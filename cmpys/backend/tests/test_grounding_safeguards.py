"""Regression cases from the writing intake quality audit; no provider calls."""
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.api.v1 import sessions
from app.services.comparison.scoring import normalize_comparison_scores


def _measurement(kind, quote, unit, scope, rubric=""):
    return dict(kind=kind, evidence_quote=quote, unit=unit, scope=scope, rubric=rubric)


def _score(dimension, user_quote, mentor_quote, user_measurement=None, mentor_measurement=None):
    answer_key = {
        "knowledge": "foundation_check", "judgment": "work_sample",
        "practice": "practice_volume", "network": "network_support",
    }[dimension]
    raw = {"dimensions": [{
        "id": dimension, "status": "comparable", "comparison_basis": "The same construct",
        "you_level": 2, "idol_level": 3, "you_evidence": "self_reported",
        "idol_evidence": "documented", "you_note": user_quote, "idol_note": mentor_quote,
        "you_measurement": user_measurement or {}, "idol_measurement": mentor_measurement or {},
    }]}
    result = normalize_comparison_scores(raw, learner_baseline={
        "interview_key_set": "v2", answer_key: {"answer": user_quote},
    }, idol_facts={"facts": [{"description": mentor_quote}]})
    assert result["evidence_policy_version"] == 3
    return next(item for item in result["dimensions"] if item["id"] == dimension)


@pytest.mark.parametrize("dimension,user", [
    ("knowledge", "I revised the claim to specify a six-week trial."),
    ("judgment", "I explained which evidence supports the claim."),
    ("practice", "I completed three essays so far."),
    ("network", "I can ask two friends for feedback today."),
])
def test_publication_milestone_cannot_create_four_numeric_comparisons(dimension, user):
    mentor = "Dickens's literary success began with the 1836 serial publication of The Pickwick Papers."
    result = _score(dimension, user, mentor)
    assert result["status"] == "insufficient_idol_evidence"
    assert result["you"] is None and result["idol"] is None
    assert result["idol_evidence"] == "none"
    assert "does not contain a usable measurement" in result["idol_note"]


@pytest.mark.parametrize("dimension,kind,unit,scope,rubric,user,mentor", [
    ("knowledge", "knowledge_assessment", "points", "claim accuracy", "Claims A",
     "On rubric Claims A I scored 3 points for claim accuracy.",
     "On rubric Claims A the mentor scored 4 points for claim accuracy."),
    ("judgment", "written_judgment_assessment", "points", "written reasoning", "Reasoning B",
     "On rubric Reasoning B I scored 2 points for written reasoning.",
     "On rubric Reasoning B the mentor scored 3 points for written reasoning."),
    ("practice", "completed_work_count", "essays", "last month", "",
     "I completed 3 essays last month.", "The mentor completed 5 essays last month."),
    ("network", "feedback_contact_count", "people", "today", "",
     "I have 2 people available for feedback today.",
     "The mentor has 3 people available for feedback today."),
])
def test_actual_matched_measurements_remain_comparable(dimension, kind, unit, scope, rubric, user, mentor):
    result = _score(dimension, user, mentor,
                    _measurement(kind, user, unit, scope, rubric),
                    _measurement(kind, mentor, unit, scope, rubric))
    assert result["status"] == "comparable"
    assert (result["you"], result["idol"]) == (50, 75)
    # Non-capital dimensions legitimately use unknown financial metric kinds.
    assert result["you_metric_kind"] == "unknown"


def test_measurement_must_be_grounded_in_supplied_facts_not_own_notes():
    user = "I completed 3 essays last month."
    fact = "The mentor published The Pickwick Papers in 1836."
    invented = "The mentor completed 5 essays last month."
    result = _score("practice", user, fact,
                    _measurement("completed_work_count", user, "essays", "last month"),
                    _measurement("completed_work_count", invented, "essays", "last month"))
    assert result["status"] == "insufficient_idol_evidence"


def test_different_units_are_not_comparable_even_with_grounded_counts():
    user = "I completed 3 essays last month."
    mentor = "The mentor completed 2 novels last month."
    result = _score("practice", user, mentor,
                    _measurement("completed_work_count", user, "essays", "last month"),
                    _measurement("completed_work_count", mentor, "novels", "last month"))
    assert result["status"] == "different_basis"
    assert result["you"] is None and result["idol"] is None


def test_date_cannot_be_used_as_completed_work_quantity():
    user = "I completed 3 essays last month."
    mentor = "In 1836 the mentor published essays last month."
    result = _score("practice", user, mentor,
                    _measurement("completed_work_count", user, "essays", "last month"),
                    _measurement("completed_work_count", mentor, "essays", "last month"))
    assert result["status"] == "insufficient_idol_evidence"


def _event(description, *, importance=0.5, age=20):
    return SimpleNamespace(canonical_title=description, canonical_description=description,
                           category="other", age_at_event=age, confidence=0.9,
                           importance_score=importance)


def _idol(domain, roles, events, *, tags=(), name="Mentor"):
    return SimpleNamespace(
        name=name, domain=domain, profile=SimpleNamespace(domains=[domain], primary_roles=roles,
        notable_themes=[], birth_date=None, death_date=None, era_tags=[]),
        tag_links=[SimpleNamespace(tag=SimpleNamespace(name=tag)) for tag in tags],
        timeline_events=events, quality_score=0.9, birth_date=None, external_ids=[], image_url=None,
    )


async def _suggest(monkeypatch, idol):
    monkeypatch.setattr(sessions, "is_verified_idol_photo", lambda _: False)
    result = SimpleNamespace()
    result.scalars = lambda: result
    result.unique = lambda: result
    result.all = lambda: [idol]
    return await sessions._catalog_idol_suggestions(
        SimpleNamespace(execute=AsyncMock(return_value=result)), interests=["Writing"],
        user_goal="Write clearer essays", user_age=24, limit=1)


@pytest.mark.asyncio
async def test_writing_tag_cannot_promote_sports_mentor(monkeypatch):
    idol = _idol("Chess", ["Chess player"], [_event("Won the world chess championship")], tags=["writing"])
    assert await _suggest(monkeypatch, idol) == []


@pytest.mark.asyncio
async def test_relevant_domain_still_needs_relevant_milestone(monkeypatch):
    idol = _idol("Literature", ["Author"], [_event("Won the world chess championship")])
    assert await _suggest(monkeypatch, idol) == []


@pytest.mark.asyncio
async def test_relevant_milestone_wins_over_unrelated_importance(monkeypatch):
    idol = _idol("Literature", ["Author"], [
        _event("Won the world chess championship", importance=1),
        _event("Published a collection of essays", importance=0.4),
        _event("Published an essay collection later", importance=1, age=30),
    ])
    result = await _suggest(monkeypatch, idol)
    assert len(result) == 1
    assert "collection of essays" in result[0].relevance_summary
    assert "chess" not in result[0].relevance_summary


def test_practice_count_prompt_confirms_existing_count_and_excludes_abandoned_work():
    params = sessions._interview_question_params(
        SimpleNamespace(user_age=24, user_financial_status=None, user_interests=["Writing"],
                        user_goal="Write essays", idol_facts_json={}), idol_name="Mentor",
        chat_history_json="[]", current_turn=7, user_message="Three finished essays",
        required_answer_key="practice_volume",
    )
    assert "earlier answer already gives this count" in params["required_answer_instruction"]
    assert "exclude abandoned drafts" in params["required_answer_instruction"]
