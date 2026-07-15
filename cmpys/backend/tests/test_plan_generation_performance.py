from types import SimpleNamespace

import pytest

from app.services.llm.schemas import PlanBackboneResponse, PlanGenerationResponse
from app.services.planning import generator


def _words(value: str, count: int) -> str:
    return " ".join([value] * count)


def _phase(week: int) -> str:
    if week <= 3:
        return "foundation"
    if week <= 6:
        return "core_skills"
    if week <= 9:
        return "applied_practice"
    return "integration"


def _backbone() -> PlanBackboneResponse:
    return PlanBackboneResponse.model_validate(
        {
            "roadmap_thesis": "Build computational judgment through cumulative evidence.",
            "anti_goals": ["Avoid passive study without a finished artifact."],
            "weeks": [
                {
                    "week_number": week,
                    "phase": _phase(week),
                    "primary_mission": f"Complete computational proof {week}.",
                    "outcome": f"A reviewed artifact for week {week} exists.",
                    "tasks": [
                        {
                            "title": f"Build artifact {week}",
                            "type": "project",
                            "estimated_hours": 3,
                            "success_metric": f"Artifact {week} passes its rubric.",
                        },
                        {
                            "title": f"Practice technique {week}",
                            "type": "practice",
                            "estimated_hours": 2,
                            "success_metric": f"Four week-{week} drills are logged.",
                        },
                    ],
                    "predicted_friction": "The scope may expand.",
                    "friction_solution": "Use one explicit completion rubric.",
                }
                for week in range(1, 13)
            ],
        }
    )


def _expanded_week_one() -> PlanGenerationResponse:
    return PlanGenerationResponse.model_validate(
        {
            "roadmap_thesis": "Build computational judgment through cumulative evidence.",
            "anti_goals": ["Avoid passive study without a finished artifact."],
            "weeks": [
                {
                    "week_number": 1,
                    "primary_mission": _words("skill", 36),
                    "binary_tasks": [
                        {
                            "title": "Build artifact 1",
                            "description": _words("mission", 85),
                            "type": "project",
                            "estimated_hours": 3,
                            "success_metric": "Artifact 1 passes its rubric.",
                        },
                        {
                            "title": "Practice technique 1",
                            "description": _words("practice", 50),
                            "type": "practice",
                            "estimated_hours": 2,
                            "success_metric": "Four week-1 drills are logged.",
                            "daily_instructions": _words("practice", 75),
                        },
                    ],
                    "predicted_friction": "The scope may expand.",
                    "friction_solution": "Use one explicit completion rubric.",
                }
            ],
        }
    )


@pytest.mark.asyncio
async def test_initial_plan_generates_backbone_then_only_week_one(monkeypatch) -> None:
    requested_models: list[type] = []
    factory_kwargs: list[dict] = []

    class Client:
        model = "grok-test"

        async def generate_and_validate(self, *, output_model, **_kwargs):
            requested_models.append(output_model)
            value = (
                _backbone()
                if output_model is PlanBackboneResponse
                else _expanded_week_one()
            )
            return (
                value,
                SimpleNamespace(
                    error=None,
                    retried=False,
                    model="grok-test",
                    provider="yunwu",
                    prompt_tokens=100,
                    completion_tokens=200,
                    total_tokens=300,
                    duration_ms=10,
                ),
            )

    def get_client(**kwargs):
        factory_kwargs.append(kwargs)
        return Client()

    async def ignore_telemetry(**_kwargs) -> None:
        return None

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", ignore_telemetry)

    roadmap = await generator._generate_llm_items(
        idol_name="Ada Lovelace",
        user_goal="learn computational thinking",
        hours_per_week=5,
        duration_weeks=12,
        idol_profile={"domains": ["computing"]},
    )

    assert requested_models == [PlanBackboneResponse, PlanGenerationResponse]
    assert {item.week_start for item in roadmap.items} == set(range(1, 13))
    assert len(roadmap.items) == 24
    assert all(
        item.meta_json["week_content_status"] == "ready"
        for item in roadmap.items
        if item.week_start == 1
    )
    assert all(
        item.meta_json["week_content_status"] == "backbone"
        for item in roadmap.items
        if item.week_start > 1
    )
    assert len(roadmap.backbone_weeks) == 12
    assert factory_kwargs == [
        {
            "timeout": generator.PLAN_BACKBONE_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_BACKBONE_MAX_TOKENS,
            "tier": "balanced",
            "thinking_budget": 0,
        },
        {
            "timeout": generator.PLAN_WEEK_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_WEEK_MAX_TOKENS,
            "tier": "balanced",
            "thinking_budget": 0,
        },
    ]
