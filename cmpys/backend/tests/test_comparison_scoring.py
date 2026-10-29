"""The comparison contract rejects false precision and unlike evidence.

Payload version 3 uses the design's five dimensions. Stored version 2 payloads
(the old ids) are never rewritten on read.
"""

import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.models.chat import MessageRole
from app.services.comparison.scoring import (
    COMPARISON_SCORE_METHOD,
    COMPARISON_SCORE_VERSION,
    FIXED_DIMENSIONS,
    comparison_scores_are_current,
    generate_comparison_scores,
    normalize_comparison_scores,
)
from app.services.interview_inputs import (
    build_interview_plan_inputs,
    provider_interview_plan_inputs,
)

FIXED_IDS = ["knowledge", "practice", "capital", "network", "judgment"]
OLD_V2_IDS = ["capital", "knowledge", "habits", "network", "clarity"]

# Which interview answers speak for which dimension (v2 question set).
V2_BINDINGS = {
    "knowledge": (
        "achievement_inventory",
        "foundation_check",
        "application_check",
        "skill_confidence",
    ),
    "practice": ("practice_volume", "achievement_inventory"),
    "capital": ("resources_capital",),
    "network": ("network_support",),
    "judgment": ("work_sample", "self_check_method"),
}
# The 8-key question set, scored with the v2 dimension ids.
LEGACY_BINDINGS = {
    "knowledge": "current_capability",
    "practice": "achievement_inventory",
    "capital": "constraints_resources",
    "network": "learning_habits_support",
    "judgment": "target_outcome",
}


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


def _by_id(output: dict) -> dict[str, dict]:
    return {dimension["id"]: dimension for dimension in output["dimensions"]}


def _all_comparable() -> dict:
    """A model reply that (wrongly) scores every dimension as comparable."""
    return {
        "dimensions": [_comparable_dimension(dimension_id) for dimension_id in FIXED_IDS]
    }


def _messages(answers: dict[str, str], *, missing_evidence=()) -> list:
    messages = []
    for index, (key, text) in enumerate(answers.items(), start=1):
        messages.append(
            SimpleNamespace(
                id=f"q{index}",
                role=MessageRole.ASSISTANT,
                content=key,
                response_ui_json={"version": 1, "kind": "text", "answer_key": key},
                reply_to_message_id=None,
            )
        )
        messages.append(
            SimpleNamespace(
                id=f"a{index}",
                role=MessageRole.USER,
                content=text,
                response_ui_json=(
                    {"missing_evidence": True} if key in missing_evidence else None
                ),
                reply_to_message_id=f"q{index}",
            )
        )
    return messages


def _provider_baseline(answers: dict[str, str], *, missing_evidence=()) -> dict:
    """The baseline the scorer really receives: built from messages, provider-safe."""
    return provider_interview_plan_inputs(
        build_interview_plan_inputs(
            _messages(answers, missing_evidence=missing_evidence)
        )
    )


# A complete v2 interview in which every answer is genuine evidence.
V2_REAL_ANSWERS = {
    "achievement_inventory": "I shipped a small budgeting app used by five friends.",
    "work_sample": "A one-page note on a local bakery’s margins and why I would pass.",
    "foundation_check": "Revenue minus costs is profit",
    "application_check": "I would compare the margin to peers",
    "self_check_method": "I compare my notes with a published filing",
    "skill_confidence": "3 of 5",
    "practice_volume": "4 pieces of work",
    "resources_capital": "A laptop and about $200 a month",
    "network_support": "3 people",
    "weekly_hours": "4 hours / week",
    "target_outcome": "Write one owner’s memo I can defend.",
}


def _score_real(
    overrides: dict[str, str], *, missing_evidence=(), drop=()
) -> dict[str, dict]:
    """Normalize an all-comparable model reply against a real v2 interview."""
    answers = {
        key: value
        for key, value in {**V2_REAL_ANSWERS, **overrides}.items()
        if key not in drop
    }
    baseline = _provider_baseline(answers, missing_evidence=missing_evidence)
    assert baseline["interview_key_set"] == "v2"
    return _by_id(
        normalize_comparison_scores(
            _all_comparable(),
            achievement_baseline_status="self_reported",
            learner_baseline=baseline,
        )
    )


def _assert_unscored(dimension: dict) -> None:
    assert dimension["status"] == "insufficient_user_evidence"
    assert dimension["you"] is None
    assert dimension["idol"] is None
    assert dimension["you_evidence"] == "none"
    assert dimension["you_level"] == 0


