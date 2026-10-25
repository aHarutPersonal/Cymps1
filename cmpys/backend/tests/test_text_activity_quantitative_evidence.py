"""Text answers can use declared quantitative evidence without a math quiz."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair, generate_package
from app.services.planning.activity_draft import LessonActivityDraft
from app.services.planning.lesson_review import numeric_spans
from app.services.planning.package_review import (
    PackageReview, _numeric_preflight_failures, review_package,
)
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import activity_draft_fixture


def quantitative_text_package():
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = [{"id": "respondents", "label": "Survey respondents",
                         "value": 37, "unit": "respondents"}]
    activity["instructions"] = (
        "The supplied fictional survey includes 37 respondents. "
        "Revise the argument for a skeptical audience, preserving this evidence "
        "while acknowledging that the survey does not establish causation."
    )
    activity["worked_solution"] = (
        "The supplied fictional survey includes 37 respondents. "
        "The revision preserves the sample size and explains why a limited "
        "survey supports a cautious claim rather than a universal conclusion."
    )
    return LessonPackage.model_validate(payload)


def evidence_for(package):
    spans = numeric_spans({}, package.review_context())
    assert len(spans) == 2
    return {"acceptable": True, "issues": [], "contains_calculations": False,
            "literal_facts": [{"claim_id": key, "case_id": "practice.guided",
                               "datum_ids": ["respondents"]} for key in spans]}


@pytest.mark.asyncio
async def test_declared_evidence_for_text_answers_passes_one_review_without_arithmetic(monkeypatch):
    package = quantitative_text_package()
    assert all(field.kind == "text" for activity in package.workbook.activities
               for field in activity.fields)
    before = package.model_dump(mode="json")
    verdict = evidence_for(package)
    client = SimpleNamespace(model="test-model", generate_json=AsyncMock(
        return_value=LLMResponse(data=verdict, finish_reason="stop")))
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    failures, response, _ = await review_package(package, {"title": "Revise an argument"}, {},
                                                 client_factory=lambda **kwargs: client)
    assert failures == [] and response.error is None
    assert client.generate_json.await_count == 1
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    assert request["evidence_cases"]["practice.guided"]["raw_datum_ids"] == ["respondents"]
    assert not response.data.get("calculations")
    assert package.model_dump(mode="json") == before


@pytest.mark.parametrize("mutation", ["missing_data", "changed_fact", "invented_calculation"])
def test_text_assessment_does_not_exempt_unbound_or_invented_quantities(mutation):
    package = quantitative_text_package()
    verdict = evidence_for(package)
    payload = package.model_dump(mode="json")
    if mutation == "missing_data":
        payload["workbook"]["activities"][0]["data"] = []
    elif mutation == "changed_fact":
        payload["workbook"]["activities"][0]["data"][0]["value"] = 38
    else:
        claim = verdict["literal_facts"][0]["claim_id"]
        verdict = copy.deepcopy(verdict)
        verdict["literal_facts"] = verdict["literal_facts"][1:]
        verdict["contains_calculations"] = True
        verdict["calculations"] = [{"claim_ids": [claim], "case_id": "practice.guided",
                                    "expression": "37", "claimed_result": 37}]
    candidate = LessonPackage.model_validate(payload)
    source_errors, proof_errors = _numeric_preflight_failures(PackageReview.model_validate(verdict), candidate)
    assert source_errors or proof_errors


@pytest.mark.asyncio
async def test_missing_public_evidence_uses_existing_public_repair_slot(monkeypatch):
    corrected = quantitative_text_package()
    payload = corrected.model_dump(mode="json")
    payload["workbook"]["activities"][0]["data"] = []
    prior = LessonPackage.model_validate(payload)
    before = prior.model_dump(mode="json")
    corrected_payload = corrected.model_dump(mode="json")
    replacement = corrected_payload["workbook"]["activities"][0]
    replacement["worked_solution"] = {
        "version": 1, "steps": [{"field_id": "argument", "explanation": replacement["worked_solution"]}],
    }
    corrected = LessonPackage.model_validate(corrected_payload)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={"public_defects": [
            "The guided survey's stated sample size is missing from its public data."
        ]}, finish_reason="stop"),
        LLMResponse(data=activity_draft_fixture(replacement), finish_reason="stop"),
    ]))
    requests = []

    def factory(**kwargs):
        requests.append(kwargs)
        return client

    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    package, response, _ = await generate_package(
        {"title": "Revise an argument"}, {}, client_factory=factory,
        prior_package=prior, defects=["Required survey evidence is undeclared."],
        repair_targets=["practice.guided"],
    )
    assert package == corrected and response.error is None
    assert prior.model_dump(mode="json") == before
    calls = client.generate_json.await_args_list
    assert len(calls) == 2
    models = [call.kwargs["output_model"] for call in calls]
    assert models[0] is PrivatePackageRepair and issubclass(models[1], LessonActivityDraft)
    assert [request["max_tokens"] for request in requests] == [3500, 4000]
    assert [request["timeout"] for request in requests] == [120, 90]
    repair_request = json.loads(calls[1].kwargs["user_prompt"])
    assert repair_request["previous_activity"] == before["workbook"]["activities"][0]
    assert repair_request["validated_repair_targets"] == ["practice.guided"]
    assert "previous_package" not in repair_request
    assert package.workbook.activities[1].model_dump(mode="json") == before["workbook"]["activities"][1]
    assert package.teaching_cases == prior.teaching_cases
    assert response.semantic_accepted is None
    # Package construction still does not approve it; all explicit source facts
    # must pass the unchanged evidence validator after the public repair.
    errors = _numeric_preflight_failures(PackageReview.model_validate(evidence_for(package)), package)
    assert errors == ([], [])
