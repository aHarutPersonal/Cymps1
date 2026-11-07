"""Deterministic literal-fact evidence for numeric review spans.

A span whose every numeric value is a declared raw datum of its owning case
needs no model-written evidence: this module proposes the LiteralFactCheck a
reviewer would write. Proposals are not approvals: the caller must run them
through the review gate (package_preflight._scope_failures), keep only the
accepted claims, and send every rejected or unresolved span to the reviewer.
Since Phase 0.4, ``server_bound_evidence`` also binds results the server
computes from declared expressions (exact values only, gate-verified).
Workload metadata, a value written under another declared label and any
span with an unbound value stay with the reviewer.
"""
from __future__ import annotations

import ast as _ast
import re
from dataclasses import dataclass as _dataclass
from decimal import ROUND_HALF_UP as _ROUND_HALF_UP
from decimal import Decimal, InvalidOperation

from app.services.planning.lesson_review import _NUMBER_LITERAL, LiteralFactCheck, _numeric_values

# Same pattern the gate uses to refuse derived results as literal facts
# (grounded_failures' calculation_signal); such spans stay with the reviewer.
_CALCULATION_SIGNAL = re.compile(
    r"(?:\d\s*=\s*|\bequals\s+|"
    r"\b(?:profit|margin|total(?:\s+passes)?|result|net cash|discount|premium)\b"
    r"\s*(?:(?:is|was|of|equals|comes to|will be)\s+|[:=]\s*)?[$€£]?\s*)("
    + _NUMBER_LITERAL.pattern + r")", re.I)


def package_cases(package: dict | None) -> dict[str, dict[str, float]]:
    """Case data keyed exactly as the review gate names cases."""
    return {
        prefix + case["id"]: {datum["id"]: datum["value"] for datum in case.get("data", []) if "id" in datum}
        for prefix, items in (("teaching.", (package or {}).get("teaching_cases", [])),
                              ("practice.", ((package or {}).get("private_workbook") or {}).get("activities", [])))
        for case in items if case.get("data")
    }


def resolve_literal_evidence(
    spans: dict[str, str], owners: dict[str, str], cases: dict[str, dict[str, float]],
    *, units: dict[str, tuple] | None = None, ownerless_teaching: bool = False,
    unique_values: bool = False,
) -> tuple[list[LiteralFactCheck], list[str]]:
    """Bind spans made only of their owner's data; return facts and resolved claim ids.

    With ownerless_teaching, a span without an owner (lesson prose) is bound
    only when exactly one teaching case holds all its values; a value shared
    by two teaching cases, or held only by a practice case, stays unbound.
    With unique_values, a value held by two data of the case (rent and fee
    both 1200) does not say which datum is stated, so the span stays unbound.
    """
    facts, resolved = [], []
    for claim_id, span in spans.items():
        if _CALCULATION_SIGNAL.search(span) or re.search(r"\bresult\b", span, re.I):
            continue
        values = _numeric_values(span, units=(units or {}).get(claim_id, ()))
        if not values:
            continue
        owner = owners.get(claim_id)
        if owner is None and ownerless_teaching:
            matches = [case_id for case_id, data in cases.items()
                       if case_id.startswith("teaching.") and values <= _by_value(data).keys()]
            owner = matches[0] if len(matches) == 1 else None
        data = cases.get(owner or "")
        by_value = _by_value(data) if data else {}
        if not by_value or not values <= by_value.keys():
            continue
        if unique_values and any(len(by_value[value]) != 1 for value in values):
            continue
        datum_ids = sorted({datum_id for value in values for datum_id in by_value[value]})
        facts.append(LiteralFactCheck(claim_id=claim_id, case_id=owner, datum_ids=datum_ids))
        resolved.append(claim_id)
    return facts, resolved


def _by_value(data: dict[str, float]) -> dict[Decimal, list[str]]:
    by_value = {}
    try:
        for datum_id, value in data.items():
            by_value.setdefault(Decimal(str(value)), []).append(datum_id)
    except InvalidOperation:
        return {}
    return by_value