def test_fixed_dimensions_are_the_five_ids() -> None:
    assert [dimension["id"] for dimension in FIXED_DIMENSIONS] == FIXED_IDS


def test_v3_dimension_ids_and_labels() -> None:
    assert FIXED_DIMENSIONS == [
        {"id": "knowledge", "label": "Knowledge base"},
        {"id": "practice", "label": "Practice volume"},
        {"id": "capital", "label": "Capital & resources"},
        {"id": "network", "label": "Network"},
        {"id": "judgment", "label": "Written judgment"},
    ]
    assert COMPARISON_SCORE_VERSION == 3

    output = normalize_comparison_scores(None)
    assert output["version"] == 3
    assert output["methodology"] == COMPARISON_SCORE_METHOD == "like_for_like_evidence"
    assert [(d["id"], d["label"]) for d in output["dimensions"]] == [
        (d["id"], d["label"]) for d in FIXED_DIMENSIONS
    ]
    # The model cannot rename a dimension out of the design's vocabulary
    # by id, and an old id it might still emit is ignored rather than mapped.
    stale = normalize_comparison_scores(
        {"dimensions": [_comparable_dimension("habits"), _comparable_dimension("clarity")]}
    )
    assert [d["id"] for d in stale["dimensions"]] == FIXED_IDS
    assert all(d["status"] == "insufficient_user_evidence" for d in stale["dimensions"])
    # Same status vocabulary as v2.
    assert {d["status"] for d in normalize_comparison_scores(_all_comparable())["dimensions"]} == {
        "comparable"
    }


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
    capital = _by_id(output)["capital"]

    assert capital["you_metric_kind"] == "personal_cash_savings"
    assert capital["idol_metric_kind"] == "business_capital_raised"
    assert capital["status"] == "different_basis"
    assert capital["you"] is None
    assert capital["idol"] is None
    assert output["overall"]["status"] == "insufficient_evidence"


def test_evidence_levels_become_coarse_points_and_never_a_percentage() -> None:
    raw = {
        "dimensions": [
            _comparable_dimension(dimension_id) for dimension_id in FIXED_IDS
        ],
        "milestones": [{"text": "Shipped a defining product", "hit_by_age": 25}],
    }

    output = normalize_comparison_scores(
        raw,
        achievement_baseline_status="self_reported",
    )

    assert [dimension["you"] for dimension in output["dimensions"]] == [50] * 5
    assert [dimension["idol"] for dimension in output["dimensions"]] == [100] * 5
    assert output["overall"]["status"] == "not_combined"
    assert output["overall"]["you"] is None
    assert output["overall"]["gap"] is None
    assert output["milestones"][0]["id"] == "m1"


def test_no_achievements_disables_overall_even_with_dimension_signals() -> None:
    output = normalize_comparison_scores(
        {
            "dimensions": [
                _comparable_dimension(dimension_id) for dimension_id in FIXED_IDS
            ]
        },
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


def _stored_payload(version: int, **overrides) -> dict:
    payload = {
        "version": version,
        "placement_version": 1,
        "methodology": COMPARISON_SCORE_METHOD,
        "overall": {},
        "dimensions": [],
    }
    payload.update(overrides)
    return payload


def test_stored_v2_and_new_v3_payloads_are_both_current() -> None:
    assert not comparison_scores_are_current({"dimensions": []})
    assert comparison_scores_are_current(_stored_payload(3))
    assert comparison_scores_are_current(_stored_payload(COMPARISON_SCORE_VERSION))
    # A stored v2 payload (old ids) stays a valid, servable payload; treating it
    # as stale would hide it from the client and re-score it into v3.
    assert comparison_scores_are_current(_stored_payload(2))
    assert not comparison_scores_are_current(_stored_payload(1))
    assert not comparison_scores_are_current(_stored_payload(4))
    assert not comparison_scores_are_current(_stored_payload(3, methodology="other"))
    assert not comparison_scores_are_current(_stored_payload(3, placement_version=2))


# ---------------------------------------------------------------------------
# Honest evidence: a missing or declined answer is unscored, never a zero
# ---------------------------------------------------------------------------


def test_every_answer_is_real_evidence_baseline_scores_all_five() -> None:
    scored = _score_real({})
    assert [scored[key]["status"] for key in FIXED_IDS] == ["comparable"] * 5
    assert all(scored[key]["you_evidence"] == "self_reported" for key in FIXED_IDS)


def test_missing_work_sample_marks_judgment_insufficient() -> None:
    baseline = _provider_baseline(
        {**V2_REAL_ANSWERS, "work_sample": "I don’t have one yet"},
        missing_evidence=("work_sample",),
    )
    assert baseline["missing_evidence_keys"] == ["work_sample"]

    output = normalize_comparison_scores(
        _all_comparable(),
        achievement_baseline_status="self_reported",
        learner_baseline=baseline,
    )
    scored = _by_id(output)

    _assert_unscored(scored["judgment"])
    assert "not evidence of low ability" in scored["judgment"]["you_note"]
    # Only the dimension the missing answer speaks for loses its score.
    assert [scored[key]["status"] for key in ("knowledge", "practice", "capital", "network")] == [
        "comparable"
    ] * 4
    assert output["overall"]["status"] == "insufficient_evidence"
    assert output["overall"]["comparable_dimensions"] == 4


def test_missing_evidence_flag_wins_over_a_contradicting_record() -> None:
    """`missing_evidence_keys` is authoritative even if the stored text looks real."""
    baseline = _provider_baseline(V2_REAL_ANSWERS)
    baseline["missing_evidence_keys"] = ["practice_volume"]

    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )

    _assert_unscored(scored["practice"])
    assert scored["knowledge"]["status"] == "comparable"


