from types import SimpleNamespace

from app.services.llm.schemas import PlanItemDetailsOutput
from app.tasks.plans import (
    _plan_detail_recovery_prompt,
    _validate_plan_detail_response,
)


def _valid_payload() -> dict:
    headings = [
        "## Why This Matters",
        "## Core Framework",
        "## Worked Example",
        "## Failure Modes",
        "## Guided Practice",
        "## Check Your Understanding",
        "## References",
    ]
    heading_text = "\n\n".join(f"{heading}\n" for heading in headings)
    lesson = heading_text + ("deliberate practice evidence mechanism example " * 240)
    substep = (
        "Set a twenty minute timer, apply the supplied framework to one real "
        "artifact, record the output, and verify it against the stated success criterion."
    )
    return {
        "steps": [
            {
                "id": f"step_{index}",
                "title": f"Learn technique {index}",
                "description": "A focused skill-building lesson.",
                "estimate_minutes": 45,
                "reading_minutes": 8,
                "practice_minutes": 37,
                "lesson_content": lesson,
                "resources": ["Resource 1"],
                "substeps": [substep, substep],
            }
            for index in range(1, 4)
        ],
        "materials": [
            {
                "title": f"Resource {index}",
                "type": (
                    "book" if index == 1 else "video" if index == 2 else "course"
                ),
                "author_or_creator": "Known Creator",
                "search_query": f"Resource {index} Known Creator",
                "duration_minutes": 15,
                "reason": "Directly supports the mission.",
                "content_markdown": None,
                "ideas": [],
            }
            for index in range(1, 4)
        ],
        "definition_of_done": "Three lessons and their outputs are complete.",
        "mental_model": "Deliberate practice",
    }


def test_plan_detail_schema_requires_all_three_complete_lessons() -> None:
    payload = _valid_payload()
    payload["steps"][0].pop("lesson_content")
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_response(response)

    assert response.error is not None
    assert "lesson_content" in response.error


def test_plan_detail_schema_accepts_prompt_contract() -> None:
    result = PlanItemDetailsOutput.model_validate(_valid_payload())

    assert len(result.steps) == 3
    assert len(result.materials) == 3


def test_plan_detail_schema_rejects_non_material_resource_reference() -> None:
    payload = _valid_payload()
    payload["steps"][0]["resources"] = ["Invented Resource"]
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_response(response)

    assert "top-level material titles" in (response.error or "")


def test_semantic_validation_failure_gets_quality_specific_retry() -> None:
    retry, stage = _plan_detail_recovery_prompt(
        "original prompt",
        "Plan detail schema validation failed: lesson has 20 words",
    )

    assert stage == "quality_recovery"
    assert "1,200-1,800" in retry
    assert "lesson has 20 words" in retry


def test_json_parse_failure_gets_json_specific_retry() -> None:
    retry, stage = _plan_detail_recovery_prompt(
        "original prompt",
        "Invalid JSON: missing comma",
    )

    assert stage == "json_recovery"
    assert "strictly valid JSON" in retry