# ---------------------------------------------------------------------------
# Server-computed values (Phase 0.3/0.4, 2026-11-04).
# ---------------------------------------------------------------------------


@_dataclass(frozen=True)
class ServerValue:
    """One value the server computes from a case's own declared data.

    ``kind`` is datum, result (a declared number field or teaching result),
    result_step (a sub-expression of a result), misconception (a declared
    wrong answer) or misconception_step. ``places`` is the declared display
    rounding, if the case declares one.
    """

    value: Decimal
    expression: str
    kind: str
    places: int | None = None
    source_id: str = ""

    def displays(self, literal: str) -> bool:
        """Exact equality, or equality at the declared rounding; nothing looser."""
        try:
            shown = Decimal(literal)
        except InvalidOperation:
            return False
        if shown == self.value:
            return True
        if self.places is None:
            return False
        rounded = self.value.quantize(Decimal(1).scaleb(-self.places), rounding=_ROUND_HALF_UP)
        return shown == rounded and shown.as_tuple().exponent == rounded.as_tuple().exponent


def _expression_steps(expression: str, data: dict[str, float]):
    """(text, value) of the whole expression first, then of every inner operation."""
    from app.services.practice.contracts import calculate
    try:
        tree = _ast.parse(expression.translate(_TYPESET), mode="eval")
        steps = [(_ast.unparse(tree.body), calculate(_ast.unparse(tree.body), data))]
    except (SyntaxError, ValueError, RecursionError):
        return []
    for node in _ast.walk(tree.body):
        if node is not tree.body and isinstance(node, (_ast.BinOp, _ast.Call)):
            text = _ast.unparse(node)
            try:
                steps.append((text, calculate(text, data)))
            except ValueError:
                continue
    return steps


_TYPESET = str.maketrans({"×": "*", "÷": "/", "−": "-", "·": "*", "⋅": "*"})


def _case_data(case: dict) -> dict[str, float]:
    return {datum["id"]: float(datum["value"]) for datum in (case or {}).get("data", []) or []
            if isinstance(datum, dict) and isinstance(datum.get("id"), str)
            and type(datum.get("value")) in (int, float)}


def case_server_values(case: dict, *, teaching: bool) -> list[ServerValue]:
    """Every datum, declared result and result step of ONE case, from its own data only."""
    data = _case_data(case)
    values = [ServerValue(Decimal(str(value)), key, "datum", source_id=key) for key, value in data.items()]
    expressions = []
    if teaching:
        for result in case.get("results", []) or []:
            if isinstance(result, dict) and isinstance(result.get("expression"), str):
                places = result.get("decimal_places")
                expressions.append((result["expression"], places if type(places) is int else None,
                                    str(result.get("id") or ""), "result"))
    else:
        for field in case.get("fields", []) or []:
            if not isinstance(field, dict) or field.get("kind") != "number":
                continue
            if isinstance(field.get("expression"), str):
                expressions.append((field["expression"], None, str(field.get("id") or ""), "result"))
            for misconception in field.get("misconceptions") or []:
                if isinstance(misconception, dict) and isinstance(misconception.get("expression"), str):
                    expressions.append((misconception["expression"], None, str(field.get("id") or ""),
                                        "misconception"))
    for expression, places, source_id, kind in expressions:
        steps = _expression_steps(expression, data)
        for index, (text, value) in enumerate(steps):
            # Only the whole declared expression carries its declared rounding;
            # its steps are exact values.
            values.append(ServerValue(Decimal(str(value)), text, kind if index == 0 else kind + "_step",
                                      places if index == 0 else None, source_id))
    return values


def _case_index(package: dict | None) -> dict[str, tuple[dict, list[ServerValue]]]:
    index = {}
    for case in (package or {}).get("teaching_cases", []) or []:
        if isinstance(case, dict) and case.get("id") and case.get("data"):
            index["teaching." + case["id"]] = (case, case_server_values(case, teaching=True))
    for activity in ((package or {}).get("private_workbook") or {}).get("activities", []) or []:
        if isinstance(activity, dict) and activity.get("id") and activity.get("data"):
            index["practice." + activity["id"]] = (activity, case_server_values(activity, teaching=False))
    return index


