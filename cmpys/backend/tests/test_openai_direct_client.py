"""The direct OpenAI client sends gpt-6-luna the pilots' tested contract.

gpt-6-luna rejects temperature and max_tokens; the client sends
reasoning_effort, max_completion_tokens and a strict schema instead.
"""
import asyncio
from types import SimpleNamespace as NS

from pydantic import BaseModel

from app.core.config import settings
from app.services.llm.openai_direct import OpenAIDirectLLMClient


class Answer(BaseModel):
    answer: str
    note: str = ""  # optional, not nullable: strict mode adds a null that is dropped again


def fake_stream(text, seen):
    async def create(**params):
        seen.append(params)

        async def chunks():
            yield NS(model="gpt-6-luna", usage=None, choices=[NS(index=0, finish_reason=None,
                                                                 delta=NS(content=text, refusal=None))])
            yield NS(model="gpt-6-luna", usage=NS(prompt_tokens=10, completion_tokens=5, prompt_tokens_details=None,
                                                  completion_tokens_details=None),
                     choices=[NS(index=0, finish_reason="stop", delta=NS(content="", refusal=None))])

        class Stream:
            def __aiter__(self):
                return chunks()

            async def close(self):
                return None

        return Stream()
    return NS(chat=NS(completions=NS(create=create)))


def test_a_request_sends_the_reasoning_model_contract_and_a_strict_schema():
    seen = []
    client = OpenAIDirectLLMClient(model="gpt-6-luna", max_tokens=2600, reasoning_reserve=2048)
    client._client = fake_stream('{"answer": "ok", "note": null}', seen)
    response = asyncio.run(client.generate_json(system_prompt="Reply.", user_prompt="Go.", output_model=Answer))
    assert response.error is None and response.data == {"answer": "ok"}  # the added null is dropped
    [params] = seen
    assert params["max_completion_tokens"] == 4648
    assert "max_tokens" not in params and "temperature" not in params
    assert params["response_format"]["type"] == "json_schema"
    assert params["response_format"]["json_schema"]["strict"] is True
    assert params["reasoning_effort"] == "low" and params["store"] is False


def test_a_missing_key_is_a_recorded_failure_not_a_crash(monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", None)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    response = asyncio.run(OpenAIDirectLLMClient(model="gpt-6-luna").generate_json(
        system_prompt="Reply.", user_prompt="Go.", output_model=Answer))
    assert response.error and response.data == {} and response.retryable is False
    assert response.error_code == "generation_unavailable" and response.provider == "openai"
