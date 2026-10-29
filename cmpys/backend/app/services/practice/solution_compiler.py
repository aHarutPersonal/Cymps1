"""Render private answer arithmetic from its canonical source, with exact provenance.

The author supplies field-addressed explanations. The compiler supplies only the
numeric equations and fixed-choice answer labels. It never certifies whether a
formula, label, unit, choice or explanation models the intended task correctly.
Independent semantic review and verification of all authored numbers still apply.
"""

from __future__ import annotations

import ast
import hashlib
import json
import math
from dataclasses import dataclass
from decimal import Decimal
from typing import Mapping

from app.services.practice.contracts import Activity, SolutionDocument, calculate


SOLUTION_RENDERER_VERSION = 1
MAX_RENDERED_SOLUTION_CHARS = 48_000
MAX_CALCULATION_RECORDS = 10


@dataclass(frozen=True)
class SolutionCalculationRecord:
    activity_id: str
    case_id: str
    field_id: str
    step_index: int
    node_path: tuple[str, ...]
    source_path: tuple[str, ...]
    start: int
    end: int
    text: str
    expression: str
    datum_ids: tuple[str, ...]
    result: float
    literal: str
    unit: str


@dataclass(frozen=True)
class CompiledSolution:
    text: str
    records: tuple[SolutionCalculationRecord, ...]
    source_hash: str
    rendered_hash: str
    renderer_version: int = SOLUTION_RENDERER_VERSION


def _hash_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _literal(value: float) -> str:
    """Preserve the canonical float's round-trip decimal; never infer rounding."""
    if not math.isfinite(value) or abs(value) > 1e15:
        raise ValueError("Invalid solution arithmetic value")
    literal = format(Decimal(str(value)), "f")
    if "." in literal:
        literal = literal.rstrip("0").rstrip(".")
    return literal


def _numeric_expression(node: ast.AST, data: dict[str, float]) -> str:
    """Keep every operator and signed operand in an explicit parenthesized tree."""
    if isinstance(node, ast.Name) and node.id in data:
        value = _literal(data[node.id])
        return f"({value})" if value.startswith("-") else value
    if isinstance(node, ast.Constant) and type(node.value) in (int, float):
        return _literal(float(node.value))
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        return "(" + ("+" if isinstance(node.op, ast.UAdd) else "-") + _numeric_expression(node.operand, data) + ")"
    if isinstance(node, ast.BinOp) and type(node.op) in {ast.Add, ast.Sub, ast.Mult, ast.Div}:
        operation = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.Div: "/"}[type(node.op)]
        return "(" + _numeric_expression(node.left, data) + " " + operation + " " + _numeric_expression(node.right, data) + ")"
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == "sqrt" and len(node.args) == 1 and not node.keywords):
        return "sqrt(" + _numeric_expression(node.args[0], data) + ")"
    raise ValueError("Unsupported private solution arithmetic")


def compile_worked_solution(activity: Activity | Mapping) -> CompiledSolution:
    """Revalidate and compile canonical private input; accept no supplied proof.

    Offsets are Python character offsets into ``text``, matching numeric source
    inventory offsets. Hashes use UTF-8 bytes. Only dedicated equation lines are
    recorded; authored headings, units and explanations never gain proof merely
    by appearing beside one. Legacy strings are returned byte-for-byte unchanged.
    """
    raw = activity.model_dump(mode="json") if isinstance(activity, Activity) else dict(activity)
    canonical = Activity.model_validate(raw)
    source_hash = _hash_text(json.dumps(canonical.model_dump(mode="json"), ensure_ascii=False,
                                       sort_keys=True, separators=(",", ":"), allow_nan=False))
    solution = canonical.worked_solution
    if isinstance(solution, str):
        return CompiledSolution(solution, (), source_hash, _hash_text(solution))
    if not isinstance(solution, SolutionDocument):
        raise ValueError("Unsupported private solution source")

    data = {datum.id: datum.value for datum in canonical.data}
    blocks: list[str] = []
    records: list[SolutionCalculationRecord] = []
    length = 0

    def append(value: str) -> tuple[int, int]:
        nonlocal length
        if blocks:
            length += 2
        start = length
        length += len(value)
        if length > MAX_RENDERED_SOLUTION_CHARS:
            raise ValueError("Rendered private solution exceeds its bounded size")
        blocks.append(value)
        return start, length

    for step_index, (step, field) in enumerate(zip(solution.steps, canonical.fields)):
        # Exact authored labels remain separate source blocks, including every
        # number they contain. A compiler calculation never blesses a label.
        append(field.label)
        if field.kind == "number":
            calculate(field.expression, data)
            tree = ast.parse(field.expression, mode="eval")
            node = tree.body
            datum_ids = tuple(sorted({part.id for part in ast.walk(node)
                                      if isinstance(part, ast.Name) and part.id != "sqrt"}))
            derived = bool(datum_ids) and isinstance(node, (ast.BinOp, ast.UnaryOp, ast.Call))
            # A raw input reference (or a legacy constant-shaped field) has no
            # derived arithmetic to prove. Render it without a compiler proof;
            # ordinary fact/semantic verification still owns that value. This
            # does not convert a constant answer into a valid lesson derivation.
            if not derived:
                append(_literal(calculate(field.expression, data)))
                if field.unit:
                    append(field.unit)
            else:
                expression = ast.unparse(node)
                value = calculate(expression, data)
                literal = _literal(value)
                unit = field.unit
                equation = _numeric_expression(node, data) + " = " + literal
                # A declared unit is authored source, not computable arithmetic.
                # Keep it in a separate block so numerical quantities hidden in
                # its spelling cannot be covered by a calculation record.
                start, end = append(equation)
                records.append(SolutionCalculationRecord(
                    activity_id=canonical.id, case_id="practice." + canonical.id,
                    field_id=field.id, step_index=step_index, node_path=(),
                    source_path=("worked_solution",), start=start, end=end, text=equation,
                    expression=expression, datum_ids=datum_ids, result=value,
                    literal=literal, unit=unit))
                if len(records) > MAX_CALCULATION_RECORDS:
                    raise ValueError("Too many private solution calculations")
                if unit:
                    append(unit)
        elif field.kind == "choice":
            choice = next(choice for choice in field.choices if choice.id == field.correct_choice)
            append(choice.label)
        elif field.kind == "multi_choice":
            # Each correct label is its own authored block, in the order the
            # learner sees the choices.
            for choice in field.choices:
                if choice.id in field.correct_choices:
                    append(choice.label)
        append(step.explanation)
    text = "\n\n".join(blocks)
    return CompiledSolution(text, tuple(records), source_hash, _hash_text(text))


def render_worked_solution(activity: Activity | Mapping) -> str:
    """Keep the existing learner-facing hint/solution API a plain string."""
    return compile_worked_solution(activity).text
