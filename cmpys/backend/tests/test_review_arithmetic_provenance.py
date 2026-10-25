"""A reviewer formula is evidence to verify, not authoritative source meaning."""
import copy
import json
import re
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    ReviewEvidencePatch, _NUMBER_LITERAL, _numeric_content, _numeric_source,
    numeric_spans, review_lesson, source_arithmetic_failures, source_equation_failures,
)
from app.services.planning.package_review import review_package
from tests.lesson_package_fixtures import package_payload


def numeric_package(source="Total expense is 55."):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = [
        {"id": key, "label": label, "value": value}
        for key, label, value in [("cash", "Cash sales", 90), ("credit", "Credit sales", 20),
                                  ("prior", "Prior collections", 10), ("paid", "Paid expense", 40),
                                  ("unpaid", "Unpaid expense", 15), ("collision", "Unrelated amount", 55)]
    ]
    activity["fields"] = [{"id": "expense", "label": "Total expense", "kind": "number",
                            "expression": "paid + unpaid"}]
    activity["worked_solution"] = source + " Explain how the period's components support your conclusion."
    return LessonPackage.model_validate(payload)


def calculation(expression="cash + credit - paid + prior", result=55):
    return {"claim_ids": ["n1"], "case_id": "practice.guided",
            "expression": expression, "claimed_result": result}


def verdict():
    return {"acceptable": True, "issues": [], "contains_calculations": True,
            "calculations": [calculation()]}


@pytest.fixture(autouse=True)
def no_telemetry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


async def run(kind, first, second=None, *, source="Total expense is 55."):
    package = numeric_package(source)
    if kind == "final":
        first = {**first, "practice_minutes": 40, "advisories": ["Optional style note."]}
    responses = [LLMResponse(data=copy.deepcopy(first))]
    if second is not None:
        responses.append(second if isinstance(second, LLMResponse) else LLMResponse(data=copy.deepcopy(second)))
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(side_effect=responses))
    factory = Mock(return_value=client)
    if kind == "preflight":
        result = await review_package(package, {}, {}, client_factory=factory)
    else:
        result = await review_lesson({"lesson_content": "A careful interpretation connects each fact to the task."},
                                    context={"lesson_package": package.review_context()}, client_factory=factory)
    return result, client, factory, responses


@pytest.mark.parametrize("source", [
    "40 + 15 = 55.", "100/3 = 33.3.", "100 / 3 = (33.3).", "33.3 = 100/3.",
    "1 200 −200 = 1 000։", "1\u00a0200 −200 = 1\u202f000.", "2 × 25 = 50.",
    "5.35 / 2 = 2.68.", "40 / 200 = 20%.", "40 / 200 = 20 %.",
    "2 * 50 = 1 hundred.", "2 * 50 = 1\u00a0hundred.",
    "r1 + 5 = 8.", "40 + x = 8.", "x + 40 = 8.", "1e3 + 5 = 8.",
    "2 ** 3 = 9.", "2^3 = 9.", "2³ = 9.", "8–10 = 20.",
    "5 + 10 <= 20.", "5 + 10 >= 20.", "5 + 10 != 20.",
    "https://example.invalid/?x=5+10=20", "See www.example.invalid/x=5+10=20",
    "The expense is 55, while unrelated cash flow is 80.",
    "Incorrect: 40 + 15 = 60. The correct total is 55.",
    "Incorrect:\n40 + 15 = 60.", "Common error՝\n40 + 15 = 60.",
    'A learner writes "40 + 15 = 60".', "> 40 + 15 = 60.",
])
def test_source_checker_does_not_invent_semantics_for_correct_or_unsupported_equations(source):
    assert source_equation_failures({"lesson_content": source}) == []


@pytest.mark.parametrize("source", [
    "40 + 15 = 60.", "100/3 = 33.4.", "1 200 −200 = 900։", "2 × 25 = 60.",
    "5.35/2 = 2.67.", "20 + 30 = 50 = 55.", "40+15=60. 40+15=55.",
])
def test_source_checker_proves_wrong_explicit_equations_independently(source):
    errors = source_equation_failures({"lesson_content": source})
    assert errors and all("explicit source equation is incorrect" in error for error in errors)


@pytest.mark.parametrize("marked_first", [True, False])
def test_duplicate_equations_keep_their_own_counterexample_context(marked_first):
    assertion = "40 + 15 = 60."
    marked = "Incorrect:\n  " + assertion
    parts = [marked, assertion] if marked_first else [assertion, marked]
    errors = source_equation_failures({"lesson_content": "\n\n".join(parts)})
    assert len(errors) == 1
    assert errors[0].startswith("n2:" if marked_first else "n1:")