_UNSELECTED_OPTION = re.compile(r"^\s*-\s*\[ \]\s")
_COEFFICIENTS = frozenset({Decimal(1), Decimal(2), Decimal(100)})


def _shows_operation(view: str, literal: str, expression: str, data: dict[str, float],
                     units: set[str] | None = None) -> bool:
    """The span itself displays this step's operation with ``literal`` as its value.

    "8 × 5 = 40" shows the step b * h; a bare "the area is 40" does not, so an
    intermediate value (often the very mistake a misconception names) is
    never bound from prose alone. Mirrors the gate's own equation consumption.
    """
    from app.services.planning.lesson_review import (
        _SmallPowers, _closed_numeric_equation_side_details, _equality_result_literal, _partial_evaluation_matches)

    try:
        tree = _ast.parse(expression.translate(_TYPESET), mode="eval")

        class Bind(_ast.NodeTransformer):
            def visit_Name(self, node):
                return _ast.copy_location(_ast.Constant(value=data[node.id]), node) if node.id in data else node

        derived = _SmallPowers().visit(Bind().visit(tree)).body
        shown = Decimal(literal)
    except (SyntaxError, ValueError, RecursionError, InvalidOperation):
        return False
    for equality in re.finditer(r"(?<![<>=!])=(?!=)", view):
        for left, position in ((True, equality.start()), (False, equality.end())):
            details = _closed_numeric_equation_side_details(view, position, left=left)
            if details is None:
                continue
            opposite = _equality_result_literal(view, equality, expression_is_left=left, units=units)
            try:
                if opposite is None or Decimal(opposite) != shown:
                    continue
                source = _SmallPowers().visit(_ast.parse(details[0], mode="eval")).body
                if isinstance(source, _ast.BinOp) and _partial_evaluation_matches(source, derived):
                    return True
            except (SyntaxError, ValueError, RecursionError, InvalidOperation):
                continue
    return False


# A sentence that itself calls a value wrong ("... gives 40, which is wrong").
_WRONG_MARKER = re.compile(
    r"\b(?:wrong(?:ly)?|incorrect(?:ly)?|mistaken(?:ly)?|misconceptions?|erroneous(?:ly)?|"
    r"(?:a|the|common|typical)\s+mistake|not\s+the\s+(?:area|answer|result))\b|սխալ", re.I)
_PROSE_OPERATORS = {
    _ast.Add: r"plus|added\s+to|\+",
    _ast.Sub: r"minus|less|take\s+away|−|-(?=\s)",
    _ast.Mult: r"times|multiplied\s+by|×|x|\*",
    _ast.Div: r"divided\s+by|over|÷|/",
}
_PROSE_RESULT = r"(?:giving|gives|gave|to\s+get|get|gets|=|is|are|equals?|makes?|leaves?|leaving|yields?|comes\s+to|totals?)"


