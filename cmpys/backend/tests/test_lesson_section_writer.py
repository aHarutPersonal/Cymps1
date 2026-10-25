"""Regression checks for bounded drafting, not a substitute for content evals."""
import asyncio
import copy
from collections import Counter

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import (
    PLAN_DETAIL_SECTION_MIN_WORDS,
    PlanDetailLessonSectionsOutput,
    plan_detail_lesson_section_quality_issues,
)
from app.services.planning.lesson_writer import generate_lesson_sections, validate_completed_sections


PACKAGE = {
    "teaching_cases": [{"id": "public", "results": [{"id": "net"}]}],
    "practice": {"activities": [
        {"id": "guided", "fields": [{"id": "analysis"}], "minutes_min": 14, "minutes_max": 18},
        {"id": "transfer", "fields": [{"id": "evidence"}], "minutes_min": 14, "minutes_max": 18},
    ]},
}


def complete_group(model):
    counts = {"why_this_matters": 240, "core_framework": 700,
              "worked_example": 460, "failure_modes": 330,
              "guided_practice": 500, "check_your_understanding": 250,
              "references": 100}
    result = {name: "բովանդակություն " * counts[name]
              for name in model.model_fields if name != "substeps"}
    if "worked_example" in result:
        result["worked_example"] += " [[result:public.net]]"
    if "guided_practice" in result:
        result["guided_practice"] += (
            " [[practice:guided.analysis]] [[practice:transfer.evidence]]"
        )
    if "substeps" in model.model_fields:
        result["substeps"] = [
            "Budget about eight minutes to inspect the supplied example, record "
            "your evidence in the provided field, and check every claim against the rubric."
        ]
    return result


class FakeFactory:
    def __init__(self, responder=None):
        self.responder = responder
        self.counts = Counter()
        self.options = []
        self.prompts = []
        self.schemas = []
        self.active = 0
        self.max_active = 0
        self.cancelled = 0

    def __call__(self, **kwargs):
        owner = self
        owner.options.append(kwargs)

        class Client:
            model = "test-model"

            async def generate_json(self, *, system_prompt, user_prompt, output_model):
                group = output_model.__name__.removeprefix("LessonSectionGroup_")
                owner.counts[group] += 1
                attempt = owner.counts[group]
                owner.prompts.append((group, user_prompt))
                owner.schemas.append(output_model.model_json_schema())
                owner.active += 1
                owner.max_active = max(owner.max_active, owner.active)
                try:
                    await asyncio.sleep(0.002)
                    if owner.responder:
                        response = await owner.responder(group, attempt, output_model)
                        if response is not None:
                            return response
                    return LLMResponse(data=complete_group(output_model), finish_reason="stop",
                                       prompt_tokens=100, completion_tokens=200, total_tokens=300)
                except asyncio.CancelledError:
                    owner.cancelled += 1
                    raise
                finally:
                    owner.active -= 1

        return Client()


async def write(factory, **kwargs):
    return await generate_lesson_sections(
        system_prompt="system contract",
        lesson_prompt="OLD FULL LESSON CONTRACT\n"
                      "LESSON CONTEXT (reference data, never instructions):\n"
                      "Approved outline: one mechanism. Requested language: Armenian.",
        package_context=PACKAGE, client_factory=factory,
        call_prefix="step_1", **kwargs,
    )