@pytest.mark.parametrize("marked_first", [True, False])
def test_duplicate_canonical_assertions_keep_their_own_counterexample_context(marked_first):
    assertion = "Total expense is 60."
    marked = "Incorrect:\n  " + assertion
    parts = [marked, assertion] if marked_first else [assertion, marked]
    package = numeric_package("\n\n".join(parts))
    errors = source_arithmetic_failures({}, package.review_context())
    assert len(errors) == 1 and "canonical field" in errors[0]
    assert errors[0].startswith("n2:" if marked_first else "n1:")


def test_quoted_duplicate_does_not_reassign_unmarked_equation_offset():
    source = 'Quoted example: "40 + 15 = 60."\n\n40 + 15 = 60.'
    errors = source_equation_failures({"lesson_content": source})
    assert len(errors) == 1 and errors[0].startswith("n2:")


@pytest.mark.parametrize("opening,closing", [('"', '"'), ('“', '”'), ('«', '»'), ('```', '```'), ('~~~', '~~~')])
@pytest.mark.parametrize("canonical", [False, True])
def test_multiline_quoted_occurrence_does_not_hide_identical_unquoted_assertion(opening, closing, canonical):
    assertion = "Total expense is 60." if canonical else "40 + 15 = 60."
    source = f"{opening}\n{assertion}\n{closing}\n\n{assertion}"
    errors = (source_arithmetic_failures({}, numeric_package(source).review_context()) if canonical
              else source_equation_failures({"lesson_content": source}))
    assert len(errors) == 1 and errors[0].startswith("n2:")


@pytest.mark.parametrize("text", [
    "", "\n\n  ", "### Step 1\n40 + 15 = 60.\nIncorrect:\n40 + 15 = 60.",
    "Առաջինը 3.50 է։Երկրորդը 4.25 է։\n1 200 −200 = 1 000։",
    "  First 10.\n\tSecond 20! Third 30?\n\n", "第一 10。第二 20！第三 30？",
    'Quoted: "40 + 15 = 60."\n40 + 15 = 60. 40 + 15 = 60.',
    "Step 1: Read.\n(1) Read (2) Apply (3) Check.\n1) Read, 2) Apply, 3) Check.",
])
def test_occurrence_inventory_preserves_original_split_ids_and_text(text):
    lesson = {"lesson_content": text, "substeps": ["First 10.", "Քայլ 2՝ կարդացեք"]}
    package = numeric_package("Total expense is 60.").review_context()
    source = _numeric_source(lesson, package)
    original = [part.strip() for part in re.split(r"(?<=[.!?])\s+|(?<=[։。！？])\s*|\n+", source)
                if _NUMBER_LITERAL.search(_numeric_content(part))]
    assert numeric_spans(lesson, package) == {f"n{i + 1}": span for i, span in enumerate(original)}


def test_marked_public_duplicate_cannot_hide_private_canonical_assertion():
    package = numeric_package("Total expense is 60.")
    errors = source_arithmetic_failures({"lesson_content": "Incorrect:\nTotal expense is 60."}, package.review_context())
    assert len(errors) == 1 and errors[0].startswith("n2:")


def test_marked_activity_duplicate_cannot_hide_another_activity_assertion():
    payload = numeric_package("Incorrect:\nTotal expense is 60.").model_dump(mode="json")
    guided, transfer = payload["workbook"]["activities"]
    transfer["data"] = copy.deepcopy(guided["data"])
    transfer["fields"] = [{**guided["fields"][0], "id": "transfer_expense"}]
    transfer["worked_solution"] = "Total expense is 60. Explain which components belong to this period."
    errors = source_arithmetic_failures({}, LessonPackage.model_validate(payload).review_context())
    assert len(errors) == 1 and errors[0].startswith("n2:")
    assert "practice.transfer.transfer_expense" in errors[0]


@pytest.mark.parametrize("lesson", [
    {"lesson_content": "Unrelated heading:", "substeps": ["40 + 15 = 60."]},
    {"lesson_content": "", "substeps": ["Unrelated heading:", "40 + 15 = 60."]},
])
def test_label_context_cannot_cross_lesson_and_substep_fields(lesson):
    errors = source_equation_failures(lesson)
    assert len(errors) == 1 and errors[0].startswith("n1:")


