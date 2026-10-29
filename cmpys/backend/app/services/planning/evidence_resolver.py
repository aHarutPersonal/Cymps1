"""Deterministic literal-fact evidence for numeric review spans.

A span whose every numeric value is a declared raw datum of its owning case
needs no model-written evidence: this module proposes the LiteralFactCheck a
reviewer would write. Proposals are not approvals: the caller must run them
through the review gate (package_preflight._scope_failures), keep only the
accepted claims, and send every rejected or unresolved span to the reviewer.
Derived results, workload metadata and any span with an unbound value stay
with the reviewer.
"""
from __future__ import annotations

import re
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
