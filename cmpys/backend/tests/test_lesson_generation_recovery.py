from tests.section_client_fixture import section_client, structured_package_fixture
import copy
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair
from app.services.planning.lesson_review import LessonReview, grounded_failures
from app.services.llm.schemas import PlanItemDetailsOutlineOutput
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.lesson_package_fixtures import package_payload
from tests.test_plan_detail_output_schema import _outline_payload, _lesson_sections_payload


def test_captured_package_tail_moves_losslessly_and_keeps_source_immutable():
    from app.services.planning.lesson_package import parse_package_response
    raw = json.loads((Path(__file__).parent / "fixtures/accounting_package_misnested_tail.json").read_text())
    original = copy.deepcopy(raw)
    result = parse_package_response(raw)
    expected = copy.deepcopy(raw)
    for key in ("hint", "worked_solution", "minutes_min", "minutes_max"):
        expected["workbook"]["activities"][-1][key] = expected["workbook"].pop(key)
    assert result == LessonPackage.model_validate(expected)
    assert raw == original
    assert result.practice_range == (28, 42)


@pytest.mark.parametrize("defect", ["partial_tail", "ambiguous", "overlap", "unknown", "bad_formula"])
def test_package_tail_recovery_rejects_ambiguity_and_invalid_content(defect):
    from app.services.planning.lesson_package import parse_package_response
    raw = json.loads((Path(__file__).parent / "fixtures/accounting_package_misnested_tail.json").read_text())
    wb = raw["workbook"]
    if defect == "partial_tail":
        wb.pop("hint")
    elif defect == "ambiguous":
        wb["activities"][0].pop("hint")
    elif defect == "overlap":
        wb["activities"][-1]["hint"] = "A conflicting activity hint already exists."
    elif defect == "unknown":
        wb["unexpected"] = "must not be discarded"
    else:
        numeric = next(field for field in wb["activities"][0]["fields"] if field["kind"] == "number")
        numeric["expression"] = "invented_input / 0"
    with pytest.raises(ValueError):
        parse_package_response(raw)


@pytest.mark.asyncio
async def test_package_tail_recovery_spends_no_extra_request(monkeypatch):
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    raw = json.loads((Path(__file__).parent / "fixtures/accounting_package_misnested_tail.json").read_text())
    # Exercise the same misplaced envelope with the current generation schema;
    # the captured legacy payload remains covered unchanged above.
    tail = raw["workbook"]
    tail["activities"][-1]["worked_solution"] = tail.pop("worked_solution")
    raw = structured_package_fixture(raw)
    raw["workbook"]["worked_solution"] = raw["workbook"]["activities"][-1].pop("worked_solution")
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=raw)))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is not None and not response.error
    assert client.generate_json.await_count == 1


@pytest.mark.parametrize("span,passes", [
    ("Operating profit: 14 million.", True),
    ("Operating profit: 19 million.", False),
    ("The calculated operating profit is 14 million.", False),
    ("Operating profit: 7 + 7 = 14 million.", False),
    ("Operating profit: 14 million; interest expense: 4 million.", True),
])
def test_supplied_financial_facts_are_not_mistaken_for_unchecked_results(span, passes):
    package = {"teaching_cases": [{"id": "company", "data": [
        {"label": "Operating profit", "value": 14},
        {"label": "Interest expense", "value": 4},
    ]}]}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], literal_fact_ids=["n1"])
    assert (not grounded_failures(review, {"lesson_content": span}, package)) == passes


@pytest.mark.parametrize("quote,passes", [
    ("Ledger Oil Co. has interest coverage 3.5.", True),
    ("has interest coverage 3.5.", True),
    ("Invented Company Co. has interest coverage 3.5.", False),
    ("Ledger Oil Co. has interest coverage 4.5.", False),
])
def test_verbatim_numeric_binding_survives_abbreviation_boundaries(quote, passes):
    source = "Ledger Oil Co. has interest coverage 3.5."
    package = {"teaching_cases": [{"id": "company", "data": [{"value": 14}, {"value": 4}]}]}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
        contains_calculations=True, calculations=[{
            "location": "coverage", "source_quote": quote, "case_id": "teaching.company",
            "claim_ids": ["n1"], "expression": "14/4", "claimed_result": 3.5,
        }])
    failures = grounded_failures(review, {"lesson_content": source}, package) + review.failures()
    assert (not failures) == passes


