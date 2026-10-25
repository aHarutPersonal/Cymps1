"""Compact references retain exact field bindings and standalone context."""
import copy

import pytest

from app.services.planning.lesson_package import LessonPackage, render_package_results
from tests.lesson_package_fixtures import package_payload


def package():
    data = package_payload()
    data["teaching_cases"] = [{"id": "sample", "assumptions": "Use the supplied fictional quantities without further assumptions.",
        "data": [{"id": "amount", "label": "Amount", "value": 10},
                 {"id": "divisor", "label": "Divisor", "value": 3}],
        "results": [{"id": "ratio", "label": "Ratio", "expression": "amount / divisor", "unit": "",
                     "decimal_places": 2}]}]
    guided, transfer = data["workbook"]["activities"]
    guided["title"] = "Guided analysis"
    guided["fields"][0]["label"] = "State the claim"
    guided["fields"].append({**copy.deepcopy(guided["fields"][0]), "id": "reason", "label": "Explain the reason"})
    transfer["title"] = "New scenario"
    transfer["fields"][0]["label"] = "Apply the method"
    return LessonPackage.model_validate(data)


def test_first_reference_introduces_each_activity_once_per_prose_string():
    source = {"guided_practice": (
        "Start [[practice:guided.argument]], then [[practice:guided.reason]]. "
        "Next [[practice:transfer.argument]]; revisit [[practice:guided.argument]]. "
        "Check [[result:sample.ratio]] and [[result:sample.ratio]].")}
    expected = {"guided_practice": (
        "Start Guided analysis — State the claim, then Explain the reason. "
        "Next New scenario — Apply the method; revisit State the claim. Check 3.33 and 3.33.")}
    exercise = package()
    before_source, before_package = copy.deepcopy(source), exercise.model_dump(mode="json")
    assert render_package_results(source, exercise) == expected
    assert source == before_source
    assert exercise.model_dump(mode="json") == before_package


def test_reference_context_resets_for_each_section_and_standalone_substep():
    source = {
        "guided_practice": "[[practice:guided.argument]] then [[practice:guided.reason]].",
        "check_your_understanding": "[[practice:guided.reason]] again.",
        "worked_example": "[[result:sample.ratio]]",
        "substeps": ["[[practice:guided.argument]] and [[practice:guided.reason]].",
                     "[[practice:guided.reason]] before [[practice:transfer.argument]].",
                     ["[[practice:guided.argument]] alone."]],
    }
    result = render_package_results(source, package())
    assert result["guided_practice"] == "Guided analysis — State the claim then Explain the reason."
    assert result["check_your_understanding"] == "Guided analysis — Explain the reason again."
    assert result["substeps"] == ["Guided analysis — State the claim and Explain the reason.",
                                  "Guided analysis — Explain the reason before New scenario — Apply the method.",
                                  ["Guided analysis — State the claim alone."]]


def test_identical_titles_do_not_merge_distinct_activity_owners():
    exercise = package()
    exercise.workbook.activities[-1].title = exercise.workbook.activities[0].title
    source = {"text": "[[practice:guided.argument]] and [[practice:transfer.argument]]."}
    assert render_package_results(source, exercise, require_all=False) == {
        "text": "Guided analysis — State the claim and Guided analysis — Apply the method."}


def test_result_binding_does_not_consume_activity_introduction_or_change_precision():
    source = {"text": "[[result:sample.ratio]] then [[practice:guided.reason]] then [[practice:guided.argument]]."}
    assert render_package_results(source, package(), require_all=False) == {
        "text": "3.33 then Guided analysis — Explain the reason then State the claim."}


@pytest.mark.parametrize("token", ["[[practice:guided.missing]]", "[[practice:other.argument]]", "[[result:other.ratio]]"])
def test_unknown_binding_remains_rejected_even_when_full_coverage_is_optional(token):
    with pytest.raises(ValueError, match="Unknown teaching result ID"):
        render_package_results({"text": token}, package(), require_all=False)


def test_repeated_field_does_not_satisfy_another_required_field_binding():
    source = {"text": "[[practice:guided.argument]] [[practice:guided.argument]] "
                      "[[practice:transfer.argument]] [[result:sample.ratio]]"}
    with pytest.raises(ValueError, match="Every teaching result and practice field"):
        render_package_results(source, package())


def test_rendering_only_replaces_tokens_without_rewriting_authored_text():
    source = {"text": "Guided analysis already appears here; retain 3.3300. "
                      "[[practice:guided.argument]] then [[practice:guided.reason]]."}
    assert render_package_results(source, package(), require_all=False) == {
        "text": "Guided analysis already appears here; retain 3.3300. "
                "Guided analysis — State the claim then Explain the reason."}
