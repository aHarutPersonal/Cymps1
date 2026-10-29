"""An activity that shows numbers must declare them as case data before review."""
import json

import pytest

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.package_builder import (
    LessonPackageActivity, UndeclaredNumbersError, _diagnostics, require_declared_numbers,
)


def _activity(name: str, extra_instructions: str = "") -> LessonPackageActivity:
    draft = json.loads(resolve_prompt_text(name).split("\n", 1)[1])
    draft["instructions"] += extra_instructions
    return LessonPackageActivity.model_validate(parse_activity_draft(draft))


def test_numbers_without_case_data_are_rejected():
    # Live run: four regenerations quoted "$82,000" in a sample memo with
    # data: []; the evidence review rejected every package after its full cost.
    activity = _activity("tutorial_exemplar_qualitative.txt",
                         " The memo says owner earnings were $82,000 last year.")
    assert activity.data == []
    with pytest.raises(UndeclaredNumbersError):
        require_declared_numbers(activity)


@pytest.mark.parametrize("name", ["tutorial_exemplar_qualitative.txt", "tutorial_exemplar_quantitative.txt"])
def test_exemplars_declare_what_they_show(name):
    require_declared_numbers(_activity(name))


def test_correction_names_the_missing_data_without_echoing_source_text():
    [diagnostic] = _diagnostics(UndeclaredNumbersError(2))
    assert diagnostic["type"] == "undeclared_numbers"
    assert "data" in diagnostic["message"] and "$" not in diagnostic["message"]
    # A corrected draft once declared rates beside their inputs; the evidence
    # check could not bind them, so derived results must stay expressions.
    assert "Derived results" in diagnostic["message"] and "never data" in diagnostic["message"]