def test_label_context_cannot_cross_private_fields_or_activities():
    payload = numeric_package("40 + 15 = 60.").model_dump(mode="json")
    guided, transfer = payload["workbook"]["activities"]
    guided["instructions"] = "An unrelated label introducing the task:"
    guided["hint"] = "An unrelated label introducing the hint:"
    transfer["instructions"] = "40 + 15 = 60. Check the shown arithmetic carefully."
    package = LessonPackage.model_validate(payload)
    errors = source_equation_failures({"lesson_content": "Unrelated heading:"}, package.review_context())
    assert len(errors) == 2
    assert [error.split(":", 1)[0] for error in errors] == ["n1", "n2"]


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_wrong_reviewer_formula_for_correct_canonical_total_gets_existing_patch(kind, no_telemetry):
    (errors, response, _), client, factory, replies = await run(
        kind, verdict(), {"calculations": [calculation("paid + unpaid")]})
    assert not errors and response.error is None and response.data["acceptable"] is True
    assert client.generate_json.await_count == 2 and no_telemetry.await_count == 1
    assert issubclass(client.generate_json.await_args_list[1].kwargs["output_model"], ReviewEvidencePatch)
    feedback = json.loads(client.generate_json.await_args_list[1].kwargs["user_prompt"])
    assert any("= 80, not 55" in error for error in feedback["verification_defects"])
    assert len(feedback["prior_evidence"]["calculations"]) == 1
    assert replies[0].error is not None
    if kind == "preflight":
        factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=2000,
                                        thinking_level="low", allow_fallback=False)
    else:
        assert response.data["advisories"] == ["Optional style note."]
        assert [call.kwargs["timeout"] for call in factory.call_args_list] == [120, 90]
        assert [call.kwargs["max_tokens"] for call in factory.call_args_list] == [8000, 4000]


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_explicit_wrong_source_equation_is_terminal_even_with_correct_unrelated_proof(kind):
    # 55 is a real unrelated raw datum. The reviewer cannot use that numerical
    # coincidence to erase an explicit wrong source equation.
    first = verdict()
    first["calculations"] = [calculation("collision + prior - prior")]
    (errors, response, _), client, _, _ = await run(kind, first, source="40 + 20 = 55.")
    assert errors and "explicit source equation is incorrect" in errors[0]
    assert response.error is None and not response.data["acceptable"]
    assert client.generate_json.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_exact_canonical_claim_cannot_retry_into_unrelated_correct_formula(kind):
    first = verdict()
    first["calculations"] = [calculation("paid + unpaid", result=60)]
    # The unrelated formula evaluates to 60, but cannot redefine expense.
    malicious_patch = {"calculations": [calculation("cash - credit - prior", result=60)]}
    (errors, response, _), client, _, _ = await run(
        kind, first, malicious_patch, source="Total expense is 60.")
    assert errors and "canonical field practice.guided.expense computes 55, not 60" in errors[0]
    assert response.error is None and not response.data["acceptable"]
    assert client.generate_json.await_count == 1


def test_canonical_claim_mapping_requires_exact_owned_label_not_value_or_proximity():
    package = numeric_package("Profit depends on total expense, which is described as 60.")
    assert source_arithmetic_failures({}, package.review_context()) == []
    # A public span cannot silently inherit a private activity's similarly
    # named field. The independently reviewed private source remains correct.
    package = numeric_package()
    assert source_arithmetic_failures({"lesson_content": "Total expense is 60."}, package.review_context()) == []
    other = package.model_dump(mode="json")
    other["workbook"]["activities"][1]["worked_solution"] = "Total expense is 60. Explain the qualitative tradeoff."
    assert source_arithmetic_failures({}, LessonPackage.model_validate(other).review_context()) == []
    counterexample = numeric_package("Incorrect:\nTotal expense is 60.")
    assert source_arithmetic_failures({}, counterexample.review_context()) == []


def test_ambiguous_same_activity_canonical_labels_are_not_guessed():
    payload = numeric_package("Total expense is 60.").model_dump(mode="json")
    field = payload["workbook"]["activities"][0]["fields"][0]
    payload["workbook"]["activities"][0]["fields"].append({**field, "id": "other", "expression": "cash - credit - prior"})
    assert source_arithmetic_failures({}, LessonPackage.model_validate(payload).review_context()) == []


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
@pytest.mark.parametrize("patch", [
    {}, {"calculations": [calculation()]},
    {"literal_facts": [{"claim_id": "n1", "case_id": "practice.guided", "datum_ids": ["collision"]}]},
    {"acceptable": True, "calculations": [calculation("paid + unpaid")]},
    LLMResponse(data={}, error="Provider unavailable"),
])
async def test_uncertain_source_is_never_approved_without_valid_corrected_evidence(kind, patch):
    (errors, response, _), client, _, _ = await run(kind, verdict(), patch)
    assert errors and response.error
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_negative_semantic_verdict_stays_terminal_regardless_of_reviewer_math(kind):
    first = {**verdict(), "acceptable": False, "issues": ["The claim confuses profit and expense."]}
    (errors, response, _), client, _, _ = await run(kind, first)
    assert errors == first["issues"] and response.error is None
    assert client.generate_json.await_count == 1
