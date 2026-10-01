from types import SimpleNamespace as NS

import pytest
from app.core.config import Settings, settings
from app.services.llm.client import get_llm_client
from app.services.llm.pricing import estimate_cost_usd
from app.services.llm.zai import ZaiLLMClient
from tests.test_openlux import chunk, transport


@pytest.fixture(autouse=True)
def configure(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "zai")
    monkeypatch.setattr(settings, "zai_api_key", "fake-test-key")


def test_routes_and_config():
    clients = [get_llm_client(tier=t) for t in ("fast", "balanced", "quality")]
    assert all(isinstance(c, ZaiLLMClient) for c in clients)
    assert [c.model for c in clients] == ["glm-5.3-flash", "glm-5.3", "glm-5.3"]
    assert [c.thinking_level for c in clients] == ["low", "high", "high"]
    assert settings.llm_configured
    safe = Settings(_env_file=None, llm_provider="zai", zai_api_key="fake-credential-value")
    assert "fake-credential-value" not in repr(safe) and "zai_api_key" not in safe.model_dump()
    assert not Settings(_env_file=None, llm_provider="zai").llm_configured


@pytest.mark.asyncio
async def test_glm_stream_schema_and_usage(monkeypatch):
    client = get_llm_client(max_tokens=500, thinking_level="minimal")
    usage = NS(prompt_tokens=30, completion_tokens=80, total_tokens=110)
    hidden = chunk()
    hidden.choices[0].delta.reasoning_content = "hidden reasoning"
    stream, request = transport(monkeypatch, client, [hidden, chunk('{"ok":true}', "stop"), NS(choices=[], usage=usage)])
    result = await client.generate_json("JSON system", "User")
    assert result.error is None and result.data == {"ok": True}
    assert "hidden" not in result.raw_response
    assert result.provider == "zai" and result.total_tokens == 110
    assert request["max_tokens"] == 2548
    assert request["extra_body"] == {"thinking": {"type": "enabled"}}
    assert request["reasoning_effort"] == "low"
    assert "stream_options" not in request and "max_completion_tokens" not in request
    assert stream.closed


@pytest.mark.asyncio
@pytest.mark.parametrize("finish", ["length", None, "content_filter"])
async def test_truncation_rejected(monkeypatch, finish):
    client = get_llm_client()
    transport(monkeypatch, client, [chunk('{"ok":true}', finish)])
    response = await client.generate_json("System", "User")
    assert response.error and response.data == {} and response.provider == "zai"


@pytest.mark.asyncio
async def test_transport_failure_has_unknown_cost_and_no_secret(monkeypatch):
    client = get_llm_client()
    transport(monkeypatch, client, [RuntimeError("fake-test-key private prompt")])
    response = await client.generate_json("System", "User")
    assert "fake-test-key" not in response.error and "private" not in response.error
    assert response.prompt_tokens is None and response.total_tokens is None


@pytest.mark.asyncio
async def test_no_hidden_sdk_retries():
    sdk = get_llm_client()._get_client("fake-key-unique-zai")
    assert sdk.max_retries == 0
    await sdk.close()


def test_cost_and_curriculum_route():
    from app.tasks.curriculum import _resolved_llm_route
    route = _resolved_llm_route("quality")
    assert route["primary"]["provider"] == "zai"
    assert route["primary"]["model"] == "glm-5.3"
    assert route["fallback"] is None
    assert estimate_cost_usd(model="glm-5.3", provider="zai", prompt_tokens=10000, completion_tokens=5000, total_tokens=15000) == .036
    assert estimate_cost_usd(model="glm-5.3-flash", provider="zai", prompt_tokens=10000, completion_tokens=5000, total_tokens=15000) == .004


@pytest.mark.asyncio
async def test_chat_routes_to_flash_without_gemini(monkeypatch):
    from app.services import gemini
    seen = {}
    async def text(self, system, user, *, operation):
        seen.update(model=self.model, operation=operation)
        yield "Hello"
    monkeypatch.setattr(ZaiLLMClient, "stream_text", text)
    result = [s async for s in gemini._stream_generate(system_prompt="S", contents="U", label="Test", grounded=False, tier="balanced", operation="guided_learning_stream")]
    assert result == ["Hello"] and seen["model"] == "glm-5.3-flash"


def test_outline_schema_does_not_offer_invalid_in_app_material():
    from app.services.llm.schemas import PlanItemDetailsOutlineOutput
    schema = PlanItemDetailsOutlineOutput.model_json_schema()
    assert "in_app_lesson" not in schema["$defs"]["PlanOutlineMaterialOutput"]["properties"]["type"]["enum"]


def test_execution_schema_requires_metrics_and_mission_depth():
    from app.services.llm.schemas import ExecutionBinaryTask, ExecutionPlanWeek
    from pydantic import ValidationError
    task = dict(title="Practice", description="Classify the supplied transactions", type="practice", estimated_hours=1)
    with pytest.raises(ValidationError):
        ExecutionBinaryTask.model_validate(task)
    with pytest.raises(ValidationError):
        ExecutionPlanWeek.model_validate(dict(week_number=1, primary_mission="Too short", binary_tasks=[]))
    schema = ExecutionBinaryTask.model_json_schema()
    assert "success_metric" in schema["required"]
    assert schema["properties"]["success_metric"]["type"] == "string"
