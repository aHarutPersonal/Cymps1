"""Fence diagnostics report every defect with its line and a concrete fix.

Normalisation rewrites only harmless variants (a note after the total, a bare
unit line, semicolons in text cells); the grammar itself is unchanged.
"""
from app.services.planning.tutorial_blocks import fence_error, fence_errors, normalize_fence, parse_check, parse_steps
from app.services.planning.tutorial_visuals import normalize_native_fences, tutorial_section_issues

STEPS_OK = """title: Garden plot (fictional case)
unit: m²
Base × height | 24 | 6 × 4, the rectangle two copies of the triangle would form.
÷ 2 (half) | −12 | A triangle is half of that rectangle.
= Area of the plot | 12
"""


def test_valid_fence_has_no_defects_and_is_unchanged_by_normalisation():
    assert fence_errors("steps", STEPS_OK) == [] and fence_error("steps", STEPS_OK) is None
    assert normalize_fence("steps", STEPS_OK) == STEPS_OK


def test_every_steps_defect_is_reported_with_its_line():
    body = """title: Demo
cm
Base | 30 | The chosen side.
Height | x | Perpendicular.
= Sub | 44
Note row without cells
= Area | 210 | half of it
"""
    errors = fence_errors("steps", body)
    text = "\n".join(errors)
    assert "line 'cm'" in text and "unit: cm" in text
    assert "line 'Height | x | Perpendicular.'" in text and "plain number" in text
    assert "line '= Sub | 44'" in text and 'only the last line may start with "="' in text
    assert "line 'Note row without cells'" in text
    assert "line '= Area | 210 | half of it'" in text
    assert 'remove the text after the number on the "=" row' in text
    assert len(errors) >= 5
    # The joined form keeps every defect too.
    assert all(error in fence_error("steps", body) for error in errors)


def test_sum_mismatch_names_the_running_total_rule_and_the_product_row():
    body = """title: Pennant banner area
unit: sq cm
Base | 30 | The chosen side, measured along the bottom edge.
Height | 14 | Perpendicular from the base line to the vertex.
Rectangle | 420 | 30 × 14 gives the full rectangle's area.
− Other half | −210 | Two identical pennants fill one rectangle, so one is half.
= Pennant area | 210
"""
    [error] = fence_errors("steps", body)
    assert "total 210 must equal the sum of the rows above it (254)" in error
    assert "every row with a number adds into the running total" in error
    assert "give inputs such as base or height an empty number cell and put the value in the note" in error  # labels hold no numerals (round 2)
    assert "write a product as one row" in error


def test_inputs_with_empty_number_cells_are_valid():
    body = """title: Pennant banner area
unit: sq cm
Base 30 cm | | The chosen side.
Height 14 cm | | Perpendicular to the base.
Base × height | 420 | 30 × 14.
÷ 2 (half) | −210 | A triangle is half the rectangle.
= Pennant area | 210
"""
    assert fence_errors("steps", body) == []


def test_check_reports_banned_character_and_missing_answer_together():
    body = """Q: Which detail supports Reading B?
- [ ] The vote
- [ ] The closing appeal
Why: Value words invite feelings; the others are background facts.
"""
    errors = fence_errors("check", body)
    assert any("semicolon" in error and "line 'Why:" in error for error in errors)
    assert any("mark at least one correct option with [x]" in error for error in errors)


def test_formula_count_defect_points_to_one_equation():
    body = "title: Two views\n= Profit\n+ Revenue\n− Costs\nvs\n= Cash\n+ Collected\n− Paid\n"
    errors = fence_errors("formula", body)
    assert any("needs 2-6 term lines, found 7" in error and "one equation" in error for error in errors)
    assert any("line 'vs'" in error for error in errors)


def test_comparison_heading_without_latin_letter_suggests_translation():
    body = "Փորձարկելի չէ\n- Ա\n- Բ\nvs\nՓորձարկելի է\n- Գ\n- Դ\n"
    errors = fence_errors("comparison", body)
    assert errors and all("Latin letter" in error for error in errors)
    assert any("translation in parentheses" in error for error in errors)


