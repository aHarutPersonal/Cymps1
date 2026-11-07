"""Phase 0 of the near-zero-rejection plan: deterministic fixes; no provider calls."""
import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import (
    InternalIdLeakError, LessonPackage, internal_id_leaks, relabel_internal_ids, require_no_internal_ids,
)
from app.tasks.plans import _assemble_parallel_lesson_response
from tests.test_internal_id_gate import guided, payload
from tests.test_short_tutorial_pipeline import outline, sections


def relabelled(instructions, teaching_cases=None):
    value = payload(instructions=instructions)
    if teaching_cases is not None:
        value["teaching_cases"] = teaching_cases
    pkg = LessonPackage.model_validate(value)
    return relabel_internal_ids(guided(pkg), pkg.teaching_cases), pkg.teaching_cases


def test_ids_become_labels_with_sentence_case_and_code_spans_untouched():
    activity, _ = relabelled("revenue_earned_current is earned before collection. Keep `revenue_earned_current` "
                             "as the config key and subtract expenses_incurred_current from it.")
    assert activity.instructions == (
        "Current-period revenue earned is earned before collection. Keep `revenue_earned_current` "
        "as the config key and subtract current-period expenses incurred from it.")
    assert internal_id_leaks(activity) == []


def test_case_ids_read_as_words_and_relabelling_is_idempotent():
    cases = [{"id": "quiet_lane", "assumptions": "A quiet street cafe sells coffee on account.",
              "data": [], "results": []}]
    activity, teaching = relabelled("Original fictional example from the quiet_lane case: compare earned "
                                    "revenue with cash collected.", cases)
    assert "from the quiet lane case" in activity.instructions
    assert relabel_internal_ids(activity, teaching) == activity
    require_no_internal_ids(activity, teaching)


def test_unnamed_ids_and_datum_wording_still_fail_closed():
    cases = [{"id": "case_b7", "assumptions": "A quiet street cafe sells coffee on account.",
              "data": [], "results": []}]
    activity, teaching = relabelled("Compare the case_b7 example and state the raw datum you used here.", cases)
    with pytest.raises(InternalIdLeakError) as caught:
        require_no_internal_ids(activity, teaching)
    assert {name for _, name in caught.value.leaks} == {"case_b7", "raw datum"}


@pytest.mark.parametrize("target_minutes", [5, 6, 7, 8])
def test_tutorial_assembly_keeps_practice_within_the_published_schema(target_minutes):
    # A ~510-word lesson reads in 3 minutes; 8 allotted minutes once yielded 5
    # practice minutes, above the tutorial schema's 4, and failed every time.
    result = LLMResponse(data=sections())
    _assemble_parallel_lesson_response(result, step=outline(1)["steps"][0],
                                      material_titles={"Resource 1"}, target_minutes=target_minutes)
    assert result.error is None
    assert 2 <= result.data["practice_minutes"] <= 4
    assert result.data["estimate_minutes"] == result.data["reading_minutes"] + result.data["practice_minutes"]


def test_identical_duplicate_json_keys_are_lossless_and_conflicts_still_fail():
    from app.services.llm.protocol import JSONProtocolError, _complete_json_object
    # 12 of 12 captured duplicate-key failures repeated the same value.
    assert _complete_json_object('{"minutes_min": 1, "minutes_max": 2, "minutes_min": 1}') == {
        "minutes_min": 1, "minutes_max": 2}
    for raw in ('{"minutes_min": 1, "minutes_min": 2}', '{"flag": 1, "flag": true}'):
        with pytest.raises(JSONProtocolError):
            _complete_json_object(raw)


def test_wire_noise_drops_remarks_and_infers_only_unambiguous_kinds():
    from app.services.planning.activity_draft import without_wire_noise
    data = {"id": "guided", "minutes_max_note": "kept short for novices",
            "fields": [{"id": "total", "expression": "a + b", "label": "Total", "label_note": "plain"},
                       {"id": "pick", "correct_choice": "x", "criteria": ["Explains why."], "label": "Pick"},
                       {"id": "why", "kind": "text", "criteria": ["Names the cause."], "label": "Why"}]}
    cleaned = without_wire_noise(data)
    assert "minutes_max_note" not in cleaned and "label_note" not in cleaned["fields"][0]
    assert cleaned["fields"][0]["kind"] == "number"
    assert "kind" not in cleaned["fields"][1]          # choice and text evidence: left for validation
    assert cleaned["fields"][2] == data["fields"][2]
    assert "minutes_max_note" in data                   # the input is not mutated
    long_note = {"fields": [], "design_note": "x" * 201}
    assert without_wire_noise(long_note) == long_note   # long text may be content: keep it