def test_prefer_not_to_say_capital_not_scored() -> None:
    scored = _score_real({"resources_capital": "Prefer not to say"})

    _assert_unscored(scored["capital"])
    # A declined money question says nothing about the other four.
    assert all(
        scored[key]["status"] == "comparable"
        for key in ("knowledge", "practice", "network", "judgment")
    )
    # Not a zero: no points, no level credited.
    assert scored["capital"]["you"] is None and scored["capital"]["idol"] is None


HONEST_NON_EVIDENCE = [
    ("resources_capital", "capital", "Prefer not to say"),
    ("resources_capital", "capital", "prefer not to say."),
    ("resources_capital", "capital", "I’d rather not say"),
    ("self_check_method", "judgment", "I don’t really check"),
    ("self_check_method", "judgment", "I don't really check"),
    ("self_check_method", "judgment", "I never check my work."),
    ("work_sample", "judgment", "I don’t have one yet"),
    ("work_sample", "judgment", "I don't have one yet"),
    ("work_sample", "judgment", "none yet"),
    ("work_sample", "judgment", "Nothing yet."),
    ("work_sample", "judgment", "None"),
    ("practice_volume", "practice", "0"),
    ("practice_volume", "practice", "0 pieces of work"),
    ("practice_volume", "practice", "Zero"),
    ("network_support", "network", "0"),
    ("network_support", "network", "0 people"),
    ("network_support", "network", "No one yet"),
]


def _other_bound_keys(dimension: str, key: str) -> tuple[str, ...]:
    return tuple(other for other in V2_BINDINGS[dimension] if other != key)


@pytest.mark.parametrize(("key", "dimension", "answer"), HONEST_NON_EVIDENCE)
def test_honest_non_evidence_answers_leave_their_dimension_unscored(
    key: str, dimension: str, answer: str
) -> None:
    """With nothing else bound to the dimension, the honest answer leaves it unscored."""
    baseline = _provider_baseline({**V2_REAL_ANSWERS, key: answer})
    # These are classed self_reported by the generic helper; only the
    # scorer's own post-model check can keep them from counting as evidence.
    assert baseline["answer_evidence_status"][key] == "self_reported"
    assert baseline["missing_evidence_keys"] == []

    # Single-key dimensions (capital, network) have nothing else bound; for the
    # others, drop the remaining bound answers so the honest one stands alone.
    scored = _score_real({key: answer}, drop=_other_bound_keys(dimension, key))

    _assert_unscored(scored[dimension])
    assert scored[dimension]["you"] is None and scored[dimension]["idol"] is None
    # Dimensions that do not depend on the dropped answers stay comparable.
    untouched = [
        other
        for other in FIXED_IDS
        if other != dimension
        and not set(V2_BINDINGS[other]) <= set(_other_bound_keys(dimension, key)) | {key}
    ]
    assert untouched and all(scored[other]["status"] == "comparable" for other in untouched)


