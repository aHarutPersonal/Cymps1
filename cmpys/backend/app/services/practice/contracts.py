"""Private exercise definitions and deterministic assessment; no provider calls."""

import ast
import hashlib
import json
import math
import operator
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Datum(StrictModel):
    id: str = Field(pattern=r"^[a-z][a-z0-9_]{0,39}$")
    label: str = Field(min_length=1, max_length=160)
    value: float
    unit: str = Field(default="", max_length=40)


def calculate(expression: str, data: dict[str, float]) -> float:
    """Evaluate bounded arithmetic only. Never execute generated/user code."""
    try:
        tree = ast.parse(expression, mode="eval")
    except (SyntaxError, RecursionError) as exc:
        raise ValueError("Invalid arithmetic expression") from exc
    if len(list(ast.walk(tree))) > 64:
        raise ValueError("Expression is too complex")
    operations = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
    }

    def visit(node):
        if isinstance(node, ast.Expression):
            result = visit(node.body)
        elif isinstance(node, ast.Constant) and type(node.value) in (int, float):
            result = float(node.value)
        elif isinstance(node, ast.Name) and node.id in data:
            result = data[node.id]
        elif isinstance(node, ast.UnaryOp) and isinstance(
            node.op, (ast.UAdd, ast.USub)
        ):
            result = visit(node.operand) * (-1 if isinstance(node.op, ast.USub) else 1)
        elif isinstance(node, ast.BinOp) and type(node.op) in operations:
            result = operations[type(node.op)](visit(node.left), visit(node.right))
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "sqrt"
            and len(node.args) == 1
            and not node.keywords
        ):
            result = math.sqrt(visit(node.args[0]))
        else:
            raise ValueError("Unsupported arithmetic")
        if not math.isfinite(result) or abs(result) > 1e15:
            raise ValueError("Invalid arithmetic result")
        return result

    try:
        return float(visit(tree))
    except (ArithmeticError, OverflowError) as exc:
        raise ValueError("Invalid arithmetic") from exc


class Choice(StrictModel):
    id: str = Field(pattern=r"^[a-z][a-z0-9_]{0,39}$")
    label: str = Field(min_length=1, max_length=300)


class AnswerField(StrictModel):
    id: str = Field(pattern=r"^[a-z][a-z0-9_]{0,39}$")
    label: str = Field(min_length=1, max_length=300)
    kind: Literal["number", "choice", "text"]
    unit: str = Field(default="", max_length=40)
    choices: list[Choice] = Field(default_factory=list, max_length=8)
    expression: str | None = Field(default=None, max_length=300)
    correct_choice: str | None = None
    tolerance: float = Field(default=0.01, ge=0, le=1)
    criteria: list[str] = Field(default_factory=list, max_length=5)
    rubric_criterion: str | None = Field(default=None, min_length=5, max_length=500)

    @model_validator(mode="after")
    def check_contract(self):
        if self.kind == "number" and not self.expression:
            raise ValueError("Numeric field needs a computable expression")
        ids = [c.id for c in self.choices]
        if len(set(ids)) != len(ids):
            raise ValueError("Duplicate choice ids")
        if self.kind == "choice" and (len(ids) < 2 or self.correct_choice not in ids):
            raise ValueError("Choice field needs a valid answer")
        if self.kind == "text" and (
            not self.criteria
            or any(not c.strip() or len(c) > 500 for c in self.criteria)
        ):
            raise ValueError("Text field needs substantive criteria")
        return self


class Point(StrictModel):
    label: str = Field(min_length=1, max_length=12)
    x: float = Field(ge=0, le=100)
    y: float = Field(ge=0, le=100)


class Diagram(StrictModel):
    caption: str = Field(min_length=1, max_length=300)
    points: list[Point] = Field(min_length=2, max_length=12)
    closed: bool = True


class Activity(StrictModel):
    id: str = Field(pattern=r"^[a-z][a-z0-9_]{0,39}$")
    title: str = Field(min_length=1, max_length=160)
    kind: Literal["practice", "transfer"]
    instructions: str = Field(min_length=40, max_length=4000)
    data: list[Datum] = Field(default_factory=list, max_length=20)
    fields: list[AnswerField] = Field(min_length=1, max_length=10)
    hint: str = Field(min_length=10, max_length=1500)
    worked_solution: str = Field(min_length=40, max_length=4000)
    minutes_min: int = Field(ge=1, le=45)
    minutes_max: int = Field(ge=1, le=60)
    diagram: Diagram | None = None

    @model_validator(mode="after")
    def check_activity(self):
        if self.minutes_min > self.minutes_max:
            raise ValueError("Invalid time interval")
        for values in (self.data, self.fields):
            ids = [v.id for v in values]
            if len(ids) != len(set(ids)):
                raise ValueError("Duplicate ids")
        values = {d.id: d.value for d in self.data}
        for field in self.fields:
            if field.kind == "number":
                calculate(field.expression, values)
        return self