def test_normalisation_keeps_banned_patterns_and_real_errors():
    braces = "title: X\nA | 1 | {note}\nB | 2 | ok\n= T | 3\n"
    assert normalize_fence("steps", braces) == braces and fence_errors("steps", braces)
    arrow = "Q: A => B?\n- [x] yes\n- [ ] no\nWhy: Because.\n"
    assert normalize_fence("check", arrow) == arrow and fence_errors("check", arrow)
    html = "title: X\nA | 1 | <b>bold</b>\nB | 2 | ok\n= T | 3\n"
    assert normalize_fence("steps", html) == html and fence_errors("steps", html)


def test_normalisation_rewrites_only_harmless_variants():
    body = ("title: Demo\ncm\nA | 1 | first; second\nB | 2 | ok;\n= Total | 3 | a note\n")
    assert normalize_fence("steps", body) == "title: Demo\nunit: cm\nA | 1 | first, second\nB | 2 | ok\n= Total | 3\n"
    assert parse_steps(normalize_fence("steps", body)) is not None
    # A unit header already present: the bare line stays (and is still rejected).
    twice = "title: Demo\nunit: cm\nm²\nA | 1 | a\nB | 2 | b\n"
    assert normalize_fence("steps", twice) == twice
    # A long or numeric bare line is never turned into a unit.
    for line in ("A longer step without cells", "42"):
        text = f"title: Demo\n{line}\nA | 1 | a\nB | 2 | b\n"
        assert normalize_fence("steps", text) == text
    # Only the final "=" row loses its note; a mid-fence "=" row is a real defect.
    mid = "title: Demo\nA | 1 | a\n= Sub | 1 | note\nB | 2 | b\n= T | 3\n"
    assert normalize_fence("steps", mid) == mid
    check = "Q: Which one; and why?\n- [x] This; that\n- [ ] Other\nWhy: First; second.\n"
    assert normalize_fence("check", check) == "Q: Which one, and why?\n- [x] This, that\n- [ ] Other\nWhy: First, second.\n"
    assert parse_check(normalize_fence("check", check)) is not None
    assert normalize_fence("steps", normalize_fence("steps", body)) == normalize_fence("steps", body)


def test_normalisation_preserves_crlf_and_surrounding_text():
    text = "Intro; prose keeps its semicolon.\n\n```steps\r\ntitle: Demo\r\nA | 1 | a; b\r\nB | 2 | c\r\n= T | 3 | n\r\n```\r\nAfter; too."
    out = normalize_native_fences(text)
    assert out == ("Intro; prose keeps its semicolon.\n\n```steps\r\ntitle: Demo\r\nA | 1 | a, b\r\n"
                   "B | 2 | c\r\n= T | 3\r\n```\r\nAfter; too.")


def test_two_steps_fences_are_each_validated():
    first = "```steps\ntitle: A\nX | 1 | a\nY | 2 | b\n= T | 3\n```"
    second = "```steps\ntitle: B\nX | 1 | a\nY | 2 | b\n= T | 4\n```"
    issues = tutorial_section_issues({"worked_example": first + "\n\n" + second})
    assert any(issue.startswith("worked_example must include exactly one valid steps fence; found 2")
               and "never a second steps fence" in issue for issue in issues)
    assert any(issue.startswith("worked_example steps fence 2 is invalid: total 4") for issue in issues)
    assert not any("steps fence 1 is invalid" in issue for issue in issues)


def test_each_defect_becomes_its_own_section_issue():
    body = "```steps\ntitle: A\nX | 1 | a\n= Mid | 1\nY | z | b\n= T | 3\n```"
    issues = [issue for issue in tutorial_section_issues({"worked_example": body})
              if issue.startswith("worked_example steps fence is invalid: ")]
    assert len(issues) == 2