@pytest.mark.parametrize(
    ("key", "dimension", "answer"),
    [row for row in HONEST_NON_EVIDENCE if len(V2_BINDINGS[row[1]]) > 1],
)
def test_honest_answer_does_not_unscore_a_dimension_with_other_real_evidence(
    key: str, dimension: str, answer: str
) -> None:
    """Excluded from evidence, not a veto: another bound answer keeps it scorable."""
    scored = _score_real({key: answer})

    assert scored[dimension]["status"] == "comparable"
    assert scored[dimension]["you"] == 50
    assert scored[dimension]["you_evidence"] == "self_reported"


def test_judgment_scored_from_work_sample_despite_no_self_check() -> None:
    scored = _score_real({"self_check_method": "I don’t really check"})

    assert scored["judgment"]["status"] == "comparable"
    assert scored["judgment"]["you"] == 50
    assert scored["judgment"]["you_evidence"] == "self_reported"


def test_judgment_scored_from_self_check_when_work_sample_is_typed_none() -> None:
    scored = _score_real({"work_sample": "I don’t have one yet"})

    assert scored["judgment"]["status"] == "comparable"
    assert scored["judgment"]["you_evidence"] == "self_reported"


def test_practice_scored_from_achievements_despite_zero_practice_volume() -> None:
    scored = _score_real({"practice_volume": "0"})

    assert scored["practice"]["status"] == "comparable"
    assert scored["practice"]["you"] == 50
    assert scored["practice"]["you_evidence"] == "self_reported"


def test_dimension_unscored_when_every_bound_key_is_non_evidence() -> None:
    """Both judgment answers are honest non-evidence, so nothing supports it."""
    scored = _score_real(
        {
            "work_sample": "none yet",
            "self_check_method": "I don’t really check",
        }
    )
    _assert_unscored(scored["judgment"])

    # Practice: zero counted pieces and "nothing yet" achievements.
    scored = _score_real({"practice_volume": "0", "achievement_inventory": "Nothing yet"})
    _assert_unscored(scored["practice"])
    # Knowledge still has its checks and confidence, so it is not dragged down.
    assert scored["knowledge"]["status"] == "comparable"


def test_missing_evidence_flag_still_forces_even_with_other_real_evidence() -> None:
    """Unlike an honest answer in the text, a flagged key is a veto on its dimension."""
    baseline = _provider_baseline(
        {**V2_REAL_ANSWERS, "work_sample": "I don’t have one yet"},
        missing_evidence=("work_sample",),
    )
    assert baseline["missing_evidence_keys"] == ["work_sample"]
    # The same typed answer without the flag is merely excluded...
    assert _score_real({"work_sample": "I don’t have one yet"})["judgment"][
        "status"
    ] == "comparable"

    # ...with the flag, the real self-check no longer rescues the dimension.
    flagged = _score_real(
        {"work_sample": "I don’t have one yet"}, missing_evidence=("work_sample",)
    )
    _assert_unscored(flagged["judgment"])
    assert flagged["practice"]["status"] == "comparable"


@pytest.mark.parametrize(
    ("key", "dimension", "answer"),
    [
        ("resources_capital", "capital", "Some savings and a laptop"),
        ("self_check_method", "judgment", "I compare against a published filing"),
        ("work_sample", "judgment", "None of the sample fits here, but I wrote a memo on X."),
        ("practice_volume", "practice", "1 pieces of work"),
        ("practice_volume", "practice", "10 pieces of work"),
        ("network_support", "network", "1 people"),
        ("network_support", "network", "20"),
    ],
)
def test_real_answers_that_resemble_the_honest_ones_still_count(
    key: str, dimension: str, answer: str
) -> None:
    assert _score_real({key: answer})[dimension]["status"] == "comparable"


def test_zero_count_decision_is_unscored_not_a_zero_level() -> None:
    """Documented decision: 0 pieces / 0 people is not a comparable level-0 row.

    The number controls start at 0, so an untouched stepper and a deliberate
    zero cannot be told apart; and the design leaves a dimension without
    evidence "unscored. That's not a zero." A model that tries to assign a
    comparable level 0 is overruled.
    """
    raw = {
        "dimensions": [
            {
                **_comparable_dimension("practice", you_level=0),
                "you_note": "No finished work reported.",
            },
            {
                **_comparable_dimension("network", you_level=0),
                "you_note": "No one to ask for feedback.",
            },
        ]
    }
    # Practice is also bound to achievement_inventory; leave it out so the zero
    # count is the only practice answer. (With real achievements practice is
    # scored from them, see test_practice_scored_from_achievements_*.)
    answers = {
        key: value
        for key, value in V2_REAL_ANSWERS.items()
        if key != "achievement_inventory"
    }
    baseline = _provider_baseline(
        {**answers, "practice_volume": "0", "network_support": "0"}
    )
    scored = _by_id(normalize_comparison_scores(raw, learner_baseline=baseline))

    for key in ("practice", "network"):
        _assert_unscored(scored[key])