@pytest.mark.asyncio
@pytest.mark.parametrize("repair_changes_key", [True, False])
@pytest.mark.parametrize("public_changes", [True, False])
async def test_private_package_defect_repairs_contract_before_rewriting(repair_changes_key, public_changes):
    writers = 0
    repairs = 0
    initial_package = structured_package_fixture(package_payload())
    initial_package["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] += " Contradictory private key."
    corrected = copy.deepcopy(initial_package)
    corrected["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] = "Use the supplied evidence to justify the choice, test the objection, and explain why the revised claim follows."
    if public_changes:
        corrected["workbook"]["activities"][0]["title"] += " revised"

    class Client:
        model = "test-model"

        @section_client
        async def generate_json(self, *, output_model, user_prompt, **kwargs):
            nonlocal writers, repairs
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=_outline_payload(), error=None)
            if output_model is PrivatePackageRepair:
                repairs += 1
                assert "Private key contradicts the supplied evidence" in user_prompt
                if public_changes and repair_changes_key:
                    return SimpleNamespace(data={"public_defects": ["The activity title must be corrected"]}, error=None)
                value = corrected if repair_changes_key else initial_package
                return SimpleNamespace(data={"solution_patches": [{
                    "activity_id": "guided", "worked_solution": value["workbook"]["activities"][0]["worked_solution"],
                }]}, error=None)
            if output_model is LessonPackage:
                assert '"previous_package"' not in user_prompt
                return SimpleNamespace(data=copy.deepcopy(initial_package), error=None)
            if issubclass(output_model, LessonReview):
                request = json.loads(user_prompt)
                bad = "Contradictory private key" in user_prompt
                return SimpleNamespace(data={
                    "acceptable": not bad, "issues": [],
                    "package_issues": ["Private key contradicts the supplied evidence"] if bad else [],
                    "practice_minutes": 60, "contains_calculations": False,
                    "calculations": [], "literal_fact_ids": list(request["numeric_spans"]),
                }, error=None)
            writers += 1
            assert "Contradictory private key" not in user_prompt
            return SimpleNamespace(data=_lesson_sections_payload(), error=None)

    packages, validations = {}, {}
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner", task_title="Build a validated experiment",
        mission_hours=5, user_goal="learn product experimentation",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="technology", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test", client_factory=lambda **kwargs: Client(),
        prepared_packages=packages, validation_records=validations,
    )
    # An unchanged patch fails. A public defect without an independently
    # validated activity target cannot trigger a package rewrite.
    accepted = repair_changes_key and not public_changes
    assert repairs == 3
    assert writers == 12
    assert bool(error) != accepted
    assert len(validations) == (3 if accepted else 0)
    assert len(packages) == (3 if accepted else 0)
    assert all("Contradictory private key" not in str(p.model_dump()) for p in packages.values())
    assert sum(stage.endswith("package_repair") for stage, *_ in calls) == 3


@pytest.mark.asyncio
async def test_unavailable_review_never_rewrites_or_publishes_a_draft(monkeypatch):
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse

    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    writers = 0
    reviews = 0

    class Client:
        model = "test-model"

        @section_client
        async def generate_json(self, *, output_model, **kwargs):
            nonlocal writers, reviews
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=_outline_payload(), error=None)
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            if issubclass(output_model, LessonReview):
                reviews += 1
                return LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")
            writers += 1
            return SimpleNamespace(data=_lesson_sections_payload(), error=None)

    packages, validations = {}, {}
    payload, _, error = await _generate_plan_item_details_parallel(
        system_prompt="planner", task_title="Build a validated experiment",
        mission_hours=5, user_goal="learn product experimentation",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="technology", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test", client_factory=lambda **kwargs: Client(),
        prepared_packages=packages, validation_records=validations,
    )
    assert writers == 12
    assert reviews == 6
    assert "Content review unavailable" in error
    assert not packages and not validations
    assert all(not step.get("lesson_content") for step in payload["steps"])


@pytest.mark.asyncio
@pytest.mark.parametrize("error,expected_calls", [
    ("zai request failed (JSONDecodeError; finish=stop)", 2),
    ("OpenLux request failed (JSONDecodeError; finish=stop)", 2),
    ("zai request failed (RateLimitError; finish=missing)", 2),
])
async def test_package_json_repair_is_bounded_and_still_validates(monkeypatch, error, expected_calls):
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={}, error=error), LLMResponse(data={"invalid": "package"}),
    ]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is None and response.error
    assert client.generate_json.await_count == expected_calls


