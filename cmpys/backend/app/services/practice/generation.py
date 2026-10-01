"""Bounded practice generation/review on the existing configured LLM route."""

import asyncio
import json

from app.core.config import settings
from app.services.llm import get_llm_client
from app.services.llm.telemetry import record_llm_response
from app.services.practice.contracts import Activity, TextReview, Workbook


# Generation and persistence must finish before another request can reclaim
# the API lease. Reviews remain short enough for the existing review lease.
PRACTICE_GENERATION_BUDGET_SECONDS = 100
PRACTICE_GENERATION_LEASE_SECONDS = 120
PRACTICE_REVIEW_BUDGET_SECONDS = 55
PRACTICE_OUTPUT_TOKENS = 4000


def _is_provider_timeout(response) -> bool:
    error = str(getattr(response, "error", None) or "")
    return (
        error.startswith("Practice provider timeout")
        or ("request failed (" in error and "TimeoutError" in error)
        or error.casefold().strip() in {"timeout", "timed out"}
    )


async def _structured(prompt: str, payload: dict, schema, operation: str, *, recovery_response=None):
    budget = (
        PRACTICE_GENERATION_BUDGET_SECONDS
        if operation == "lesson_practice_generate"
        else PRACTICE_REVIEW_BUDGET_SECONDS
    )
    # Includes primary inference, the one authorized operational recovery,
    # and telemetry. Per-call bounds alone previously exceeded the API lease.
    async with asyncio.timeout(budget):
        return await _structured_request(
            prompt, payload, schema, operation, recovery_response=recovery_response
        )


async def _structured_request(prompt: str, payload: dict, schema, operation: str, *, recovery_response=None):
    from app.services.llm.prompt_loader import load_and_render

    system = load_and_render(prompt, {})
    from app.services.llm.client import LLMResponse
    from app.services.llm.recovery import operational_recovery_client

    if recovery_response is not None:
        client = operational_recovery_client(recovery_response, timeout=30, max_tokens=PRACTICE_OUTPUT_TOKENS)
        if client is None:
            raise ValueError("Practice recovery evidence is no longer available")
    else:
        # Live workbook attempts on GLM Flash repeatedly timed out at 45s.
        # Use the proven balanced route for this reasoning/answer-key task,
        # with compact output and enough time to finish a complete workbook.
        primary_timeout = (
            90 if operation == "lesson_practice_generate" else 45
        ) if settings.llm_provider == "zai" else 15
        client = get_llm_client(
            tier="balanced",
            timeout=primary_timeout, max_tokens=PRACTICE_OUTPUT_TOKENS, allow_fallback=False,
            thinking_level="low" if settings.llm_provider == "zai" else None
        )
    model = None
    for attempt in range(2):
        try:
            model, response = await asyncio.wait_for(
                client.generate_and_validate(
                    system_prompt=system,
                    user_prompt=json.dumps(payload, ensure_ascii=False),
                    output_model=schema,
                    repair_on_failure=False,
                ),
                timeout=primary_timeout + 3 if attempt == 0 and recovery_response is None else 32,
            )
        except TimeoutError:
            response = LLMResponse(
                data={}, error="Practice provider timeout",
                provider=getattr(client, "provider_name", None),
                model=getattr(client, "model", None),
            )
        try:
            await asyncio.wait_for(
                record_llm_response(
                    operation=operation,
                    response=response,
                    result_status="accepted" if model else "rejected",
                    metadata={"attempt": attempt + 1, **{
                        k: v for k, v in (payload.get("context") or {}).items()
                        if k in {"plan_item_id", "step_id"}
                    }, "failure_kind": (
                        "provider_timeout" if _is_provider_timeout(response)
                        else "provider_or_contract" if response.error else None
                    )},
                ),
                timeout=3,
            )
        except TimeoutError:
            pass  # Telemetry cannot extend the enclosing operation budget.
        if model is not None or attempt == 1 or recovery_response is not None:
            break
        recovery = operational_recovery_client(response, timeout=30, max_tokens=PRACTICE_OUTPUT_TOKENS)
        if recovery is None:
            break
        client = recovery
    if model is None:
        if _is_provider_timeout(response):
            raise TimeoutError("Practice provider timed out")
        raise ValueError("Practice response did not satisfy its contract")
    return model


async def generate_workbook(step: dict, context: dict) -> Workbook:
    return await _structured(
        "lesson_practice_generate.txt",
        {
            "lesson": step,
            "context": context,
        },
        Workbook,
        "lesson_practice_generate",
    )


async def review_text(activity: Activity, answers: dict, lesson: str, *, recovery_response=None) -> TextReview:
    return await _structured(
        "lesson_practice_review.txt",
        {
            "lesson": lesson[:40000],
            "activity": activity.model_dump(),
            "text_fields": [
                f.model_dump() for f in activity.fields if f.kind == "text"
            ],
            "answers": {
                f.id: answers[f"{activity.id}.{f.id}"]
                for f in activity.fields
                if f.kind == "text"
            },
        },
        TextReview,
        "lesson_practice_review",
        recovery_response=recovery_response,
    )
