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


def _response(
    *,
    model: str,
    error: str | None = None,
    finish_reason: str = "STOP",
) -> SimpleNamespace:
    return SimpleNamespace(
        error=error,
        retried=False,
        model=model,
        provider="gemini",
        prompt_tokens=100,
        completion_tokens=200,
        total_tokens=300,
        duration_ms=10,
        finish_reason=finish_reason,
    )


async def _generate_week_one(*, telemetry_context: dict | None = None):
    return await generator.generate_plan_week_from_backbone(
        backbone_week=_backbone().weeks[0],
        roadmap_thesis="Build computational judgment through cumulative evidence.",
        idol_name="Ada Lovelace",
        idol_domain="computing",
        user_goal="learn computational thinking",
        hours_per_week=5,
        telemetry_context=telemetry_context,
    )


@pytest.mark.asyncio
async def test_initial_plan_generates_backbone_then_only_week_one(monkeypatch) -> None:
    requested_models: list[type] = []
    factory_kwargs: list[dict] = []
    rendered_prompts: dict[type, str] = {}
    telemetry_metadata: list[dict] = []

    class Client:
        model = "grok-test"

        async def generate_and_validate(self, *, output_model, user_prompt, **_kwargs):
            requested_models.append(output_model)
            rendered_prompts[output_model] = user_prompt
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

    async def capture_telemetry(**kwargs) -> None:
        telemetry_metadata.append(kwargs["metadata"])

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    roadmap = await generator._generate_llm_items(
        idol_name="Ada Lovelace",
        user_goal="learn computational thinking",
        hours_per_week=5,
        duration_weeks=12,
        idol_profile={"domains": ["computing"]},
        learner_baseline_json='{"weekly_capacity_hours":5,"achievement_inventory":{"answer":"Built a compiler"}}',
        interview_transcript_json="RAW INTERVIEW TRANSCRIPT",
        comparison_summary="DISTILLED COMPARISON",
        blueprint_markdown="DISTILLED BLUEPRINT",
        telemetry_context={"plan_job_id": "job-1", "queue_wait_ms": 123},
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
    assert roadmap.generation_source == "llm"
    assert "RAW INTERVIEW TRANSCRIPT" in rendered_prompts[PlanBackboneResponse]
    assert "Built a compiler" in rendered_prompts[PlanBackboneResponse]
    assert "<<<USER_INPUT" in rendered_prompts[PlanBackboneResponse]
    assert rendered_prompts[PlanBackboneResponse].count("USER_INPUT>>>") >= 1
    assert "RAW INTERVIEW TRANSCRIPT" not in rendered_prompts[PlanGenerationResponse]
    assert "DISTILLED COMPARISON" in rendered_prompts[PlanGenerationResponse]
    assert "DISTILLED BLUEPRINT" in rendered_prompts[PlanGenerationResponse]
    assert all(row["plan_job_id"] == "job-1" for row in telemetry_metadata)
    assert all(row["queue_wait_ms"] == 123 for row in telemetry_metadata)
    assert factory_kwargs == [
        {
            "timeout": generator.PLAN_BACKBONE_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_BACKBONE_MAX_TOKENS,
            "tier": "balanced",
            "thinking_level": "medium",
        },
        {
            "timeout": generator.PLAN_WEEK_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_WEEK_MAX_TOKENS,
            "tier": "balanced",
            "thinking_level": "medium",
        },
    ]


@pytest.mark.asyncio
async def test_truncated_backbone_escalates_once_to_quality_tier(monkeypatch) -> None:
    factory_kwargs: list[dict] = []
    calls: list[dict] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, **kwargs):
            calls.append({"tier": self.tier, **kwargs})
            if self.tier == "balanced":
                return None, _response(
                    model=self.model,
                    error="Invalid JSON in response",
                    finish_reason="MAX_TOKENS",
                )
            return _backbone(), _response(model=self.model)

    def get_client(**kwargs):
        factory_kwargs.append(kwargs)
        return Client(kwargs["tier"])

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    result = await generator._generate_plan_backbone(
        system_prompt="planner system",
        user_prompt="original backbone request",
        duration_weeks=12,
        hours_per_week=5,
        telemetry_context={"plan_job_id": "job-1"},
    )

    assert result == _backbone()
    assert [call["tier"] for call in calls] == ["balanced", "quality"]
    assert all(call["repair_on_failure"] is False for call in calls)
    assert factory_kwargs == [
        {
            "timeout": generator.PLAN_BACKBONE_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_BACKBONE_MAX_TOKENS,
            "tier": "balanced",
            "thinking_level": "medium",
        },
        {
            "timeout": generator.PLAN_BACKBONE_RECOVERY_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_BACKBONE_RECOVERY_MAX_TOKENS,
            "tier": "quality",
            "thinking_level": "low",
        },
    ]
    assert generator.PLAN_BACKBONE_RECOVERY_MAX_TOKENS > (
        generator.PLAN_BACKBONE_MAX_TOKENS
    )
    recovery_prompt = calls[1]["user_prompt"]
    assert "BACKBONE QUALITY RECOVERY" in recovery_prompt
    assert "include every week from 1 through 12" in recovery_prompt
    assert "keep each text field to one concise sentence" in recovery_prompt
    assert telemetry[0]["result_status"] == "schema_failed"
    assert telemetry[0]["metadata"]["recovery_reason"] == "truncated"
    assert telemetry[0]["metadata"]["recovery_tier"] == "quality"
    assert telemetry[1]["result_status"] == "schema_valid"
    assert telemetry[1]["model"] == "quality-test"
    assert telemetry[1]["response"].retried is True