@pytest.mark.asyncio
async def test_valid_package_can_recover_from_malformed_json(monkeypatch):
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={}, error="zai request failed (JSONDecodeError; finish=stop)"),
        LLMResponse(data=structured_package_fixture(package_payload())),
    ]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is not None and not response.error
    first, second = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == second.kwargs["user_prompt"]
    assert "previous response was invalid JSON" in second.kwargs["system_prompt"]


@pytest.mark.asyncio
@pytest.mark.parametrize("recovery", ["valid", "invalid", "truncated"])
async def test_truncated_package_uses_one_compact_retry_without_relaxing_gates(monkeypatch, recovery):
    from unittest.mock import AsyncMock, Mock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    truncated = LLMResponse(data={}, error="zai request failed (ValueError; finish=length)",
                            finish_reason="length", raw_response='{"workbook":')
    second = (LLMResponse(data=structured_package_fixture(package_payload())) if recovery == "valid" else
              LLMResponse(data={"invalid": True}) if recovery == "invalid" else truncated)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[truncated, second]))
    factory = Mock(return_value=client)
    package, response, _ = await generate_package({}, {}, client_factory=factory)
    assert bool(package) == (recovery == "valid")
    assert bool(response.error) == (recovery != "valid")
    assert client.generate_json.await_count == 2
    assert factory.call_count == 1
    assert factory.call_args.kwargs["max_tokens"] == 6500
    assert factory.call_args.kwargs["timeout"] == 120
    initial, retry = client.generate_json.await_args_list
    assert retry.kwargs["user_prompt"] == initial.kwargs["user_prompt"]
    assert "NEW complete JSON object within 4000 output tokens" in retry.kwargs["system_prompt"]
    assert truncated.raw_response not in retry.kwargs["user_prompt"]


@pytest.mark.asyncio
async def test_contract_repair_receives_rejected_package_and_specific_defect(monkeypatch):
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    invalid = structured_package_fixture(package_payload())
    invalid["workbook"]["activities"][0]["fields"] = [{
        "id": "passes", "label": "Total checklist items passed", "kind": "number",
    }]
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=invalid), LLMResponse(data=structured_package_fixture(package_payload())),
    ]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is not None and not response.error
    repair_prompt = client.generate_json.await_args_list[1].kwargs["user_prompt"]
    assert json.dumps(invalid) in repair_prompt
    assert "Numeric field needs a computable expression" in repair_prompt
    assert "Use choice/text" in repair_prompt


@pytest.mark.parametrize("span,passes", [
    ("Gross margin is 34.0%; net margin is 9.5%.", True),
    ("The thresholds are gross margin at least 30.0% and net margin at least 8.0%.", True),
    ("Gross margin: 34.0 versus at least 30.0.", True),
    ("Gross margin is 39.0%.", False),
    ("Gross margin = 30.0 + 4.0 = 34.0%.", False),
    ("Record the total and your verdict in 80-140 words.", True),
    # Thresholds must be supplied in the package, not invented in prose.
    ("Rule: 5 = buy, 3 = watch, 2 = pass.", False),
    ("Total passes = 5.", False),
])
def test_supplied_ratios_thresholds_and_instructions_are_distinct_from_results(span, passes):
    package = {"teaching_cases": [{"id": "company", "data": [
        {"label": "Gross margin (percent)", "value": 34},
        {"label": "Net margin (percent)", "value": 9.5},
        {"label": "Checklist threshold: gross margin at least", "value": 30},
        {"label": "Checklist threshold: net margin at least", "value": 8},
    ]}]}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], literal_fact_ids=["n1"])
    assert (not grounded_failures(review, {"lesson_content": span}, package)) == passes


def test_checklist_total_is_verified_from_comparisons_including_equality():
    from app.services.practice.contracts import calculate
    expression = "(28>=30)+(8>=8)+(10.5>=12)+(0.6<=0.6)+(29>=30)"
    assert calculate(expression, {}, allow_comparisons=True) == 2
    with pytest.raises(ValueError):
        calculate(expression, {})
    for unsafe in ["__import__('os')", "[1][0]", "1 < 2 < 3", "1 in [1]"]:
        with pytest.raises(ValueError):
            calculate(unsafe, {}, allow_comparisons=True)
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30, contains_calculations=True,
        calculations=[{"location": "total", "source_quote": "Total passes = 2.",
            "case_id": "teaching.company", "claim_ids": ["n1"],
            "expression": expression, "claimed_result": 2}])
    package = {"teaching_cases": [{"id": "company", "data": [{"value": n} for n in [28,30,8,10.5,12,0.6,29]]}]}
    assert not grounded_failures(review, {"lesson_content": "Total passes = 2."}, package)
    assert not review.failures()
    review.calculations[0].claimed_result = 3
    assert review.failures()