def _spelled(value: float) -> str:
    text = format(Decimal(str(value)), "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


def _shows_prose_operation(view: str, literal: str, expression: str, data: dict[str, float]) -> bool:
    """The span states this step in words: "5000 minus the 400 refund, giving 4600".

    Both operands must be shown as numerals, in order, joined by the step's
    own operator word and followed by a result word and ``literal``; nothing
    is inferred from values alone.
    """
    from app.services.practice.contracts import calculate
    try:
        node = _ast.parse(expression.translate(_TYPESET), mode="eval").body
        # A left-deep chain "a - b + c" reads in order; its first operand and
        # every right operand must be shown, each after its own operator word.
        chain, firsts = [], []
        while isinstance(node, _ast.BinOp) and type(node.op) in _PROSE_OPERATORS:
            chain.append((type(node.op), _spelled(calculate(_ast.unparse(node.right), data))))
            firsts.append(_spelled(calculate(_ast.unparse(node.left), data)))
            node = node.left
        if not chain:
            return False
    except (SyntaxError, ValueError, RecursionError):
        return False
    number = r"(?<![\d.,]){}(?:\.0+)?(?![\d]|[.,]\d)"
    gap = r"[^.;:!?\d\n]{0,48}?"
    # Either the full chain ("9000 minus 2000 plus 1500 ... giving 8500") or a
    # shorter one whose first operand is an inner value ("8500 minus 5000").
    for depth in range(1, len(chain) + 1):
        pattern = number.format(re.escape(firsts[depth - 1]))
        for operator, operand in reversed(chain[:depth]):
            pattern += (gap + r"(?<!\w)(?:" + _PROSE_OPERATORS[operator] + r")(?!\w)"
                        + gap + number.format(re.escape(operand)))
        pattern += gap + r"(?<!\w)" + _PROSE_RESULT + r"(?!\w)" + gap + number.format(re.escape(literal))
        if re.search(pattern, view, re.I):
            return True
    return False


def _shown_as_operand(view: str, step: ServerValue, values: list[ServerValue], data: dict[str, float],
                      units: set[str] | None) -> bool:
    """A step shown as an operand of its parent's displayed operation.

    "Cash net flow is 8500 minus 5000, which equals 3500": 8500 and 5000 are
    the two steps of the declared cash formula, displayed with its operator
    and its result. The parent's own result must be displayed too.
    """
    try:
        target = _ast.dump(_ast.parse(step.expression, mode="eval").body)
    except (SyntaxError, ValueError, RecursionError):
        return False
    for parent in values:
        if parent.kind not in ("result", "result_step") or parent is step:
            continue
        try:
            node = _ast.parse(parent.expression, mode="eval").body
        except (SyntaxError, ValueError, RecursionError):
            continue
        if not (isinstance(node, _ast.BinOp) and target in (_ast.dump(node.left), _ast.dump(node.right))):
            continue
        shown = _spelled(float(parent.value))
        if parent.places is not None:
            shown = str(parent.value.quantize(Decimal(1).scaleb(-parent.places), rounding=_ROUND_HALF_UP))
        if (_shows_prose_operation(view, shown, parent.expression, data)
                or _shows_operation(view, shown, parent.expression, data, units)):
            return True
    return False


def _has_false_equation(view: str) -> bool:
    """Any explicit numeric equality in the span that does not hold ("9 x 8 = 36 cm²").

    Values alone cannot bind a span whose displayed arithmetic is wrong, even
    when every number in it is a correct declared value. A scalar side keeps
    its displayed precision; a percent or scaled scalar is not compared.
    """
    from app.services.planning.lesson_review import _closed_numeric_equation_side_details
    from app.services.practice.contracts import calculate

    def scalar(text: str):
        match = re.match(r"[ \u00a0\u202f]*([-+\u2212]?\d[\d,]*(?:\.\d+)?)(?![\d.,]\d)", text)
        if match is None:
            return None, None
        tail = text[match.end():]
        if re.match(r"[ \u00a0\u202f]*(?:[-+*/×÷^(]|[xX][ \u00a0]+\d)", tail):
            return None, None  # The side continues as an expression.
        if re.match(r"[ \u00a0\u202f]*(?:%|‰|percent|per\s*cent|hundred|thousand|million|billion|k\b)", tail, re.I):
            return None, "scaled"
        return Decimal(_canonical(match[1])), None

    for equality in re.finditer(r"(?<![<>=!])=(?!=)", view):
        left = _closed_numeric_equation_side_details(view, equality.start(), left=True)
        right_value, flag = scalar(view[equality.end():])
        try:
            if left is None or flag == "scaled":
                continue
            lhs = Decimal(str(calculate(left[0], {})))
            if right_value is None:
                right = _closed_numeric_equation_side_details(view, equality.end(), left=False)
                if right is None:
                    continue
                rhs = Decimal(str(calculate(right[0], {})))
                if re.fullmatch(r"\(?\s*-?\d+(?:\.\d+)?\s*\)?", left[0]):
                    shown = Decimal(left[0].strip("() "))
                    if rhs.quantize(shown, rounding=_ROUND_HALF_UP) != shown:
                        return True
                elif abs(lhs - rhs) > Decimal("1e-9"):
                    return True
            elif lhs.quantize(right_value, rounding=_ROUND_HALF_UP) != right_value:
                return True
        except (ValueError, InvalidOperation):
            return True
    return False


_CLAUSE_BREAK = re.compile(r"[.;:,!?\n]|\b(?:and|but|while|whereas|so)\b", re.I)


def _label_words(label) -> frozenset[str]:
    text = re.sub(r"\s*\([^()]*\)\s*$", "", label) if isinstance(label, str) else ""
    return frozenset(re.findall(r"[^\W\d_]+", text.lower()))


def _case_labels(case: dict) -> dict[str, frozenset[str]]:
    """Declared label words by id: data, number fields and teaching results."""
    return {item["id"]: words for key in ("data", "fields", "results") for item in (case or {}).get(key, []) or []
            if isinstance(item, dict) and isinstance(item.get("id"), str) and (words := _label_words(item.get("label")))}


def _under_another_label(view: str, shown: Decimal, items: list[ServerValue],
                         labels: dict[str, frozenset[str]]) -> bool:
    """A value written in a clause that names a different declared quantity.

    "Revenue earned is 6200" equals the expenses datum but names revenue, so
    equal values are not equal meanings: the span stays with the model
    binder. A clause runs from the previous numeral or clause break to the
    next one. The value's own label, or the label of any datum its expression
    uses, keeps the binding; an unlabelled clause ("8 × 5 = 40") is untouched.
    """
    own = set()
    for item in items:
        own.add(item.source_id)
        try:
            own.update(node.id for node in _ast.walk(_ast.parse(item.expression.translate(_TYPESET), mode="eval"))
                       if isinstance(node, _ast.Name))
        except (SyntaxError, ValueError, RecursionError):
            pass
    others = [words for key, words in labels.items() if key not in own]
    if not others:
        return False
    numerals = list(_NUMBER_LITERAL.finditer(view))
    for match in numerals:
        try:
            if Decimal(_canonical(match.group()).lstrip("+")) != shown:
                continue
        except InvalidOperation:
            continue
        before = max([0] + [found.end() for found in _CLAUSE_BREAK.finditer(view, 0, match.start())]
                     + [found.end() for found in numerals if found.end() <= match.start()])
        after = min([len(view)] + [found.start() for found in _CLAUSE_BREAK.finditer(view, match.end())]
                    + [found.start() for found in numerals if found.start() >= match.end()])
        words = set(re.findall(r"[^\W\d_]+", (view[before:match.start()] + " " + view[match.end():after]).lower()))
        if any(other <= words for other in others) and not any(labels[key] <= words for key in own if key in labels):
            return True
    return False


def _span_proposal(literals: list[str], claim_id: str, case_id: str, values: list[ServerValue],
                   *, view: str = "", data: dict[str, float] | None = None, units: set[str] | None = None,
                   labels: dict[str, frozenset[str]] | None = None):
    """Literal facts or calculations binding every literal to this one case, else None.

    Final results bind wherever they are shown. A step of a result binds only
    where the span displays that operation ("8 × 5 = 40", or in words "5000
    minus the 400 refund, giving 4600"). A value written under a different
    declared label never binds (``_under_another_label``). A misconception
    value binds only as an unselected quick-check option ("- [ ] 40") or in a sentence that itself
    calls it wrong, where the lesson presents it as a mistake.
    """
    datum_values = [item for item in values if item.kind == "datum"]
    distractor = bool(_UNSELECTED_OPTION.match(view)) or bool(_WRONG_MARKER.search(view))
    datum_ids, calculations, coefficients = set(), {}, 0
    for literal in literals:
        try:
            shown = Decimal(literal)
        except InvalidOperation:
            return None
        if shown in _COEFFICIENTS and not any(item.value == shown for item in values):
            # A formula constant ("40 ÷ 2 = 20") is consumed by the gate only as
            # part of a verified equation; otherwise the gate rejects the span.
            coefficients += 1
            continue
        matched = [item for item in datum_values if item.value == shown]
        if matched:
            if _under_another_label(view, shown, matched, labels or {}):
                return None
            datum_ids.update(item.source_id for item in matched)
            continue
        result = next((item for item in values if item.kind == "result" and item.displays(literal)), None)
        if result is None:
            result = next((item for item in values if item.kind == "result_step" and item.displays(literal)
                           and (_shows_operation(view, literal, item.expression, data or {}, units)
                                or _shows_prose_operation(view, literal, item.expression, data or {})
                                or _shown_as_operand(view, item, values, data or {}, units))), None)
        if result is None and distractor:
            result = next((item for item in values if item.kind in ("misconception", "misconception_step", "result_step")
                           and item.displays(literal)), None)
        if result is None or _under_another_label(view, shown, [result], labels or {}):
            return None
        calculations.setdefault(literal, {"claim_ids": [claim_id], "case_id": case_id,
                                          "expression": result.expression, "claimed_result": float(shown)})
    if calculations:
        # A derivation's own bound case inputs cover every raw datum in its span.
        return [], list(calculations.values())
    if coefficients or not datum_ids:
        return None
    return [LiteralFactCheck(claim_id=claim_id, case_id=case_id, datum_ids=sorted(datum_ids))], []


_CHECK_FENCE = re.compile(r"^[ \t]*```check[ \t]*\r?\n(?P<body>.*?)^[ \t]*```", re.M | re.S)
_DOUBLING = re.compile(r"\b(?:doubles?|doubled|doubling|twice|two\s+times)\b", re.I)
_HALVING = re.compile(r"\b(?:halves|halved|halving|half)\b", re.I)


def _what_if_values(case: dict, question: str) -> list[ServerValue]:
    """A quick check that doubles or halves ONE datum ("The plot base doubles to 16 m").

    The stated new value must be exactly 2x (or 1/2) one datum, with the
    doubling/halving word in the same question; every declared result is then
    recomputed with that datum replaced. Ambiguity (two data fit) binds nothing.
    """
    data = _case_data(case)
    shown = {Decimal(_canonical(match.group())) for match in _NUMBER_LITERAL.finditer(question)}
    candidates = []
    for factor, pattern, spelled in ((Decimal(2), _DOUBLING, "(2 * {})"), (Decimal("0.5"), _HALVING, "({} / 2)")):
        if not pattern.search(question):
            continue
        for key, value in data.items():
            if Decimal(str(value)) * factor in shown and Decimal(str(value)) * factor != Decimal(str(value)):
                candidates.append((key, spelled.format(key), float(Decimal(str(value)) * factor)))
    if len(candidates) != 1:
        return []
    key, replacement, new_value = candidates[0]
    values = [ServerValue(Decimal(str(new_value)), replacement, "result", source_id=key)]
    for result in case.get("results", []) or []:
        expression = result.get("expression") if isinstance(result, dict) else None
        if not isinstance(expression, str):
            continue
        substituted = re.sub(r"\b" + re.escape(key) + r"\b", replacement, expression)
        for index, (text, value) in enumerate(_expression_steps(substituted, data)):
            values.append(ServerValue(Decimal(str(value)), text, "result" if index == 0 else "result_step",
                                      source_id=str(result.get("id") or "")))
    return values


def _canonical(literal: str) -> str:
    return literal.translate(str.maketrans({",": None, " ": None, "\u00a0": None, "\u202f": None, "\u2212": "-"}))


def _check_what_ifs(lesson: dict, index: dict) -> list[tuple[int, int, str, list[ServerValue]]]:
    """(start, end, case_id, values) for each lesson quick check with one what-if."""
    source = str((lesson or {}).get("lesson_content") or "")
    found = []
    for fence in _CHECK_FENCE.finditer(source):
        question = next((line for line in fence["body"].splitlines() if re.match(r"\s*Q\s*:", line, re.I)), "")
        fits = [(key, values) for key, (case, _) in index.items() if key.startswith("teaching.")
                and (values := _what_if_values(case, question))]
        if len(fits) == 1:
            found.append((fence.start(), fence.end(), fits[0][0], fits[0][1]))
    return found


def propose_server_evidence(lesson: dict, package: dict | None,
                            claim_ids: set[str] | None = None) -> dict[str, tuple[list, list]]:
    """Exact-value proposals: every quantity of a span equals a declared datum or a
    server-computed result (or step) of ONE case.

    Practice spans bind to their owning activity first; a span that restates
    a public teaching case binds to that case when exactly one case fits.
    Lesson spans bind only when exactly one teaching case fits. Values match
    exactly, or at a teaching result's declared decimal places, never closer
    than that. Proposals are NOT approvals; see ``server_bound_evidence``.
    """
    from app.services.planning.lesson_review import (
        _operand_units, numeric_span_occurrences, numeric_span_view, span_quantity_literals)

    index = _case_index(package)
    teaching = [key for key in index if key.startswith("teaching.")]
    what_ifs = _check_what_ifs(lesson, index)
    proposals = {}
    for record in numeric_span_occurrences(lesson, package):
        if claim_ids is not None and record.claim_id not in claim_ids:
            continue
        literals = span_quantity_literals(record, package)
        if not literals:
            continue
        owner = "practice." + record.owner["id"] if record.owner and record.owner.get("id") else None
        view = numeric_span_view(record, package)
        if _has_false_equation(view):
            continue  # A wrong displayed equation stays with the model binder and source checks.

        def fit(key):
            case = index[key][0]
            return _span_proposal(literals, record.claim_id, key, index[key][1], view=view, data=_case_data(case),
                                  units=_operand_units(case), labels=_case_labels(case))

        proposal = fit(owner) if owner in index else None
        if proposal is None:
            fits = [found for key in teaching if (found := fit(key)) is not None]
            proposal = fits[0] if len(fits) == 1 else None
        if proposal is None and record.path == ("lesson", "lesson_content"):
            # A quick check's what-if values, recomputed from declared formulas.
            for lower, upper, key, extra in what_ifs:
                if lower <= record.start < upper:
                    proposal = _span_proposal(literals, record.claim_id, key, index[key][1] + extra,
                                              view=view, data=_case_data(index[key][0]),
                                              units=_operand_units(index[key][0]),
                                              labels=_case_labels(index[key][0]))
        if proposal is not None:
            proposals[record.claim_id] = proposal
    return proposals


def server_bound_evidence(lesson: dict, package: dict | None, claim_ids: set[str] | None = None):
    """Gate-verified deterministic evidence, as a ReviewEvidencePatch.

    Every proposal runs through the same evidence gate a model binder's
    answer must pass (grounded_failures and the arithmetic/precision check);
    a rejected claim is dropped and stays with the model binder.
    """
    from app.services.planning.lesson_review import LessonReview, ReviewEvidencePatch, grounded_failures

    try:
        proposals = propose_server_evidence(lesson, package, claim_ids)
    except (ValueError, TypeError, KeyError, AttributeError, InvalidOperation, RecursionError, OverflowError):
        return ReviewEvidencePatch()  # Deterministic binding fails closed: the model binder decides.
    for _ in range(4):  # Drop rejected claims, then confirm the rest together.
        if not proposals:
            return ReviewEvidencePatch()
        facts = [fact for claim in proposals.values() for fact in claim[0]]
        calculations = [check for claim in proposals.values() for check in claim[1]]
        try:
            review = LessonReview.model_validate({
                "acceptable": True, "issues": [], "practice_minutes": 1,
                "contains_calculations": bool(calculations),
                "calculations": [{"location": ", ".join(check["claim_ids"]), **check} for check in calculations],
                "literal_facts": [fact.model_dump(mode="json") for fact in facts]})
            errors = grounded_failures(review, lesson, package, expected_claim_ids=set(proposals)) + review.failures()
        except (ValueError, TypeError, KeyError, OverflowError, InvalidOperation, RecursionError):
            return ReviewEvidencePatch()
        if not errors:
            return ReviewEvidencePatch(literal_facts=facts, calculations=calculations)
        rejected = {error.split(":", 1)[0].strip() for error in errors}
        named = {key for item in rejected for key in item.split(", ")} & proposals.keys()
        if not named:
            return ReviewEvidencePatch()  # A scope-wide failure names no claim: bind nothing.
        proposals = {key: value for key, value in proposals.items() if key not in named}
    return ReviewEvidencePatch()