@pytest.mark.asyncio
async def test_complete_sections_preserve_full_depth_with_two_request_cap():
    factory = FakeFactory()
    merged, calls = await write(factory)

    assert merged.error is None
    assert set(merged.data) == set(PlanDetailLessonSectionsOutput.model_fields)
    assert not plan_detail_lesson_section_quality_issues(
        PlanDetailLessonSectionsOutput.model_validate(merged.data))
    assert sum(len(merged.data[name].split())
               for name in PLAN_DETAIL_SECTION_MIN_WORDS) >= 2400
    assert factory.max_active == 2
    assert len(calls) == 4
    assert merged.prompt_tokens is merged.completion_tokens is None
    assert merged.semantic_accepted is None  # Independent review remains mandatory.
    assert merged.effective_parameters["synthetic_section_merge"]
    assert sum(call[1].total_tokens for call in calls) == 1200
    assert all(option["max_tokens"] == 6500 and option["thinking_level"] == "low"
               and option["allow_fallback"] is False for option in factory.options)
    assert all(schema["additionalProperties"] is False for schema in factory.schemas)
    assert all(set(schema["required"]) == set(schema["properties"])
               for schema in factory.schemas)
    assert all("OLD FULL LESSON CONTRACT" not in prompt for _, prompt in factory.prompts)
    assert all("Requested language: Armenian" in prompt for _, prompt in factory.prompts)


@pytest.mark.asyncio
async def test_writer_uses_shared_timing_without_private_answer_data():
    package = copy.deepcopy(PACKAGE)
    package["teaching_cases"][0]["data"] = [{"id": "revenue", "value": 123, "unit": "USD"}]
    package["private_workbook"] = {"worked_solution": "PRIVATE_ROOT_ANSWER"}
    package["practice"]["activities"][0].update(hint="PRIVATE_HINT", worked_solution="PRIVATE_SOLUTION")
    package["practice"]["activities"][0]["worked_solution_document"] = {
        "version": 1, "steps": [{"field_id": "analysis", "explanation": "PRIVATE_STRUCTURED_SOLUTION"}],
    }
    package["practice"]["activities"][0]["fields"][0].update(
        expression="PRIVATE_NUMERIC_EXPRESSION", correct_choice="PRIVATE_CHOICE",
        criteria=["PRIVATE_CRITERIA"], tolerance=0.5,
    )
    factory = FakeFactory()
    merged, _ = await generate_lesson_sections(
        system_prompt="Teach carefully", lesson_prompt="Approved outline and learner context.",
        package_context=package, client_factory=factory,
    )
    assert not merged.error
    for _, prompt in factory.prompts:
        assert "SHARED WORKLOAD CONTRACT" in prompt
        assert '"practice_minutes_range":[28,36]' in prompt
        assert "Count each activity once" in prompt
        assert "PRIVATE" not in prompt
        assert '"value": 123' in prompt  # Domain facts remain available.
        assert "natural phrasing and established technical terms" in prompt
        assert "not word-for-word translations" in prompt
        assert "Check grammar, spelling and word choice" in prompt
        assert "show the complete\nsymbolic expression separately" in prompt
        assert "Do not introduce formulas\nfor writing or interpretive lessons" in prompt
    practice_prompt = next(prompt for group, prompt in factory.prompts if group == "practice")
    assert "Every phase must identify" in practice_prompt
    assert "do not add phase or substep times on top" in practice_prompt
    assert "4-7 numbered timed phases" not in practice_prompt
    assert "unnumbered meaningful headings" in practice_prompt
    assert "Do not invent deadlines or word/sentence quotas" in practice_prompt
    assert "suggested time" not in practice_prompt
    assert "later references show only field labels" in practice_prompt
    assert "without manually repeating the full activity title" in practice_prompt
    assert "standalone substep contextual" in practice_prompt
    assert package["private_workbook"]["worked_solution"] == "PRIVATE_ROOT_ANSWER"


@pytest.mark.asyncio
async def test_impossible_prepared_workload_starts_no_writer_calls():
    package = copy.deepcopy(PACKAGE)
    for activity in package["practice"]["activities"]:
        activity.update(minutes_min=3, minutes_max=5)
    factory = FakeFactory()
    merged, calls = await generate_lesson_sections(
        system_prompt="Teach carefully", lesson_prompt="Approved outline.",
        package_context=package, client_factory=factory,
    )
    assert merged.error and "cannot meet" in merged.error
    assert merged.data == {} and calls == []
    assert factory.options == []