def test_unknown_and_unanswered_inputs_are_unscored_too() -> None:
    answers = {
        key: value
        for key, value in V2_REAL_ANSWERS.items()
        if key not in {"network_support", "skill_confidence"}
    }
    answers.update(
        {
            "foundation_check": "I don't know yet",
            "application_check": "I don't know yet",
            "achievement_inventory": "I don't know",
        }
    )
    baseline = _provider_baseline(answers)

    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )

    # Network was never answered; knowledge has nothing but unknown answers.
    _assert_unscored(scored["network"])
    _assert_unscored(scored["knowledge"])
    # Practice still has its own counted answer.
    assert scored["practice"]["status"] == "comparable"


@pytest.mark.parametrize(
    "key", sorted({key for keys in V2_BINDINGS.values() for key in keys})
)
def test_each_v2_answer_key_speaks_for_exactly_its_bound_dimensions(key: str) -> None:
    baseline = _provider_baseline({key: V2_REAL_ANSWERS[key]})
    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )
    for dimension in FIXED_IDS:
        expected = (
            "comparable"
            if key in V2_BINDINGS[dimension]
            else "insufficient_user_evidence"
        )
        assert scored[dimension]["status"] == expected, (key, dimension)


def test_model_evidence_labels_are_capped_at_self_reported() -> None:
    raw = _all_comparable()
    for entry in raw["dimensions"]:
        entry["you_evidence"] = "verified"
    baseline = _provider_baseline(V2_REAL_ANSWERS)

    scored = _by_id(normalize_comparison_scores(raw, learner_baseline=baseline))

    assert {scored[key]["you_evidence"] for key in FIXED_IDS} == {"self_reported"}


def test_unmarked_baseline_with_v2_keys_binds_as_v2() -> None:
    """A hand-built baseline without the key-set marker but with v2 answers."""
    baseline = {
        "work_sample": {"answer": "A memo on a bakery"},
        "answer_evidence_status": {},
        "missing_evidence_keys": [],
    }
    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )
    assert scored["judgment"]["status"] == "comparable"
    assert scored["capital"]["status"] == "insufficient_user_evidence"


# ---------------------------------------------------------------------------
# Sessions that used the 8-key question set
# ---------------------------------------------------------------------------

V1_REAL_ANSWERS = {
    "achievement_inventory": "I shipped a small budgeting app used by five friends.",
    "current_capability": "I can reconcile cash and profit; no invested capital.",
    "foundation_check": "Revenue minus costs is profit",
    "application_check": "I would compare the margin to peers",
    "weekly_hours": "8",
    "target_outcome": "Write one owner’s memo I can defend.",
    "constraints_resources": "A laptop and about $200 a month",
    "learning_habits_support": "Weekly peer feedback has worked for me.",
}


def test_v1_session_scored_with_legacy_binding() -> None:
    baseline = _provider_baseline(V1_REAL_ANSWERS)
    assert baseline["interview_key_set"] == "v1"

    output = normalize_comparison_scores(
        _all_comparable(),
        achievement_baseline_status="self_reported",
        learner_baseline=baseline,
    )

    # Scored with the v3 ids even though the interview used the old question set.
    assert output["version"] == 3
    assert [d["id"] for d in output["dimensions"]] == FIXED_IDS
    assert {d["status"] for d in output["dimensions"]} == {"comparable"}

    # Each dimension reads exactly its legacy answer: remove one at a time.
    for dimension, legacy_key in LEGACY_BINDINGS.items():
        answers = {k: v for k, v in V1_REAL_ANSWERS.items() if k != legacy_key}
        scored = _by_id(
            normalize_comparison_scores(
                _all_comparable(),
                learner_baseline=_provider_baseline(answers),
            )
        )
        assert scored[dimension]["status"] == "insufficient_user_evidence", dimension
        # The legacy answers of the other four dimensions are untouched.
        others = [other for other in FIXED_IDS if other != dimension]
        assert all(scored[other]["status"] == "comparable" for other in others)


def test_v1_binding_ignores_v2_only_keys() -> None:
    """An 8-key baseline never borrows evidence from a v2-only answer key."""
    baseline = _provider_baseline(V1_REAL_ANSWERS)
    baseline["resources_capital"] = {"answer": "A laptop"}
    baseline["constraints_resources"] = None

    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )
    _assert_unscored(scored["capital"])