@pytest.mark.asyncio
async def test_contract_invalid_backbone_is_rewritten_by_quality_tier(
    monkeypatch,
) -> None:
    invalid_backbone = _backbone().model_copy(deep=True)
    invalid_backbone.weeks[1].tasks[0].title = invalid_backbone.weeks[0].tasks[0].title
    calls: list[tuple[str, str]] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, *, user_prompt: str, **_kwargs):
            calls.append((self.tier, user_prompt))
            result = invalid_backbone if self.tier == "balanced" else _backbone()
            return result, _response(model=self.model)

    monkeypatch.setattr(
        generator,
        "get_llm_client",
        lambda **kwargs: Client(kwargs["tier"]),
    )

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    result = await generator._generate_plan_backbone(
        system_prompt="planner system",
        user_prompt="original backbone request",
        duration_weeks=12,
        hours_per_week=5,
    )

    assert result == _backbone()
    assert [tier for tier, _prompt in calls] == ["balanced", "quality"]
    assert "duplicate backbone task title" in calls[1][1]
    assert telemetry[0]["result_status"] == "contract_failed"
    assert telemetry[0]["metadata"]["recovery_reason"] == "contract_invalid"
    assert telemetry[1]["result_status"] == "schema_valid"


@pytest.mark.asyncio
async def test_invalid_quality_backbone_fails_without_a_third_generation(
    monkeypatch,
) -> None:
    factory_tiers: list[str] = []
    calls: list[str] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, **_kwargs):
            calls.append(self.tier)
            return None, _response(
                model=self.model,
                error=f"{self.tier} returned invalid JSON",
                finish_reason="MAX_TOKENS" if self.tier == "balanced" else "STOP",
            )

    def get_client(**kwargs):
        factory_tiers.append(kwargs["tier"])
        return Client(kwargs["tier"])

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    with pytest.raises(
        ValueError,
        match="Invalid plan backbone: quality returned invalid JSON",
    ):
        await generator._generate_plan_backbone(
            system_prompt="planner system",
            user_prompt="original backbone request",
            duration_weeks=12,
            hours_per_week=5,
        )

    assert factory_tiers == ["balanced", "quality"]
    assert calls == ["balanced", "quality"]
    assert [event["result_status"] for event in telemetry] == [
        "schema_failed",
        "failed",
    ]
    assert telemetry[-1]["model"] == "quality-test"


