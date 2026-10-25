"""Public example replay must not masquerade as independent transfer."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.services.llm.prompt_loader import load_and_render
from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import (
    LessonPackage, TeachingCase, digest, validate_transfer_independence,
)
from app.services.practice.contracts import Activity
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_activity_fixture
from tests.test_staged_package_builder import Factory


def payload(*, numeric=True):
    # Generic synthetic values preserve the observed subset shape, not captured
    # private prose, answers, names or exact data from a provider response.
    data = package_payload()
    facts = [{"id": name, "label": name.replace("_", " ").title(), "value": value, "unit": "credits"}
             for name, value in [("cash", 90), ("credit", 30), ("prior", 20),
                                 ("rent", 25), ("material", 18), ("wages", 26), ("loan", 50)]]
    data["teaching_cases"] = [{"id": "public_case", "assumptions": "A fictional business supplies all amounts in credits.",
                               "data": facts, "results": [{"id": "revenue", "label": "Current revenue",
                               "expression": "cash + credit", "unit": "credits", "decimal_places": 0}]}]
    transfer = data["workbook"]["activities"][-1]
    transfer["data"] = [copy.deepcopy(fact) for fact in facts if fact["id"] in {"loan", "prior", "credit"}]
    transfer["instructions"] = "Use the supplied transactions to explain how timing changes the reported financial position."
    if numeric:
        transfer["fields"] = [{"id": "difference", "label": "Net difference", "kind": "number",
                                "expression": "loan + prior - credit", "unit": "credits"}]
    return data


def independent_transfer(data):
    transfer = copy.deepcopy(data["workbook"]["activities"][-1])
    for fact in transfer["data"]:
        if fact["id"] == "loan":
            fact["value"] = 60
        elif fact["id"] == "credit":
            fact["value"] = 37
    return transfer


@pytest.mark.parametrize("numeric", [True, False])
def test_transfer_reusing_public_subset_is_rejected_even_with_qualitative_answers(numeric):
    data = payload(numeric=numeric)
    before = copy.deepcopy(data)
    with pytest.raises(ValueError, match="copied subsets"):
        LessonPackage.model_validate(data)
    assert data == before  # No silent rewriting of task facts or answers.


@pytest.mark.parametrize("rename,reorder", [(True, False), (False, True), (True, True)])
def test_subset_identity_does_not_depend_on_ids_order_or_unit_whitespace(rename, reorder):
    data = payload()
    transfer = data["workbook"]["activities"][-1]
    if rename:
        for fact in transfer["data"]:
            fact["id"] = "new_" + fact["id"]
            fact["label"] = "Renamed " + fact["label"]
            fact["unit"] = "  credits  "
        transfer["fields"][0]["expression"] = "new_loan + new_prior - new_credit"
    if reorder:
        transfer["data"].reverse()
    with pytest.raises(ValueError, match="copied subsets"):
        LessonPackage.model_validate(data)


def test_case_sensitive_unit_symbols_are_not_collapsed_into_the_same_quantity():
    data = payload()
    for fact in data["teaching_cases"][0]["data"]:
        fact["unit"] = "mW"
    data["teaching_cases"][0]["results"][0]["unit"] = "mW"
    transfer = data["workbook"]["activities"][-1]
    for fact in transfer["data"]:
        fact["unit"] = "MW"
    transfer["fields"][0]["unit"] = "MW"
    assert LessonPackage.model_validate(data)
    for fact in transfer["data"]:
        fact["unit"] = " mW "
    transfer["fields"][0]["unit"] = "mW"
    with pytest.raises(ValueError, match="copied subsets"):
        LessonPackage.model_validate(data)


def test_whole_public_case_copy_remains_rejected():
    data = payload()
    data["workbook"]["activities"][-1]["data"] = copy.deepcopy(data["teaching_cases"][0]["data"])
    with pytest.raises(ValueError, match="Transfer inputs"):
        LessonPackage.model_validate(data)


def test_unused_novel_fact_cannot_hide_copied_numeric_operands():
    data = payload()
    data["workbook"]["activities"][-1]["data"].append(
        {"id": "unused", "label": "Unrelated new amount", "value": 123, "unit": "credits"})
    with pytest.raises(ValueError, match="unused new data"):
        LessonPackage.model_validate(data)


def test_new_relevant_inputs_allow_shared_incidental_values():
    data = payload()
    data["workbook"]["activities"][-1] = independent_transfer(data)
    package = LessonPackage.model_validate(data)
    # The prior-period amount is shared, but two operands genuinely change.
    assert next(f.value for f in package.workbook.activities[-1].data if f.id == "prior") == 20


def test_all_numeric_answer_operands_count_not_only_the_first_field():
    data = payload()
    transfer = data["workbook"]["activities"][-1]
    transfer["data"].append({"id": "new_cost", "label": "New scenario cost", "value": 37, "unit": "credits"})
    transfer["fields"].append({"id": "revised", "label": "Difference after new cost", "kind": "number",
                                "expression": "loan + prior - credit - new_cost", "unit": "credits"})
    assert len(LessonPackage.model_validate(data).workbook.activities[-1].fields) == 2


def test_guard_compares_each_public_case_not_an_unrelated_global_union():
    data = payload()
    data["teaching_cases"].append({"id": "another_case", "assumptions": "A separate fictional example has one input.",
        "data": [{"id": "cost", "label": "Cost", "value": 37, "unit": "credits"}],
        "results": [{"id": "doubled", "label": "Doubled cost", "expression": "cost * 2",
                     "unit": "credits", "decimal_places": 0}]})
    transfer = data["workbook"]["activities"][-1]
    transfer["data"] = [{"id": "loan", "label": "Loan", "value": 50, "unit": "credits"},
                        {"id": "new_cost", "label": "New scenario cost", "value": 37, "unit": "credits"}]
    transfer["fields"][0]["expression"] = "loan - new_cost"
    assert LessonPackage.model_validate(data)


def test_qualitative_new_scenario_without_raw_numbers_is_left_to_semantic_review():
    data = payload(numeric=False)
    transfer = data["workbook"]["activities"][-1]
    transfer["data"] = []
    transfer["instructions"] = "Apply the timing distinction to a new subscription business with payment before delivery; explain your reasoning."
    assert LessonPackage.model_validate(data)


def test_guided_practice_can_reuse_public_example_inputs():
    data = payload()
    guided = Activity.model_validate({**data["workbook"]["activities"][-1], "kind": "practice"})
    cases = [TeachingCase.model_validate(case) for case in data["teaching_cases"]]
    assert validate_transfer_independence(guided, cases) is None


def seed_for(data):
    return builder.LessonPackageSeed.model_validate({
        "workbook_title": data["workbook"]["title"], "teaching_cases": data["teaching_cases"],
        "activity_briefs": [{"id": activity["id"], "kind": activity["kind"], "scope": activity["instructions"]}
                            for activity in data["workbook"]["activities"]],
    }).model_dump(mode="json")


@pytest.mark.asyncio
async def test_subset_component_uses_existing_correction_before_any_private_checkpoint(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    data = payload()
    seed = seed_for(data)
    guided, bad = map(structured_activity_fixture, data["workbook"]["activities"])
    good = structured_activity_fixture(independent_transfer(data))
    factory = Factory({"seed": [seed], "guided": [guided], "transfer": [bad, good]})
    saved = []

    async def save(parts):
        saved.append(parts)

    package, response, _ = await builder.generate_initial_package({}, {}, client_factory=factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert response.effective_parameters["shared_correction_used"] is True
    assert response.effective_parameters["component_requests"] == 4
    assert record.await_count == 4
    for parts in saved:
        if "transfer" in parts["activities"]:
            assert parts["activities"]["transfer"] == Activity.model_validate(good).model_dump(mode="json")
    assert saved[-1]["activities"]["guided"] == Activity.model_validate(guided).model_dump(mode="json")


@pytest.mark.asyncio
async def test_failed_subset_correction_keeps_only_valid_components_and_stops(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    data = payload()
    guided, bad = map(structured_activity_fixture, data["workbook"]["activities"])
    factory = Factory({"seed": [seed_for(data)], "guided": [guided], "transfer": [bad, bad]})
    saved = []

    async def save(parts):
        saved.append(parts)

    package, response, _ = await builder.generate_initial_package({}, {}, client_factory=factory, on_parts=save)
    assert package is None and response.error and response.data == {}
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert record.await_count == 4
    assert all("transfer" not in parts["activities"] for parts in saved)
    assert set(saved[-1]["activities"]) == {"guided"}


@pytest.mark.asyncio
async def test_saved_subset_fails_closed_before_more_paid_work(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    data = payload()
    seed = seed_for(data)
    parts = {"version": 2, "seed": seed, "seed_hash": digest(seed),
             "activities": {"transfer": structured_activity_fixture(data["workbook"]["activities"][-1])}}
    factory = Factory({})
    package, response, _ = await builder.generate_initial_package({}, {}, client_factory=factory, existing_parts=parts)
    assert package is None and response.error
    assert not factory.requests
    record.assert_not_awaited()


def test_planning_and_activity_prompts_require_real_transfer_and_objective_choices():
    seed = " ".join(load_and_render("lesson_package_seed.txt", {}).split())
    activity = " ".join(load_and_render("lesson_activity_generate.txt", {}).split())
    assert "Recalling public answers or revising the same worked case is not independent transfer" in seed
    assert "exactly one answer objectively correct" in seed
    assert "personal preference or self-assessment must use a text response" in seed
    assert "unused extra fact does not create independence" in activity
    assert "answers are not already supplied in public explanations" in activity
    assert "Never use a fixed correct choice for a freely chosen audience, preference or self-assessment" in activity
    assert "assessing reasons and fit with the learner's declared choice" in activity
    assert "Keep activity titles concise and natural" in activity