@pytest.mark.parametrize(
    "unsure",
    ["I’m not sure yet", "not sure", "I have no idea", "I haven't decided yet"],
)
def test_v1_unsure_target_is_not_written_judgment_evidence(unsure: str) -> None:
    baseline = _provider_baseline({**V1_REAL_ANSWERS, "target_outcome": unsure})
    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )
    _assert_unscored(scored["judgment"])


def test_v1_nothing_yet_learning_support_is_not_network_evidence() -> None:
    """Replaces the old `habits` check: "Nothing yet" is not an established input."""
    baseline = {
        "learning_habits_support": {"answer": "Nothing yet"},
    }
    scored = _by_id(
        normalize_comparison_scores(_all_comparable(), learner_baseline=baseline)
    )
    _assert_unscored(scored["network"])


# ---------------------------------------------------------------------------
# Stored v2 payloads are served exactly as stored
# ---------------------------------------------------------------------------


def _stored_v2_scores() -> dict:
    """What a v2 session holds today: the old ids, no evidence_policy_version."""
    return {
        "version": 2,
        "placement_version": 1,
        "methodology": COMPARISON_SCORE_METHOD,
        "achievement_baseline_status": "self_reported",
        "overall": {
            "status": "insufficient_evidence",
            "you": None,
            "idol": None,
            "gap": None,
            "comparable_dimensions": 1,
            "total_dimensions": 5,
            "reason": "Only 1 of 5 dimensions have like-for-like evidence.",
        },
        "dimensions": [
            {
                "id": "capital",
                "label": "Capital at work",
                "status": "comparable",
                "you": 50,
                "idol": 100,
            },
            {
                "id": "knowledge",
                "label": "Knowledge base",
                "status": "insufficient_user_evidence",
                "you": None,
                "idol": None,
            },
            {"id": "habits", "label": "Daily discipline", "status": "different_basis"},
            {"id": "network", "label": "Trusted network", "status": "different_basis"},
            {"id": "clarity", "label": "Strategic clarity", "status": "different_basis"},
        ],
        "milestones": [{"id": "m1", "label": "Shipped a product", "hit_by_age": 24}],
    }


def test_stored_v2_payload_untouched_on_read() -> None:
    from datetime import datetime, timezone

    from app.api.v1.sessions import _build_session_response
    from app.schemas.session import SessionResponse

    stored = _stored_v2_scores()
    snapshot = copy.deepcopy(stored)
    session = SimpleNamespace(
        id="s1",
        phase=None,
        user_age=24,
        user_financial_status="",
        user_interests=[],
        idol=None,
        interview_turn_count=0,
        comparison_output="Saved verdict",
        blueprint_output=None,
        interview_thread_id=None,
        comparison_scores_json=stored,
        comparison_scores_status="ready",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )

    body = _build_session_response(session)
    response = SessionResponse.model_validate(body).model_dump(mode="json", by_alias=True)

    # Served as stored: still version 2, still the old ids, nothing added.
    assert body["comparisonScores"] == snapshot
    assert response["comparisonScores"] == snapshot
    assert response["comparisonScoresStatus"] == "ready"
    assert [d["id"] for d in response["comparisonScores"]["dimensions"]] == OLD_V2_IDS
    assert stored == snapshot


@pytest.mark.asyncio
async def test_stored_v2_payload_is_not_renormalized_on_session_fetch(monkeypatch) -> None:
    """Review focus 1: the fetch path must not turn a stored v2 into a v3."""
    from app.api.v1 import sessions as sessions_api
    from app.tasks import comparison as comparison_tasks

    enqueued = []
    monkeypatch.setattr(
        comparison_tasks.backfill_comparison_scores,
        "apply_async",
        lambda **kwargs: enqueued.append(kwargs),
    )
    stored = _stored_v2_scores()
    snapshot = copy.deepcopy(stored)
    assert "evidence_policy_version" not in stored
    session = SimpleNamespace(
        id="s1",
        user_id="u1",
        user_goal="Learn to judge businesses",
        # A thread is present, which used to trigger a local reclassification
        # of every payload that lacked evidence_policy_version.
        interview_thread_id="thread-1",
        comparison_output="Saved verdict",
        comparison_scores_json=stored,
        comparison_scores_status="queued",
        comparison_scores_next_retry_at=None,
        comparison_scores_last_attempt_at=None,
    )
    db = AsyncMock()

    await sessions_api._maybe_enqueue_scores_backfill(session, db)

    db.execute.assert_not_awaited()  # no interview reload, no UPDATE of the row
    db.commit.assert_not_awaited()
    assert enqueued == []  # and no re-score is queued
    assert session.comparison_scores_json is stored
    assert stored == snapshot
    assert session.comparison_scores_status == "ready"