def test_threshold_acronym_is_bound_to_expanded_label_in_same_case():
    package = {"teaching_cases": [{"id": "company", "data": [
        {"label": "Return on equity (percent)", "value": 14},
        {"label": "Checklist threshold: ROE at least", "value": 12},
    ]}]}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
        contains_calculations=False, calculations=[], literal_fact_ids=["n1"])
    assert not grounded_failures(review, {"lesson_content": "Margin rule: return on equity of 14 clears the minimum of 12."}, package)


@pytest.mark.parametrize("source,value,expected", [
    ("zero headroom", 0, "0"), ("four points", 4, "4"),
    ("one and a half points", 1.5, "1.5"), ("two passes", 2, "2"),
    ("minus four", 4, None), ("minus four", -4, "-4"),
    ("fourth choice", 4, None), ("twenty-one", 1, None),
    ("one hundred", 1, None), ("three points", 4, None),
])
def test_worded_results_preserve_actual_value_and_sign(source,value,expected):
    from app.services.planning.lesson_review import _source_literal
    assert _source_literal(source,value) == expected


@pytest.mark.parametrize("word,expression,result,passes", [
    ("passes", "34>=30", 1, True), ("fails", "34<30", 0, True),
    ("passes", "34<30", 1, False), ("passes", "34>=30", 0, False),
    ("passes", "34-30", 4, False),
])
def test_quoted_threshold_verdict_requires_matching_value_and_comparison(word,expression,result,passes):
    source = f"34 compared with 30 {word}."
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30, contains_calculations=True,
        calculations=[{"location":"mark", "source_quote":source, "claim_ids":["n1"],
            "case_id":"teaching.company", "expression":expression,
            "claimed_result":result, "claimed_literal":word}])
    package={"teaching_cases":[{"id":"company","data":[{"value":34},{"value":30}]}]}
    failures=grounded_failures(review,{"lesson_content":source},package)+review.failures()
    assert (not failures) == passes


def test_structural_field_indices_do_not_create_fake_numeric_claims():
    from app.services.planning.lesson_review import numeric_spans
    source = "Field 1: Explain why the sample is unsupported.\nField 2: Identify the unrelated criterion.\nField 3: Total passes = 2."
    assert numeric_spans({"lesson_content": source}) == {"n1": "Field 3: Total passes = 2."}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
        contains_calculations=False, calculations=[], literal_fact_ids=["n1"])
    assert grounded_failures(review,{"lesson_content":source},{})


def test_compact_units_remain_numeric_claims_after_structural_prefix():
    from app.services.planning.lesson_review import numeric_spans, _source_literal
    source = "Item 5: $41m exceeds $30m.\nField 1: Explain the objection."
    assert numeric_spans({"lesson_content": source}) == {"n1": "Item 5: $41m exceeds $30m."}
    assert _source_literal("Cash is $41m.",41) == "41"
    assert _source_literal("case41m",41) is None
    assert _source_literal("41invalid",41) is None


@pytest.mark.parametrize("ids,second,case_id,quote,passes", [
    (["n1","n2"], "3.5", "teaching.company", None, True),
    (["n1","n2"], "3.6", "teaching.company", None, False),
    (["n1","fabricated"], "3.5", "teaching.company", None, False),
    (["n1"], "3.5", "teaching.company", None, False),
    (["n1","n2"], "3.5", "teaching.unknown", None, False),
    (["n1","n2"], "3.5", "teaching.company", "Invented 3.5", False),
])
def test_compact_grouped_review_binds_every_claim_to_server_source(ids,second,case_id,quote,passes):
    source = f"Coverage is 3.50.\nRepeated coverage: {second}."
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30, contains_calculations=True,
        calculations=[{"location":"coverage", "source_quote":quote, "claim_ids":ids,
            "case_id":case_id, "expression":"14/4", "claimed_result":3.5}])
    package={"teaching_cases":[{"id":"company","data":[{"value":14},{"value":4}]}]}
    failures=grounded_failures(review,{"lesson_content":source},package)+review.failures()
    assert (not failures) == passes