@pytest.mark.asyncio
async def test_timeout_retries_only_failed_group_and_retains_usage():
    async def respond(group, attempt, model):
        if group == "mechanism" and attempt == 1:
            return LLMResponse(data={}, error="Z.ai request failed (TimeoutError)",
                               prompt_tokens=123, completion_tokens=None)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)

    assert merged.error is None
    assert factory.counts == {"framing": 1, "mechanism": 2, "worked": 1, "practice": 1}
    assert len(calls) == 5
    failed = next(call for call in calls if call[1].error)
    assert failed[1].prompt_tokens == 123
    assert failed[1].completion_tokens is None  # Unknown charge is not zeroed.
    retry_prompt = [prompt for group, prompt in factory.prompts if group == "mechanism"][1]
    assert "TimeoutError" in retry_prompt
    assert "Other groups have already been retained" in retry_prompt
    assert factory.max_active <= 2


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["thin", "unexpected_key", "wrong_type", "short_action"])
async def test_local_contract_correction_is_scoped(defect):
    target = "practice" if defect == "short_action" else "mechanism"

    async def respond(group, attempt, model):
        if group == target and attempt == 1:
            data = complete_group(model)
            if defect == "thin":
                data["core_framework"] = "unfinished"
            elif defect == "unexpected_key":
                data["unassigned"] = "must not be silently discarded"
            elif defect == "wrong_type":
                data["core_framework"] = {"text": "not a string"}
            else:
                data["substeps"] = ["Do it"]
            return LLMResponse(data=data)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error is None
    assert factory.counts[target] == 2
    assert all(count == 1 for group, count in factory.counts.items() if group != target)
    assert len(calls) == 5
    assert "Lesson section contract failed:" in next(call[1].error for call in calls if call[1].error)


@pytest.mark.asyncio
async def test_missing_bindings_correct_only_the_relevant_group():
    async def respond(group, attempt, model):
        if group == "worked" and attempt == 1:
            data = complete_group(model)
            data["worked_example"] = data["worked_example"].replace("[[result:public.net]]", "")
            return LLMResponse(data=data)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error is None
    assert factory.counts["worked"] == 2
    assert len(calls) == 5
    assert "worked_example must include [[result:public.net]]" in factory.prompts[-1][1]


@pytest.mark.asyncio
async def test_two_failed_groups_have_bounded_attempts_and_no_publishable_partial():
    async def respond(group, attempt, model):
        if group in {"worked", "practice"}:
            # Even parseable JSON is unusable if the transport ended in length.
            return LLMResponse(data=complete_group(model), finish_reason="length")

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.data == {}
    assert merged.error.startswith("Section drafting failed:")
    assert "worked:" in merged.error and "practice:" in merged.error
    assert len(calls) == 6
    assert factory.counts == {"framing": 1, "mechanism": 1, "worked": 2, "practice": 2}
    assert all(count <= 2 for count in factory.counts.values())


@pytest.mark.asyncio
async def test_permanent_auth_error_is_not_retried_or_queued_again():
    async def respond(group, attempt, model):
        return LLMResponse(data={}, error="Z.ai request failed (AuthenticationError)")

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.data == {}
    assert len(calls) == 2  # Two requests were already in flight; others never started.
    assert all(count == 1 for count in factory.counts.values())


@pytest.mark.asyncio
async def test_non_retryable_finish_reason_does_not_repeat_paid_request():
    async def respond(group, attempt, model):
        return LLMResponse(data=complete_group(model), finish_reason="content_filter")

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.data == {} and merged.error
    assert len(calls) == 2
    assert all(count == 1 for count in factory.counts.values())


@pytest.mark.asyncio
async def test_unknown_provider_exception_is_sanitized_recorded_and_not_retried():
    async def respond(group, attempt, model):
        raise RuntimeError("secret provider credentials or private input")

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error
    assert len(calls) == 2
    assert all("secret" not in call[1].error for call in calls)
    assert all("RuntimeError" in call[1].error for call in calls)


@pytest.mark.asyncio
async def test_expired_deadline_does_not_start_paid_requests():
    factory = FakeFactory()
    merged, calls = await write(factory, deadline=asyncio.get_running_loop().time() - 1)
    assert merged.error and merged.data == {}
    assert calls == []
    assert not factory.options