@pytest.mark.asyncio
async def test_truncated_week_escalates_once_to_quality_tier(monkeypatch) -> None:
    factory_kwargs: list[dict] = []
    calls: list[dict] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, **kwargs):
            calls.append({"tier": self.tier, **kwargs})
            if self.tier == "balanced":
                return None, _response(
                    model=self.model,
                    error="Invalid JSON in response",
                    finish_reason="MAX_TOKENS",
                )
            return _expanded_week_one(), _response(model=self.model)

    def get_client(**kwargs):
        factory_kwargs.append(kwargs)
        return Client(kwargs["tier"])

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    result = await _generate_week_one(
        telemetry_context={"plan_job_id": "job-1"},
    )

    assert result == _expanded_week_one().weeks[0]
    assert [call["tier"] for call in calls] == ["balanced", "quality"]
    assert all(call["repair_on_failure"] is False for call in calls)
    assert factory_kwargs == [
        {
            "timeout": generator.PLAN_WEEK_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_WEEK_MAX_TOKENS,
            "tier": "balanced",
            "thinking_level": "medium",
        },
        {
            "timeout": generator.PLAN_WEEK_RECOVERY_TIMEOUT_SECONDS,
            "max_tokens": generator.PLAN_WEEK_RECOVERY_MAX_TOKENS,
            "tier": "quality",
            "thinking_level": "low",
        },
    ]
    assert generator.PLAN_WEEK_RECOVERY_MAX_TOKENS > generator.PLAN_WEEK_MAX_TOKENS
    recovery_prompt = calls[1]["user_prompt"]
    assert "WEEK 1 QUALITY RECOVERY" in recovery_prompt
    assert "exactly one week" in recovery_prompt
    assert "preserve the approved task order, types, task intent, and estimated hours" in (
        recovery_prompt
    )
    assert "titles may only be clarified" in recovery_prompt
    assert telemetry[0]["result_status"] == "schema_failed"
    assert telemetry[0]["metadata"]["recovery_reason"] == "truncated"
    assert telemetry[0]["metadata"]["recovery_tier"] == "quality"
    assert telemetry[1]["result_status"] == "schema_valid"
    assert telemetry[1]["model"] == "quality-test"
    assert telemetry[1]["response"].retried is True


@pytest.mark.asyncio
async def test_contract_invalid_week_is_rewritten_by_quality_tier(monkeypatch) -> None:
    invalid_week = _expanded_week_one().model_copy(deep=True)
    invalid_week.weeks[0].binary_tasks[0].description = "Too short."
    calls: list[tuple[str, str]] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, *, user_prompt: str, **_kwargs):
            calls.append((self.tier, user_prompt))
            result = invalid_week if self.tier == "balanced" else _expanded_week_one()
            return result, _response(model=self.model)

    monkeypatch.setattr(
        generator,
        "get_llm_client",
        lambda **kwargs: Client(kwargs["tier"]),
    )

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    result = await _generate_week_one()

    assert result == _expanded_week_one().weeks[0]
    assert [tier for tier, _prompt in calls] == ["balanced", "quality"]
    assert "description has 2 words" in calls[1][1]
    assert telemetry[0]["result_status"] == "contract_failed"
    assert telemetry[0]["metadata"]["recovery_reason"] == "contract_invalid"
    assert telemetry[1]["result_status"] == "schema_valid"


@pytest.mark.asyncio
async def test_invalid_quality_week_fails_without_a_third_generation(
    monkeypatch,
) -> None:
    factory_tiers: list[str] = []
    calls: list[str] = []
    telemetry: list[dict] = []

    class Client:
        def __init__(self, tier: str) -> None:
            self.tier = tier
            self.model = f"{tier}-test"

        async def generate_and_validate(self, **_kwargs):
            calls.append(self.tier)
            return None, _response(
                model=self.model,
                error=f"{self.tier} returned invalid week JSON",
                finish_reason="MAX_TOKENS" if self.tier == "balanced" else "STOP",
            )

    def get_client(**kwargs):
        factory_tiers.append(kwargs["tier"])
        return Client(kwargs["tier"])

    async def capture_telemetry(**kwargs) -> None:
        telemetry.append(kwargs)

    monkeypatch.setattr(generator, "get_llm_client", get_client)
    monkeypatch.setattr(generator, "record_llm_response", capture_telemetry)

    with pytest.raises(
        ValueError,
        match="Invalid expanded week 1: quality returned invalid week JSON",
    ):
        await _generate_week_one()

    assert factory_tiers == ["balanced", "quality"]
    assert calls == ["balanced", "quality"]
    assert [event["result_status"] for event in telemetry] == [
        "schema_failed",
        "failed",
    ]
    assert telemetry[-1]["model"] == "quality-test"


@pytest.mark.asyncio
async def test_llm_mode_failure_is_not_published_as_deterministic_plan(
    monkeypatch,
) -> None:
    async def fail_backbone(**_kwargs):
        raise RuntimeError("both providers unavailable")

    monkeypatch.setattr(generator, "_generate_plan_backbone", fail_backbone)

    with pytest.raises(
        RuntimeError,
        match="failed across configured providers",
    ):
        await generator._generate_llm_items(
            idol_name="Ada Lovelace",
            user_goal="learn computational thinking",
            hours_per_week=5,
            duration_weeks=12,
        )
