"""Per-stage model routing (owner decision, 2026-11-07): Haiku 5.5 and gpt-6-luna back each other up."""
import asyncio
from types import SimpleNamespace as NS

import anthropic
import httpx
import openai
import pytest
from pydantic import BaseModel

from app.core.config import settings
from app.services.llm.anthropic_direct import AnthropicDirectLLMClient
from app.services.llm.client import DummyLLMClient, FallbackLLMClient, LLMResponse, get_llm_client
from app.services.llm.openai_direct import OpenAIDirectLLMClient
from app.services.llm.protocol import ProviderStreamError, provider_unavailable
from app.services.llm.routes import route_for, tutorial_attempt, tutorial_attempt_provider
from tests.llm_fakes import (anthropic_client, anthropic_transport, chunk, openai_client, openai_transport,
                             usage_chunk)


class Answer(BaseModel):
    answer: str


@pytest.fixture
def routed(monkeypatch):
    FallbackLLMClient.reset_circuits_for_tests()
    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, "anthropic_api_key", "fake-anthropic-key")
    monkeypatch.setattr(settings, "openai_api_key", "fake-openai-key")
    monkeypatch.setattr(settings, "anthropic_model", "claude-haiku-5-5")
    monkeypatch.setattr(settings, "openai_model", "gpt-6-luna")
    monkeypatch.setattr(settings, "llm_route_overrides", {})
    monkeypatch.setattr(settings, "llm_usage_telemetry_enabled", False)
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    yield
    FallbackLLMClient.reset_circuits_for_tests()


@pytest.mark.parametrize("operation, primary", [
    ("plan_item_detail_generation", "anthropic"),
    ("lesson_package_scoped_activity_repair", "anthropic"),
    ("lesson_review_schema_repair", "anthropic"),
    ("plan_item_tutorial_outline", "anthropic"),
    ("plan_backbone_generation", "anthropic"),
    ("plan_week_generation", "anthropic"),
    ("interview_stream", "openai"),
    ("guided_learning_stream", "openai"),
    ("comparison_stream", "openai"),
    ("blueprint_stream", "openai"),
    ("comparison_scores", "openai"),
    ("lesson_practice_review", "openai"),
    ("lesson_practice_generate", "openai"),
    ("book_module_generation", "openai"),
    ("book_companion_generate", "openai"),
    ("idol_persona_generation", "openai"),
    ("daily_feed_generation", "openai"),
    (None, "openai"),
])
def test_owner_assignment_routes_each_stage_with_the_other_model_as_backup(routed, operation, primary):
    backup = "openai" if primary == "anthropic" else "anthropic"
    assert route_for(operation) == (primary, backup)


def test_overrides_switch_a_stage_or_one_operation(routed, monkeypatch):
    monkeypatch.setattr(settings, "llm_route_overrides", {"books": "anthropic", "idol_persona_generation": "anthropic"})
    assert route_for("book_fidelity_review") == ("anthropic", "openai")
    assert route_for("idol_persona_generation") == ("anthropic", "openai")
    assert route_for("idol_profile_extraction") == ("openai", "anthropic")


def test_dummy_mode_never_builds_a_provider_client(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "dummy")
    assert isinstance(get_llm_client(operation="plan_week_generation"), DummyLLMClient)


def test_factory_wraps_the_primary_with_its_backup(routed):
    client = get_llm_client(operation="plan_week_generation", tier="quality", timeout=30, max_tokens=900)
    assert isinstance(client, FallbackLLMClient)
    assert isinstance(client.primary, AnthropicDirectLLMClient) and isinstance(client.fallback, OpenAIDirectLLMClient)
    assert (client.primary.model, client.fallback.model) == ("claude-haiku-5-5", "gpt-6-luna")
    assert client.primary.effort == "high" and client.max_tokens == 900 and client.timeout == 30
    single = get_llm_client(operation="interview_stream", allow_fallback=False)
    assert isinstance(single, OpenAIDirectLLMClient) and single.effort == "low"
    forced = get_llm_client(operation="interview_stream", provider="anthropic")
    assert isinstance(forced, AnthropicDirectLLMClient)


