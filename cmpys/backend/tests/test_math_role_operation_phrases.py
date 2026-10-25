"""A bounded operation object phrase is syntax, never an independent fact."""
import pytest

from app.services.planning.lesson_review import MathRoleCheck, _math_role_diagnostic
from tests.test_math_role_evidence import package_for, role


def diagnostic(quote, *, kind="inverse_multiplier", expression="base * height / 2",
               source=None, changes=None, field_ids=None):
    package = package_for(expression=expression)
    owner = package.review_context()["private_workbook"]["activities"][0]
    evidence = MathRoleCheck.model_validate({
        **role(quote=quote, kind=kind), **(changes or {}),
    })
    return _math_role_diagnostic(evidence, source or quote, owner, owner, field_ids or set())


@pytest.mark.parametrize("quote,kind,expression", [
    ("բազմապատկիր մակերեսը 2-ով", "inverse_multiplier", "base * height / 2"),
    ("բազմապատկիր եռանկյան մակերեսը 2-ով", "inverse_multiplier", "base * height / 2"),
    ("բազմապատկես տվյալ եռանկյան մակերեսը 2-ով", "inverse_multiplier", "base * height / 2"),
    ("բազմապատկիր տվյալ պատկերի չափված եռանկյան ամբողջ մակերեսը 2-ով", "inverse_multiplier", "base * height / 2"),
    ("բաժանիր կողմերի արտադրյալը 2-ի", "divisor", "base * height / 2"),
    ("բաժանելով կողմերի արտադրյալը 2-ով", "divisor", "base * height / 2"),
    ("բազմապատկիր հիմքը 2-ով", "multiplier", "base * 2"),
    ("բաժանիր արդյունքը 2-ի", "inverse_divisor", "base * 2"),
    ("բազմապատկիր 2-ով", "inverse_multiplier", "base * height / 2"),
    ("multiply the area by 2", "inverse_multiplier", "base * height / 2"),
])
def test_explicit_bounded_object_phrase_consumes_only_coefficient(quote, kind, expression):
    interval, reason = diagnostic(quote, kind=kind, expression=expression)
    assert reason is None
    assert quote[interval[0]:interval[1]] == "2"


@pytest.mark.parametrize("quote", [
    "բազմապատկիր տվյալ պատկերի չափված եռանկյան ամբողջ ներքին մակերեսը 2-ով",  # Seven object words.
    "բազմապատկիր area 2-ով",  # Do not guess mixed-language object syntax.
    "բազմապատկիր մակերեսը + հիմքը 2-ով",
    "բազմապատկիր մակերեսը / հիմքը 2-ով",
    "բազմապատկիր մակերեսը (հիմքը) 2-ով",
    "բազմապատկիր մակերեսը 3 անգամ 2-ով",
    "բազմապատկիր մակերեսը\n2-ով",
    "բազմապատկիր մակերեսը\t2-ով",
    "բազմապատկիր ոչ մակերեսը 2-ով",
    "բազմապատկիր մի մակերեսը 2-ով",
    "բազմապատկիր առանց մակերեսի 2-ով",
    "բազմապատկիր բաժանելով մակերեսը 2-ով",
    "բազմապատկիր մակերեսը հանած հիմքը 2-ով",
    "բազմապատկիր մակերեսը գումարած հիմքը 2-ով",
    "բաժանիր հետո բազմապատկիր մակերեսը 2-ով",
    "բազմապատկիր երկու մակերեսները 2-ով",
    "Մի բազմապատկիր մակերեսը 2-ով",
    "բազմապատկիր մակերեսը սմ 2-ով",
    "բազմապատկիր մակերեսը սմ² 2-ով",
    "բազմապատկիր մակերեսը 2-ի",  # Multiplication has instrumental inflection.
    "բազմապատկիր մակերեսը 2",
    "բազմապատկիր մակերեսը 2-ով%",
    "բազմապատկիր մակերեսը 2-ով hundred",
])
def test_ambiguous_object_or_coefficient_is_not_evidence(quote):
    interval, reason = diagnostic(quote)
    assert interval is None and reason


@pytest.mark.parametrize("changes,field_ids", [
    ({"case_id": "practice.transfer"}, set()),
    ({"field_id": "missing"}, set()),
    ({"role": "divisor"}, set()),
    ({"symbol_bindings": {"x": "base"}}, set()),
    ({}, {"other_field"}),
])
def test_object_grammar_does_not_relax_owner_or_formula_binding(changes, field_ids):
    interval, reason = diagnostic("բազմապատկիր մակերեսը 2-ով", changes=changes, field_ids=field_ids)
    assert interval is None and reason


def test_inner_division_does_not_authorize_whole_answer_inverse():
    interval, reason = diagnostic("բազմապատկիր մակերեսը 2-ով", expression="base + height / 2")
    assert interval is None and reason


def test_duplicate_source_quote_is_still_rejected():
    quote = "բազմապատկիր մակերեսը 2-ով"
    interval, reason = diagnostic(quote, source=f"{quote}, հետո {quote}։")
    assert interval is None and reason


@pytest.mark.parametrize("prefix", ["Մի ", "Մի՛ ", "Մի՜ ", "ոչ թե ", "Մի՛ տվյալ դեպքում "])
def test_quote_cannot_drop_preceding_clause_negation(prefix):
    quote = "բազմապատկիր մակերեսը 2-ով"
    interval, reason = diagnostic(quote, source=f"{prefix}{quote}։")
    assert interval is None and reason


def test_negation_in_a_previous_sentence_does_not_bind_this_operation():
    quote = "բազմապատկիր մակերեսը 2-ով"
    interval, reason = diagnostic(quote, source=f"Մի՛ պատճենիր պատասխանը։ Այժմ {quote}։")
    assert interval is not None and reason is None


def test_long_clause_cannot_truncate_away_negation():
    quote = "բազմապատկիր մակերեսը 2-ով"
    interval, reason = diagnostic(quote, source="Մի՛ " + "նշված դեպքում " * 40 + quote + "։")
    assert interval is None and reason
