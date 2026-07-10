from types import SimpleNamespace

from app.tasks.plans import _build_idol_plan_context


def test_plan_context_keeps_profile_persona_milestones_and_gaps():
    context = _build_idol_plan_context(
        idol=SimpleNamespace(name="Ada Lovelace", domain="computing"),
        profile=SimpleNamespace(
            display_name="Ada Lovelace",
            short_description="Mathematician and computing pioneer",
            domains=["mathematics", "computing"],
            primary_roles=["mathematician"],
            notable_themes=["analytical engine"],
        ),
        persona=SimpleNamespace(
            voice_style="analytical",
            principles=["imagination and rigor"],
            topics_of_strength=["mathematics"],
            era_context="Victorian era",
        ),
        milestones=[
            SimpleNamespace(
                canonical_title="Published Notes",
                canonical_description="Explained the Analytical Engine",
                age_at_event=27,
                category="learning",
                importance_score=0.95,
            )
        ],
        gaps=["learning"],
    )

    assert context["idol_profile"]["domain"] == "computing"
    assert context["idol_persona"]["principles"] == ["imagination and rigor"]
    assert context["idol_milestones"][0]["title"] == "Published Notes"
    assert context["gaps"] == ["learning"]
    assert context["readiness_by_gap"] == {"learning": "beginner"}