def test_a_missing_key_routes_to_the_configured_model_or_fails_closed(routed, monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", None)
    assert isinstance(get_llm_client(operation="plan_week_generation"), OpenAIDirectLLMClient)
    monkeypatch.setattr(settings, "openai_api_key", None)
    client = get_llm_client(operation="plan_week_generation")
    assert isinstance(client, AnthropicDirectLLMClient)
    response = asyncio.run(client.generate_json("System", "User", output_model=Answer))
    assert response.error_code == "generation_unavailable" and response.retryable is False
    assert provider_unavailable(response)


class Scripted:
    def __init__(self, provider, *responses):
        self.provider_name, self.model, self.responses, self.calls = provider, provider + "-model", list(responses), 0

    async def generate_json(self, **_):
        self.calls += 1
        return self.responses.pop(0)


def test_backup_takes_over_only_when_the_primary_is_unavailable(routed):
    outage = LLMResponse(data={}, error="anthropic request failed (InternalServerError; 529)",
                         error_code="generation_failed", provider="anthropic")
    primary, backup = Scripted("anthropic", outage), Scripted("openai", LLMResponse(data={"answer": "ok"}))
    response = asyncio.run(FallbackLLMClient(primary, backup).generate_json("s", "u"))
    assert response.data == {"answer": "ok"} and response.fallback_from_provider == "anthropic"

    FallbackLLMClient.reset_circuits_for_tests()
    malformed = LLMResponse(data={}, error="anthropic request failed (JSONDecodeError; Expecting value)",
                            retryable=True, provider="anthropic")
    primary, backup = Scripted("anthropic", malformed), Scripted("openai", LLMResponse(data={"answer": "x"}))
    response = asyncio.run(FallbackLLMClient(primary, backup).generate_json("s", "u"))
    assert response is malformed and backup.calls == 0


def test_a_tutorial_attempt_uses_one_model_and_a_fresh_attempt_switches(routed, monkeypatch):
    from app.tasks.plans import _tutorial_client

    assert [tutorial_attempt_provider(n) for n in range(3)] == ["anthropic", "openai", "anthropic"]
    outline = _tutorial_client(timeout=45, max_tokens=4000, tier="balanced", thinking_level="low")
    assert isinstance(outline, FallbackLLMClient)  # the outline keeps the plan route's backup
    with tutorial_attempt(0):
        first = _tutorial_client(timeout=45, max_tokens=4000, tier="balanced", thinking_level="low")
    with tutorial_attempt(1):
        second = _tutorial_client(timeout=45, max_tokens=4000, allow_fallback=True)
    assert isinstance(first, AnthropicDirectLLMClient) and isinstance(second, OpenAIDirectLLMClient)
    monkeypatch.setattr(settings, "anthropic_api_key", None)
    with tutorial_attempt(0):
        assert isinstance(_tutorial_client(timeout=45, max_tokens=4000), OpenAIDirectLLMClient)


def test_operational_recovery_moves_to_the_other_model(routed, monkeypatch):
    from app.services.llm.recovery import CompleteRecoveryClient, operational_recovery_client

    outage = LLMResponse(data={}, error="anthropic request failed (APIConnectionError; connection)",
                         error_code="generation_failed", provider="anthropic")
    recovery = operational_recovery_client(outage, timeout=30, max_tokens=900)
    assert isinstance(recovery, CompleteRecoveryClient) and recovery.provider_name == "openai"
    content = LLMResponse(data={}, error="anthropic request failed (ValueError; finish=length)", provider="anthropic")
    assert operational_recovery_client(content, timeout=30, max_tokens=900) is None
    monkeypatch.setattr(settings, "openai_api_key", None)
    assert operational_recovery_client(outage, timeout=30, max_tokens=900) is None


def test_anthropic_request_contract_and_native_schema():
    client = anthropic_client(max_tokens=2600, reasoning_reserve=2048, thinking_level="medium")
    seen = anthropic_transport(client, '{"answer": "ok"}')
    response = asyncio.run(client.generate_json("Reply.", "Go.", output_model=Answer))
    assert response.error is None and response.data == {"answer": "ok"} and response.finish_reason == "stop"
    assert (response.provider, response.prompt_tokens, response.completion_tokens) == ("anthropic", 31, 47)
    assert seen["max_tokens"] == 4648 and seen["output_config"]["effort"] == "medium"
    assert seen["output_config"]["format"]["type"] == "json_schema"
    assert "temperature" not in seen and "betas" not in seen  # Haiku has no server-side fallback


@pytest.mark.parametrize("status, body, code, retryable", [
    (400, {"type": "error", "error": {"type": "invalid_request_error", "message": "Your credit balance is too low"}},
     "generation_unavailable", False),
    (401, {}, "generation_unavailable", False),
    (429, {}, "generation_rate_limited", True),
    (529, {}, "generation_failed", True),
])
def test_anthropic_failures_are_sanitized_and_classified(status, body, code, retryable):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    error = anthropic.APIStatusError("PRIVATE upstream text", response=httpx.Response(status, request=request),
                                     body=body)
    client = anthropic_client()
    anthropic_transport(client, "", error=error)
    response = asyncio.run(client.generate_json("Reply.", "Go.", output_model=Answer))
    assert (response.error_code, response.retryable) == (code, retryable)
    assert "PRIVATE" not in response.error and response.error.startswith("anthropic request failed (")
    assert response.prompt_tokens == 0  # rejected before any stream event: not billed


def test_openai_failures_share_the_vocabulary_and_protocol_categories():
    client = openai_client(max_tokens=900, reasoning_reserve=0)
    openai_transport(client, [chunk('{"answer": "a", "answer": "b"}', "stop"), usage_chunk()])
    response = asyncio.run(client.generate_json("Reply.", "Go.", output_model=Answer))
    assert response.error.startswith("openai request failed (JSONProtocolError;")
    assert response.effective_parameters["json_protocol_error"] == "duplicate_property"
    assert not provider_unavailable(response)

    request = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
    quota = openai.RateLimitError("PRIVATE", response=httpx.Response(429, request=request),
                                  body={"code": "insufficient_quota"})
    client = openai_client()
    openai_transport(client, [])
    async def reject(**_):
        raise quota
    client._client.chat.completions.create = reject
    response = asyncio.run(client.generate_json("Reply.", "Go.", output_model=Answer))
    assert response.error_code == "generation_unavailable" and response.retryable is False
    assert "PRIVATE" not in response.error


def test_text_streams_yield_visible_text_and_record_usage(monkeypatch):
    recorded = []

    async def record(records, **_):
        recorded.extend(records)
        return True
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", record)

    async def collect(client):
        return [piece async for piece in client.stream_text("System", "User", operation="interview_stream")]

    claude = anthropic_client(max_tokens=500)
    seen = anthropic_transport(claude, "Hello there?")
    assert asyncio.run(collect(claude)) == ["Hello there?"]
    assert "temperature" not in seen and seen["max_tokens"] == 500 + claude.reasoning_reserve
    luna = openai_client(max_tokens=500)
    _, params = openai_transport(luna, [chunk("Hi"), chunk(" you?", "stop"), usage_chunk()])
    assert asyncio.run(collect(luna)) == ["Hi", " you?"]
    assert params["reasoning_effort"] == "low" and "response_format" not in params
    assert [(r.provider, r.operation, r.success) for r in recorded] == [
        ("anthropic", "interview_stream", True), ("openai", "interview_stream", True)]


def test_routed_stream_switches_models_only_before_any_text(routed, monkeypatch):
    from app.services.llm import client as client_module

    def build(provider, **_):
        stub = NS(provider_name=provider)

        async def stream_text(system_prompt, user_prompt, *, operation):
            if behaviour[provider] == "unavailable":
                raise ProviderStreamError(provider, "RateLimitError", code="generation_rate_limited", retryable=True)
            yield f"{provider} says hi"
            if behaviour[provider] == "drops":
                raise ProviderStreamError(provider, "APIError", code="generation_failed", retryable=True)
        stub.stream_text = stream_text
        return stub
    monkeypatch.setattr(client_module, "direct_client", build)

    async def collect():
        return [piece async for piece in client_module.stream_routed_text(
            "System", "User", operation="interview_stream", max_tokens=500)]

    behaviour = {"openai": "unavailable", "anthropic": "ok"}
    assert asyncio.run(collect()) == ["anthropic says hi"]
    behaviour = {"openai": "drops", "anthropic": "ok"}
    with pytest.raises(ProviderStreamError):
        asyncio.run(collect())


def test_dummy_streams_work_offline(monkeypatch):
    from app.services.llm.client import stream_routed_text

    monkeypatch.setattr(settings, "llm_provider", "dummy")

    async def collect():
        return [piece async for piece in stream_routed_text("s", "u", operation="guided_learning_stream",
                                                            max_tokens=900)]
    assert asyncio.run(collect()) == ["[dummy guided_learning_stream reply]"]


def test_retired_gateway_settings_in_an_old_env_file_are_ignored(tmp_path):
    from app.core.config import Settings

    env = tmp_path / ".env"
    env.write_text("OPENLUX_API_KEY=x\nZAI_MODEL=glm\nYUNWU_API_KEY=y\nOPENROUTER_MODEL=z\n"
                   "BOOK_NARRATION_TTS_MODEL=speech\nLLM_PROVIDER=routed\n")
    assert Settings(_env_file=env).llm_provider in {"routed", "dummy"}  # an LLM_PROVIDER env var wins