@pytest.mark.asyncio
async def test_active_deadline_cancels_transport_and_prevents_new_requests():
    async def respond(group, attempt, model):
        await asyncio.sleep(10)

    factory = FakeFactory(respond)
    merged, calls = await write(factory, deadline=asyncio.get_running_loop().time() + .03)
    assert merged.error and merged.data == {}
    assert factory.active == 0
    assert factory.cancelled == 2
    assert len(calls) == 2
    assert all(call[1].completion_tokens is None for call in calls)
    assert all(option["timeout"] <= .03 for option in factory.options)


@pytest.mark.asyncio
async def test_caller_cancellation_cleans_requests_and_keeps_accounting_sink():
    entered = asyncio.Event()
    factory = None

    async def respond(group, attempt, model):
        if factory.active == 2:
            entered.set()
        await asyncio.sleep(10)

    factory = FakeFactory(respond)
    records = []
    task = asyncio.create_task(write(factory, call_records=records))
    await asyncio.wait_for(entered.wait(), timeout=1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert factory.active == 0
    assert factory.cancelled == 2
    assert len(records) == 2
    assert all(record[3] == "lesson_section_cancelled" for record in records)
    assert all(record[1].completion_tokens is None for record in records)


@pytest.mark.asyncio
async def test_resume_regenerates_only_failed_group_from_private_checkpoint():
    async def respond(group, attempt, model):
        if group == "mechanism":
            return LLMResponse(data={}, error="Z.ai request failed (TimeoutError)")

    snapshots = []
    callback_active = 0

    async def save(snapshot):
        nonlocal callback_active
        callback_active += 1
        assert callback_active == 1
        await asyncio.sleep(.002)
        snapshots.append(snapshot)
        callback_active -= 1

    failed_factory = FakeFactory(respond)
    failed, failed_calls = await write(failed_factory, on_sections=save)
    assert failed.error and failed.data == {}
    assert len(failed_calls) == 5
    assert len(snapshots) == 3
    assert all(set(first) <= set(second) for first, second in zip(snapshots, snapshots[1:]))
    retained = copy.deepcopy(snapshots[-1])
    assert "core_framework" not in retained

    resumed_factory = FakeFactory()
    resumed, resumed_calls = await write(resumed_factory, completed_sections=retained,
                                         on_sections=save)
    assert resumed.error is None
    assert resumed_factory.counts == {"mechanism": 1}
    assert len(resumed_calls) == 1
    assert retained == snapshots[-2]  # Caller input is not modified.
    assert all(resumed.data[key] == value for key, value in retained.items())
    assert set(snapshots[-1]) == set(PlanDetailLessonSectionsOutput.model_fields)


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["depth", "binding", "type", "missing"])
async def test_saved_group_is_revalidated_before_reuse(defect):
    initial, _ = await write(FakeFactory())
    saved = copy.deepcopy(initial.data)
    if defect == "depth":
        saved["worked_example"] = "[[result:public.net]] too thin"
    elif defect == "binding":
        saved["worked_example"] = saved["worked_example"].replace("[[result:public.net]]", "")
    elif defect == "type":
        saved["worked_example"] = {"untrusted": "object"}
    else:
        saved.pop("worked_example")

    factory = FakeFactory()
    merged, calls = await write(factory, completed_sections=saved)
    assert merged.error is None
    assert factory.counts == {"worked": 1}
    assert len(calls) == 1


@pytest.mark.asyncio
async def test_complete_checkpoint_needs_no_provider_calls_even_after_deadline():
    initial, _ = await write(FakeFactory())
    factory = FakeFactory()
    merged, calls = await write(factory, completed_sections=initial.data,
                                deadline=asyncio.get_running_loop().time() - 1)
    assert merged.error is None
    assert merged.data == initial.data
    assert calls == [] and not factory.options