class Workbook(StrictModel):
    title: str = Field(min_length=1, max_length=160)
    activities: list[Activity] = Field(min_length=2, max_length=6)

    @model_validator(mode="after")
    def check_sequence(self):
        ids = [a.id for a in self.activities]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate activity ids")
        if (
            self.activities[0].kind != "practice"
            or self.activities[-1].kind != "transfer"
        ):
            raise ValueError("Start with practice and finish with a new transfer case")
        return self


class FieldReview(StrictModel):
    field_id: str
    criterion_met: list[bool] = Field(min_length=1, max_length=5)
    feedback: str = Field(min_length=10, max_length=1500)
    uncertain: bool = False


class TextReview(StrictModel):
    fields: list[FieldReview] = Field(min_length=1, max_length=10)


class DraftRequest(StrictModel):
    revision: int = Field(ge=0)
    answers: dict[str, str] = Field(max_length=60)

    @model_validator(mode="after")
    def bound_answers(self):
        if (
            any(len(k) > 85 or len(v) > 8000 for k, v in self.answers.items())
            or sum(map(len, self.answers.values())) > 48000
        ):
            raise ValueError("Answer exceeds practice limits")
        return self


class SubmitRequest(StrictModel):
    revision: int = Field(ge=0)
    request_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{8,80}$")
    activity_id: str = Field(max_length=40)


def lesson_version(item, step: dict) -> str:
    # Includes immutable job identity AND content, covering old artifacts too.
    generation = (item.details_json or {}).get("_generation") or {}
    payload = {"job": generation.get("job_id"), "step": step}
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()


def public_workbook(workbook: Workbook) -> dict:
    result = workbook.model_dump()
    for activity in result["activities"]:
        activity.pop("hint")
        activity.pop("worked_solution")
        for field in activity["fields"]:
            for key in ("expression", "correct_choice", "tolerance", "criteria"):
                field.pop(key)
    return result


def validate_answers(workbook: Workbook, answers: dict[str, str]) -> None:
    allowed = {f"{a.id}.{f.id}" for a in workbook.activities for f in a.fields}
    if set(answers) - allowed:
        raise ValueError("Unknown answer field")


def grade_fixed(activity: Activity, answers: dict[str, str]) -> list[dict]:
    result = []
    for field in activity.fields:
        raw = answers.get(f"{activity.id}.{field.id}", "").strip()
        if not raw:
            raise ValueError("Complete every field before checking")
        if field.kind == "text":
            continue
        if field.kind == "number":
            expected = calculate(
                field.expression, {d.id: d.value for d in activity.data}
            )
            try:
                # A single decimal comma is accepted; thousands separators are not.
                number = float(raw.replace(",", "."))
                passed = (
                    math.isfinite(number) and abs(number - expected) <= field.tolerance
                )
            except ValueError:
                passed = False
        else:
            passed = raw == field.correct_choice
        result.append(
            {
                "field_id": field.id,
                "passed": passed,
                "feedback": "Correct."
                if passed
                else "Check the supplied data and your calculation."
                if field.kind == "number"
                else "Reconsider this choice using the lesson.",
            }
        )
    return result


def combine_review(
    activity: Activity, fixed: list[dict], review: TextReview | None
) -> list[dict]:
    expected = {f.id: f for f in activity.fields if f.kind == "text"}
    if expected:
        if (
            review is None
            or len(review.fields) != len(expected)
            or {f.field_id for f in review.fields} != set(expected)
        ):
            raise ValueError("Incomplete review")
        for field in review.fields:
            if len(field.criterion_met) != len(expected[field.field_id].criteria):
                raise ValueError("Incomplete rubric review")
            fixed.append(
                {
                    "field_id": field.field_id,
                    "passed": all(field.criterion_met) and not field.uncertain,
                    "feedback": field.feedback,
                    "uncertain": field.uncertain,
                    "criterion_met": field.criterion_met,
                    "criteria": list(expected[field.field_id].criteria),
                    "score": sum(field.criterion_met),
                    "max_score": len(field.criterion_met),
                }
            )
    return fixed
