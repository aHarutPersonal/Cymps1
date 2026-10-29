"""Review follow-ups: unit normalisation stays on real unit lines, and mixed
correction preambles never contradict themselves."""
import json

import pytest

from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _normalize_tutorial_fence_layout, _prompt
from app.services.planning.tutorial_blocks import fence_errors, normalize_fence
from tests.test_writer_fix_smoke_failures import SMOKE_DRAFTS, nova_package, validate

ROWS = "Base | | 6 cm along the bottom.\nHeight | | 4 cm, perpendicular.\nBase × height | 24 | 6 × 4.\n= Area | 24\n"


@pytest.mark.parametrize("line", ["cm", "m²", "sq cm", "USD", "$m", "%", "hours", "սմ", "մ"])
def test_recognised_unit_line_becomes_the_unit_header(line):
    body = f"title: Plot\n{line}\n{ROWS}"
    assert normalize_fence("steps", body) == f"title: Plot\nunit: {line}\n{ROWS}"


@pytest.mark.parametrize("line", ["6 cm", "Base 6", "Revenue", "Height", "Orders"])
def test_data_or_step_lines_are_never_turned_into_the_unit(line):
    body = f"title: Plot\n{line}\n{ROWS}"
    assert normalize_fence("steps", body) == body
    errors = fence_errors("steps", body)
    assert any(error.startswith(f"line '{line}'") for error in errors)
    assert not any("unit:" in error for error in errors)


def test_unit_hint_only_for_recognised_units():
    [error] = [e for e in fence_errors("steps", f"title: Plot\ncm\n{ROWS}") if e.startswith("line 'cm'")]
    assert "write 'unit: cm'" in error


def test_declared_case_unit_is_recognised_when_supplied():
    body = f"title: Nova\nmessages\n{ROWS}"
    assert normalize_fence("steps", body) == body
    assert normalize_fence("steps", body, units={"messages"}) == f"title: Nova\nunit: messages\n{ROWS}"
    assert normalize_fence("steps", f"title: Nova\n6 messages\n{ROWS}", units={"6 messages"}).count("unit:") == 0


def test_writer_passes_the_declared_units():
    data = {"worked_example": f"Walk it.\n\n```steps\ntitle: Nova\ncharges\n{ROWS}```"}
    assert "unit: charges" not in _normalize_tutorial_fence_layout(data)["worked_example"]
    assert "unit: charges" in _normalize_tutorial_fence_layout(data, units={"charges"})["worked_example"]


# --- correction preambles ----------------------------------------------------

def _correction(draft, issues):
    prompt = _prompt(_TUTORIAL_GROUP, "context", nova_package(), issues, previous_sections=draft)
    return prompt[prompt.index("VALIDATION ISSUES"):prompt.index("\nLESSON CONTEXT")]


FENCE = ("worked_example steps fence is invalid: line '= Sub | 1': only the last line may start with \"=\"")
MISSING = "check_your_understanding must include exactly one valid check fence; found 0"


def _short():
    return SMOKE_DRAFTS["project_design_2"]


def _long():
    draft = json.loads(json.dumps(SMOKE_DRAFTS["software_2"]))
    draft["core_framework"] += " Padding sentence that repeats the idea once more." * 40
    return draft


def _length_issue(draft):
    payload, issues = validate(draft, nova_package())
    return [issue for issue in issues if issue.startswith("tutorial fields have ")]


def test_fence_and_too_long_trim_prose_and_fix_lines_without_contradiction():
    text = _correction(_long(), [FENCE, *_length_issue(_long())])
    assert "Remove repetition and verbose phrasing" in text
    assert "Fix the native block lines named in the issues" in text
    assert "edit prose only as needed for the budget" in text
    assert "keep every other sentence unchanged" not in text and "Fix only" not in text


def test_fence_and_too_short_add_prose_and_fix_lines_without_contradiction():
    text = _correction(_short(), [FENCE, *_length_issue(_short())])
    assert "Add about" in text and "Remove nothing from the prose: keep every existing sentence and binding" in text
    assert "native block line and binding" not in text
    assert "Fix the native block lines named in the issues" in text
    assert "edit prose only as needed for the budget" in text
    assert "Fix only" not in text and "keep every other sentence unchanged" not in text


def test_missing_fence_is_added_not_fixed():
    text = _correction(_long(), [MISSING])
    assert "Add each missing native block named in the issues" in text
    assert "lines named" not in text


def test_missing_fence_and_too_short():
    text = _correction(_short(), [MISSING, *_length_issue(_short())])
    assert "Add each missing native block named in the issues" in text
    assert "edit prose only as needed for the budget" in text
    assert "keep every other sentence unchanged" not in text and "lines named" not in text


def test_fence_only_and_length_only_keep_their_instructions():
    fence_only = _correction(_long(), [FENCE])
    assert "Fix only the native block lines named in the issues" in fence_only
    assert "keep every other sentence unchanged" in fence_only and "Remove" not in fence_only
    short_only = _correction(_short(), _length_issue(_short()))
    assert "Remove nothing from the prose" in short_only and "block lines" not in short_only
    long_only = _correction(_long(), _length_issue(_long()))
    assert "Remove repetition and verbose phrasing" in long_only and "block lines" not in long_only