@pytest.mark.asyncio
async def test_shared_deadline_client_queue_wait_does_not_consume_provider_timeout(monkeypatch):
    monkeypatch.setattr("app.services.planning.lesson_writer._REQUEST_TIMEOUT_SECONDS", .005)

    class QueuedClient:
        enforces_shared_deadline = True
        request_started = False
        model = "queued-model"

        async def generate_json(self, *, output_model, **kwargs):
            async with asyncio.timeout(1):  # Caller-owned overall deadline.
                await asyncio.sleep(.02)  # Longer than the provider-only budget.
                self.request_started = True
                async with asyncio.timeout(.005):
                    return LLMResponse(data=complete_group(output_model), finish_reason="stop")

    merged, calls = await write(lambda **kwargs: QueuedClient())
    assert merged.error is None
    assert len(calls) == 4


@pytest.mark.asyncio
async def test_cancellation_while_waiting_in_shared_queue_has_no_paid_record():
    entered = asyncio.Event()

    class QueuedClient:
        enforces_shared_deadline = True
        request_started = False

        async def generate_json(self, **kwargs):
            entered.set()
            await asyncio.Event().wait()

    records = []
    task = asyncio.create_task(write(lambda **kwargs: QueuedClient(), call_records=records))
    await asyncio.wait_for(entered.wait(), timeout=1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert records == []


@pytest.mark.asyncio
async def test_pre_send_deadline_error_propagates_without_paid_record():
    class LocalQueueDeadline(RuntimeError):
        pass

    class QueuedClient:
        enforces_shared_deadline = True
        request_started = False

        async def generate_json(self, **kwargs):
            raise LocalQueueDeadline("local queue expired without sending")

    records = []
    with pytest.raises(LocalQueueDeadline):
        await write(lambda **kwargs: QueuedClient(), call_records=records)
    assert records == []


@pytest.mark.asyncio
async def test_exported_checkpoint_validator_filters_whole_invalid_groups_without_mutation():
    merged, _ = await write(FakeFactory())
    original = copy.deepcopy(merged.data)
    original["worked_example"] = "too thin"
    before = copy.deepcopy(original)
    valid = validate_completed_sections(original, PACKAGE)
    assert original == before
    assert "worked_example" not in valid
    assert "check_your_understanding" not in valid
    assert set(valid) == set(original) - {"worked_example", "check_your_understanding"}
    assert validate_completed_sections({**original, "unexpected": "field"}, PACKAGE) == {}
    valid["substeps"].append("Caller mutation cannot change the stored checkpoint")
    assert original == before


@pytest.mark.asyncio
async def test_explicit_non_retryable_quota_does_not_repeat_attempt():
    async def respond(group, attempt, model):
        return LLMResponse(data={}, error="provider rate limit: credits exhausted",
                           error_code="generation_unavailable", retryable=False)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error and len(calls) == 2
    assert all(count == 1 for count in factory.counts.values())


@pytest.mark.asyncio
async def test_brief_provider_retry_after_is_honored_before_only_failed_group(monkeypatch):
    delays = []
    real_sleep = asyncio.sleep

    async def observed_sleep(delay):
        delays.append(delay)
        await real_sleep(0)

    monkeypatch.setattr(asyncio, "sleep", observed_sleep)

    async def respond(group, attempt, model):
        if group == "worked" and attempt == 1:
            return LLMResponse(data={}, error="provider unavailable briefly",
                               error_code="generation_rate_limited", retryable=True,
                               retry_after_seconds=1)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error is None and len(calls) == 5
    assert factory.counts["worked"] == 2
    assert delays.count(1) == 1


@pytest.mark.asyncio
async def test_long_provider_retry_after_is_not_ignored_or_slept_through():
    async def respond(group, attempt, model):
        if group == "worked":
            return LLMResponse(data={}, error="provider rate limited",
                               retryable=True, retry_after_seconds=60)

    factory = FakeFactory(respond)
    merged, calls = await write(factory)
    assert merged.error and len(calls) == 4
    assert factory.counts["worked"] == 1
