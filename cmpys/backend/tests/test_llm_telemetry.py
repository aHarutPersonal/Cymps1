from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import BaseModel

from app.core.config import settings
from app.services.llm.client import BaseLLMClient, LLMResponse
from app.services.llm.telemetry import (
    UsageRecord,
    infer_provider,
    record_usage_records,
    usage_record_from_response,
)


def test_usage_record_preserves_total_tokens_and_outcome():
    response = LLMResponse(
        data={"ok": True},
        model="gemini-2.5-flash",
        prompt_tokens=120,
        completion_tokens=80,
        total_tokens=350,
        duration_ms=1234.5,
    )

    record = usage_record_from_response(
        operation="plan_generation",
        response=response,
        result_status="schema_valid",
        quality_score=0.95,
    )

    assert record.provider == "gemini"
    assert record.total_tokens == 350
    assert record.result_status == "schema_valid"
    assert record.quality_score == 0.95


def test_usage_record_falls_back_to_visible_token_sum():
    response = LLMResponse(
        data={},
        model="gpt-4.1-mini",
        prompt_tokens=20,
        completion_tokens=30,
    )

    record = usage_record_from_response(operation="feed_generation", response=response)

    assert record.total_tokens == 50
    assert infer_provider(record.model) == "openai"


def test_yunwu_provider_is_preserved_for_gateway_models(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    response = LLMResponse(data={}, model="gpt-5.6-luna")

    record = usage_record_from_response(operation="extraction", response=response)

    assert record.provider == "yunwu"


def test_fallback_response_records_actual_provider_and_reason(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    response = LLMResponse(
        data={"ok": True},
        model="gemini-2.5-flash",
        provider="gemini",
        fallback_from_model="grok-4.5",
        fallback_from_provider="yunwu",
        fallback_error="timeout",
    )

    record = usage_record_from_response(operation="generation", response=response)

    assert record.provider == "gemini"
    assert record.metadata["fallback_from_model"] == "grok-4.5"
    assert record.metadata["fallback_from_provider"] == "yunwu"
    assert record.metadata["fallback_error"] == "timeout"


@pytest.mark.asyncio
async def test_record_usage_adds_events_to_existing_transaction(monkeypatch):
    monkeypatch.setattr(settings, "llm_usage_telemetry_enabled", True)
    db = AsyncMock()
    db.add_all = MagicMock()
    db.begin_nested = MagicMock(return_value=AsyncMock())
    record = UsageRecord(
        operation="book_module_generation",
        model="gemini-2.5-flash",
        provider="gemini",
        total_tokens=500,
        result_status="quality_passed",
        quality_score=0.9,
    )

    await record_usage_records([record], db=db)

    db.add_all.assert_called_once()
    event = db.add_all.call_args.args[0][0]
    assert event.operation == "book_module_generation"
    assert event.total_tokens == 500
    assert event.quality_score == 0.9
    assert event.estimated_cost_usd is not None
    assert event.estimated_cost_usd > 0
    assert event.metadata_json["pricing_version"].startswith("multi-provider-")
    db.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_unknown_test_model_is_not_persisted(monkeypatch):
    monkeypatch.setattr(settings, "llm_usage_telemetry_enabled", True)
    db = AsyncMock()
    db.add_all = MagicMock()

    await record_usage_records(
        [UsageRecord(operation="test", model="unknown", provider="unknown")],
        db=db,
    )

    db.add_all.assert_not_called()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_validation_repair_aggregates_both_call_usage():
    class Output(BaseModel):
        count: int

    class Client(BaseLLMClient):
        def __init__(self):
            self.responses = [
                LLMResponse(
                    data={"count": "not-a-number"},
                    model="gemini-2.5-flash",
                    prompt_tokens=100,
                    completion_tokens=20,
                    total_tokens=150,
                    duration_ms=1000,
                ),
                LLMResponse(
                    data={"count": 3},
                    model="gemini-2.5-flash",
                    prompt_tokens=140,
                    completion_tokens=30,
                    total_tokens=200,
                    duration_ms=1200,
                ),
            ]

        async def generate_json(self, **kwargs):
            return self.responses.pop(0)

    validated, response = await Client().generate_and_validate(
        system_prompt="system",
        user_prompt="user",
        output_model=Output,
    )

    assert validated == Output(count=3)
    assert response.retried is True
    assert response.prompt_tokens == 240
    assert response.completion_tokens == 50
    assert response.total_tokens == 350
    assert response.duration_ms == 2200
