"""The v2 comparison contract rejects false precision and unlike evidence."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.comparison.scoring import (
    COMPARISON_SCORE_METHOD,
    COMPARISON_SCORE_VERSION,
    FIXED_DIMENSIONS,
    comparison_scores_are_current,
    generate_comparison_scores,
    normalize_comparison_scores,
)

FIXED_IDS = ["capital", "knowledge", "habits", "network", "clarity"]


def _comparable_dimension(dimension_id: str, *, you_level=2, idol_level=4) -> dict:
    value = {
        "id": dimension_id,
        "status": "comparable",
        "comparison_basis": "the same demonstrated construct",
        "you_level": you_level,
        "idol_level": idol_level,
        "you_evidence": "self_reported",
        "idol_evidence": "verified",
        "you_note": "A concrete user result is reported.",
        "idol_note": "A concrete mentor result is verified.",
    }
    if dimension_id == "capital":
        value.update(
            you_metric_kind="personal_invested_assets",
            idol_metric_kind="personal_invested_assets",
            you_note="A personal investment portfolio is self-reported.",
            idol_note="A personal investment portfolio is documented.",
        )
    return value


def test_fixed_dimensions_are_the_five_ids() -> None:
    assert [dimension["id"] for dimension in FIXED_DIMENSIONS] == FIXED_IDS


def test_missing_model_dimensions_never_fall_back_to_invented_scores() -> None:
    output = normalize_comparison_scores(None)

    assert output["version"] == COMPARISON_SCORE_VERSION
    assert output["methodology"] == COMPARISON_SCORE_METHOD
    assert [dimension["id"] for dimension in output["dimensions"]] == FIXED_IDS
    assert all(dimension["you"] is None for dimension in output["dimensions"])
    assert output["overall"]["status"] == "insufficient_evidence"
    assert output["milestones"] == []


def test_personal_savings_and_business_ipo_are_forced_to_different_basis() -> None:
    raw = {
        "dimensions": [
            {
                "id": "capital",
                # Deliberately reproduce the old model's incorrect request.
                "status": "comparable",
                "comparison_basis": "capital scale",
                "you_level": 2,
                "idol_level": 4,
                "you_evidence": "self_reported",
                "idol_evidence": "verified",
                "you_metric_kind": "other",
                "idol_metric_kind": "other",
                "you_note": "Has $50k saved but no evidence it is compounding.",
                "idol_note": "Led Apple IPO raising over $100M by age 25.",
            }
        ]
    }

    output = normalize_comparison_scores(
        raw,
        achievement_baseline_status="self_reported",
    )
    capital = output["dimensions"][0]

    assert capital["you_metric_kind"] == "personal_cash_savings"
    assert capital["idol_metric_kind"] == "business_capital_raised"
    assert capital["status"] == "different_basis"
    assert capital["you"] is None
    assert capital["idol"] is None
    assert output["overall"]["status"] == "insufficient_evidence"


def test_evidence_levels_become_coarse_points_and_never_a_percentage() -> None:
    raw = {
        "dimensions": [_comparable_dimension(dimension_id) for dimension_id in FIXED_IDS],
        "milestones": [{"text": "Shipped a defining product", "hit_by_age": 25}],
    }

    output = normalize_comparison_scores(
        raw,
        achievement_baseline_status="self_reported",
    )

    assert [dimension["you"] for dimension in output["dimensions"]] == [50] * 5
    assert [dimension["idol"] for dimension in output["dimensions"]] == [100] * 5
    assert output["overall"] == {
        "status": "estimated",
        "you": 50,
        "idol": 100,
        "gap": 50,
        "comparable_dimensions": 5,
        "total_dimensions": 5,
        "reason": (
            "Ordinal readiness estimate from self-reported user evidence; "
            "not a percentage of the idol's achievements."
        ),
    }
    assert output["milestones"][0]["id"] == "m1"


def test_no_achievements_disables_overall_even_with_dimension_signals() -> None:
    output = normalize_comparison_scores(
        {"dimensions": [_comparable_dimension(dimension_id) for dimension_id in FIXED_IDS]},
        achievement_baseline_status="none_yet",
    )

    assert output["overall"]["status"] == "insufficient_evidence"
    assert output["overall"]["you"] is None
    assert "No achievements were reported" in output["overall"]["reason"]


def test_milestones_are_capped_at_five() -> None:
    output = normalize_comparison_scores(
        {"milestones": [{"text": f"m{index}"} for index in range(9)]}
    )
    assert len(output["milestones"]) == 5


def test_only_the_v2_server_contract_is_current() -> None:
    assert not comparison_scores_are_current({"dimensions": []})
    assert comparison_scores_are_current(
        {
            "version": COMPARISON_SCORE_VERSION,
            "methodology": COMPARISON_SCORE_METHOD,
            "overall": {},
            "dimensions": [],
        }
    )


@pytest.mark.asyncio
async def test_generation_threads_authoritative_achievement_status() -> None:
    client = SimpleNamespace(
        generate_json=AsyncMock(
            return_value=SimpleNamespace(
                error=None,
                data={
                    "dimensions": [
                        _comparable_dimension(dimension_id)
                        for dimension_id in FIXED_IDS
                    ],
                    "milestones": [],
                },
            )
        )
    )

    output = await generate_comparison_scores(
        client,
        idol_name="Steve Jobs",
        user_age=28,
        user_profile_json="{}",
        interview_transcript_json="[]",
        idol_facts_json="{}",
        comparison_summary="",
        achievement_baseline_status="none_yet",
    )

    assert output is not None
    assert output["achievement_baseline_status"] == "none_yet"
    assert output["overall"]["status"] == "insufficient_evidence"
    prompt = client.generate_json.await_args.kwargs["user_prompt"]
    assert "AUTHORITATIVE ACHIEVEMENT BASELINE STATUS: none_yet" in prompt
