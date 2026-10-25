"""Private typed solutions remain inside actual curriculum originality gates."""

import pytest

from app.services.curriculum.gates import (
    _draft_prose_segments_with_locations,
    draft_text,
    validate_originality,
    validate_source_originality,
)
from app.services.curriculum.schemas import CanonicalModuleDraft, ResearchManifest, SessionWorkbook
from app.services.practice.contracts import Workbook
from tests.test_curriculum_pipeline import _draft, _manifest


COPIED = (
    "The archived observer recorded 125000 units of revenue and 90000 units of cash while "
    "carefully distinguishing the reporting period from collection dates. Those records "
    "preserved each supporting document, described the remaining uncertainty, and connected "
    "the final conclusion to the original stated assumptions without changing their meaning."
)
ORIGINAL = (
    "Develop a defensible explanation using the supplied evidence, identify its limits, "
    "then revise the claim in response to a plausible objection from the new scenario."
)


def _with_private_solution(*, structured: bool, explanation: str) -> CanonicalModuleDraft:
    draft = _draft()
    activities = []
    for index in range(2):
        text = explanation if index == 0 else ORIGINAL
        solution = {"version": 1, "steps": [{"field_id": "reason", "explanation": text}]} if structured else text
        activities.append({
            "id": f"scenario_{index}", "title": "Develop and test a supported claim",
            "kind": "practice" if index == 0 else "transfer",
            "instructions": "Use the supplied scenario to explain the reasoning, acknowledge uncertainty and revise the claim.",
            "data": [], "fields": [{"id": "reason", "label": "Explain the reasoning",
                "kind": "text", "criteria": ["Connects the conclusion to the supplied evidence."]}],
            "hint": "Make the relationship between your evidence and conclusion explicit.",
            "worked_solution": solution, "minutes_min": 5, "minutes_max": 10,
        })
    session = SessionWorkbook(block_ids=[block.block_id for block in draft.blocks],
        workbook=Workbook.model_validate({"title": "Apply and transfer", "activities": activities}))
    return CanonicalModuleDraft.model_validate({**draft.model_dump(mode="json"),
        "session_workbooks": [session.model_dump(mode="json")]})


@pytest.mark.parametrize("structured", [False, True])
def test_catalog_originality_rejects_copied_private_solution_in_real_draft(structured):
    draft = _with_private_solution(structured=structured, explanation=COPIED)
    result = validate_originality(draft, [COPIED])
    assert not result.passed
    assert {issue.code for issue in result.issues} == {"excessive_catalog_overlap"}
    assert result.metrics["maximum_shingle_similarity"] == 1.0


@pytest.mark.parametrize("structured", [False, True])
def test_source_originality_rejects_and_localizes_copied_private_solution(structured):
    draft = _with_private_solution(structured=structured, explanation=COPIED)
    manifest = _manifest().model_dump(mode="json")
    manifest["sources"][0]["sanitized_support_text"] = COPIED
    result = validate_source_originality(draft, ResearchManifest.model_validate(manifest))
    assert not result.passed
    assert {issue.code for issue in result.issues} == {"source_copying_detected"}
    path = "session_workbooks[0].activities[0].worked_solution"
    if structured:
        path += ".steps[0].explanation"
    assert any(path in issue.repair_instruction for issue in result.issues)


@pytest.mark.parametrize("structured", [False, True])
def test_authored_solution_text_and_numbers_survive_typed_and_persisted_extraction(structured):
    draft = _with_private_solution(structured=structured, explanation=COPIED)
    expected = "session_workbooks[0].activities[0].worked_solution"
    if structured:
        expected += ".steps[0].explanation"
    for source in (draft, draft.model_dump(mode="json")):
        segments = _draft_prose_segments_with_locations(source)
        assert (None, expected, COPIED) in segments
        assert "125000" in draft_text(source) and "90000" in draft_text(source)
        assert draft_text(source).count(COPIED) == 1


@pytest.mark.parametrize("structured", [False, True])
def test_unrelated_private_solution_is_not_flagged_by_source_fixture(structured):
    draft = _with_private_solution(structured=structured, explanation=ORIGINAL)
    manifest = _manifest().model_dump(mode="json")
    manifest["sources"][0]["sanitized_support_text"] = COPIED
    assert validate_originality(draft, [COPIED]).passed
    assert validate_source_originality(draft, ResearchManifest.model_validate(manifest)).passed