@pytest.mark.asyncio
async def test_backfill_task_never_rescores_a_stored_v2_payload(monkeypatch) -> None:
    from app.tasks import comparison as comparison_tasks

    class _Result:
        def __init__(self, value):
            self._value = value

        def scalar_one_or_none(self):
            return self._value

    class _Maker:
        def __init__(self, db):
            self._db = db

        def __call__(self):
            return self

        async def __aenter__(self):
            return self._db

        async def __aexit__(self, *args):
            return False

    stored = _stored_v2_scores()
    snapshot = copy.deepcopy(stored)
    session = SimpleNamespace(
        id="s1", comparison_scores_json=stored, comparison_output="Saved verdict"
    )
    db = AsyncMock()
    db.execute.return_value = _Result(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", _Maker(db))

    async def fail_generate(client, **kwargs):
        raise AssertionError("a stored v2 payload must not be re-scored")

    monkeypatch.setattr(
        "app.services.comparison.scoring.generate_comparison_scores", fail_generate
    )

    result = await comparison_tasks._backfill_comparison_scores_async("s1")

    assert result == {"status": "skipped", "reason": "scores_already_present"}
    assert session.comparison_scores_json is stored and stored == snapshot
    db.commit.assert_not_awaited()


def test_a_v3_payload_is_what_new_scoring_stores() -> None:
    output = normalize_comparison_scores(
        _all_comparable(), achievement_baseline_status="self_reported"
    )
    assert comparison_scores_are_current(output)
    assert output["version"] == 3
    assert output["evidence_policy_version"] == 2
    assert output["placement_version"] == 1


# ---------------------------------------------------------------------------
# The capital metric-kind guard stays bound to capital
# ---------------------------------------------------------------------------


def test_capital_metric_guard_applies_to_capital_only() -> None:
    raw = {
        "dimensions": [
            {
                **_comparable_dimension("practice"),
                # Would be non-comparable if this were the capital dimension.
                "you_metric_kind": "unknown",
                "idol_metric_kind": "other",
                "you_note": "Raised $2M at an IPO.",
            },
            {
                **_comparable_dimension("capital"),
                "you_metric_kind": "unknown",
                "idol_metric_kind": "unknown",
                "you_note": "Has a few tools.",
                "idol_note": "A resource.",
            },
        ]
    }

    scored = _by_id(normalize_comparison_scores(raw))

    assert scored["practice"]["status"] == "comparable"
    assert scored["practice"]["you_metric_kind"] == "unknown"
    assert scored["capital"]["status"] == "insufficient_user_evidence"
    assert scored["capital"]["you_metric_kind"] == "unknown"


def test_overall_reason_names_the_v3_dimensions() -> None:
    output = normalize_comparison_scores(
        _all_comparable(), achievement_baseline_status="self_reported"
    )
    reason = output["overall"]["reason"]
    assert output["overall"]["status"] == "not_combined"
    for old in ("habits", "clarity"):
        assert old not in reason
    for phrase in ("practice", "written judgment"):
        assert phrase in reason


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


@pytest.mark.asyncio
async def test_gateway_outage_recovers_once_and_records_both_calls(monkeypatch):
    from app.services.llm.client import LLMResponse
    primary = SimpleNamespace(model='gateway', generate_json=AsyncMock(return_value=LLMResponse(
        data={}, provider='openlux', model='gateway', error='OpenLux request failed (TimeoutError; finish=missing)')))
    fallback = SimpleNamespace(model='independent', generate_json=AsyncMock(return_value=LLMResponse(
        data={'dimensions': []}, provider='gemini', model='independent')))
    recovery = AsyncMock()
    def select_recovery(response, **kwargs):
        assert 0 < kwargs['timeout'] <= 20
        return fallback
    monkeypatch.setattr('app.services.llm.recovery.operational_recovery_client', select_recovery)
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', recovery)
    result = await generate_comparison_scores(primary, idol_name='Mentor', user_age=28,
        user_profile_json='{}', interview_transcript_json='[]', idol_facts_json='{}', comparison_summary='Saved verdict')
    assert result is not None
    assert result['overall']['you'] is None
    assert primary.generate_json.await_count == fallback.generate_json.await_count == 1
    assert [c.kwargs['metadata']['stage'] for c in recovery.await_args_list] == ['primary', 'operational_recovery']


@pytest.mark.asyncio
async def test_invalid_content_does_not_switch_provider(monkeypatch):
    from app.services.llm.client import LLMResponse
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    monkeypatch.setattr('app.services.llm.recovery.settings', SimpleNamespace(
        gemini_api_key='test-only', gemini_quality_model='test'))
    client = SimpleNamespace(model='gateway', generate_json=AsyncMock(return_value=LLMResponse(
        data={}, provider='openlux', error='OpenLux request failed (JSONDecodeError; finish=stop)')))
    result = await generate_comparison_scores(client, idol_name='Mentor', user_age=28,
        user_profile_json='{}', interview_transcript_json='[]', idol_facts_json='{}', comparison_summary='Saved verdict')
    assert result is None
    assert client.generate_json.await_count == 1


def test_scores_prompt_example_has_no_concrete_statuses() -> None:
    """A filled-in example anchors the classifier toward its sample verdicts."""
    from pathlib import Path

    prompt = (Path(__file__).resolve().parents[2] / "prompts" / "comparison_scores.txt").read_text()
    example = prompt[prompt.index("OUTPUT (strict JSON"):]
    for status in ("comparable", "different_basis", "insufficient_user_evidence", "insufficient_idol_evidence"):
        assert f'"status": "{status}"' not in example
    assert '"you_level": 0' not in example and '"idol_level": 4' not in example
    for dimension_id in FIXED_IDS:
        assert dimension_id in example
    # The JSON scorer has no field for prose advice.
    assert "Explain a practical next learning step" not in prompt


def _prompt(name: str) -> str:
    from pathlib import Path

    return (Path(__file__).resolve().parents[2] / "prompts" / name).read_text()


def test_scores_prompt_uses_only_the_v3_vocabulary() -> None:
    prompt = _prompt("comparison_scores.txt")

    for dimension in FIXED_DIMENSIONS:
        assert f'"{dimension["id"]}"' in prompt
        assert f'"{dimension["label"]}"' in prompt
    for retired in (
        '"habits"',
        '"clarity"',
        "Capital at work",
        "Daily discipline",
        "Trusted network",
        "Strategic clarity",
        "capital at work",
    ):
        assert retired not in prompt
    assert '"version": 3' in prompt and '"version": 2' not in prompt

    lowered = " ".join(prompt.split()).casefold()
    # The definitions the server relies on.
    assert "finished pieces of work" in lowered and "accepted practice" in lowered
    assert "written analyses or decisions written down" in lowered
    assert "people the learner can ask for feedback" in lowered
    assert "money, tools or resources" in lowered
    assert "diagnostics, confidence and completed study" in lowered
    # Honest non-evidence answers and the unscored-is-not-zero stance.
    for phrase in ("prefer not to say", "don't really check", "not a zero"):
        assert phrase in lowered


def test_comparison_generate_prompt_speaks_the_v3_dimensions() -> None:
    prompt = _prompt("comparison_generate.txt")

    for label in ("Knowledge base", "Practice volume", "Capital & resources", "Network", "Written judgment"):
        assert label in prompt
    for retired in ("Daily discipline", "Strategic clarity", "Trusted network", "Capital at work"):
        assert retired not in prompt


def test_dimension_labels_come_from_the_server_seed_never_the_model() -> None:
    """R1-M1: a model-written label never reaches the learner."""
    raw = _all_comparable()
    for dimension in raw["dimensions"]:
        dimension["label"] = "Model-invented label"
    labels = {
        dimension["id"]: dimension["label"]
        for dimension in normalize_comparison_scores(raw)["dimensions"]
    }
    assert labels == {seed["id"]: seed["label"] for seed in FIXED_DIMENSIONS}


def test_scores_prompt_says_its_evidence_strings_are_shown_to_the_learner() -> None:
    """F12: basis and notes are learner copy, not scorer shorthand."""
    lowered = " ".join(_prompt("comparison_scores.txt").split()).casefold()
    assert "shown to the learner word for word" in lowered
    for banned in ("snake_case", "field or key names", "not supplied"):
        assert banned in lowered
    # The two plain replacements the app can show as they are.
    assert "you haven’t shared this yet" in lowered
    assert "no verified record of {idol_name} at {user_age} for this yet" in lowered
