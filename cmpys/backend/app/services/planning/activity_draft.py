"""Small provider-only activity contract; persisted workbooks stay canonical.

Reasoning belongs beside the field it explains on the generation wire. The
adapter only assembles private solution ownership; it does not infer answers,
invent grading criteria, approve content, or repair malformed provider output.
"""
from __future__ import annotations

import copy
import hashlib
from dataclasses import dataclass
from typing import Annotated, Any, Literal, TYPE_CHECKING

from pydantic import Field, StrictBool, ValidationError, field_validator, model_validator

from app.services.practice.contracts import (
    Activity, AnswerField, Choice, Datum, Diagram, SolutionStep, StrictModel,
)

if TYPE_CHECKING:
    from app.services.planning.package_builder import LessonPackageActivity


class _DraftField(StrictModel):
    # Reuse canonical constraints/defaults so a wire adaptation cannot relax a
    # stored field's limits. Kind-specific properties are intentionally absent.
    id: str = copy.deepcopy(AnswerField.model_fields["id"])
    label: str = copy.deepcopy(AnswerField.model_fields["label"])
    unit: str = copy.deepcopy(AnswerField.model_fields["unit"])
    rubric_criterion: str | None = copy.deepcopy(AnswerField.model_fields["rubric_criterion"])
    explanation: str = copy.deepcopy(SolutionStep.model_fields["explanation"])

    @field_validator("explanation")
    @classmethod
    def substantive_explanation(cls, value: str) -> str:
        return SolutionStep.substantive_explanation(value)


class NumberDraftField(_DraftField):
    kind: Literal["number"]
    expression: str = Field(min_length=1, max_length=300)
    tolerance: float = copy.deepcopy(AnswerField.model_fields["tolerance"])


class ChoiceDraftField(_DraftField):
    kind: Literal["choice"]
    choices: list[Choice] = Field(min_length=2, max_length=8)
    correct_choice: str = Field(min_length=1)


class TextDraftField(_DraftField):
    kind: Literal["text"]
    criteria: list[Annotated[str, Field(min_length=1, max_length=500, pattern=r"\S")]] = Field(
        min_length=1, max_length=5,
    )


DraftAnswerField = Annotated[
    NumberDraftField | ChoiceDraftField | TextDraftField, Field(discriminator="kind"),
]


def _compact_schema(value: Any, *, names: bool = False) -> Any:
    """Remove schema annotations, never a property actually called title."""
    if isinstance(value, dict):
        return {key: _compact_schema(child, names=key in {"properties", "$defs"})
                for key, child in value.items()
                if names or key not in {"title", "default"}}
    if isinstance(value, list):
        return [_compact_schema(child) for child in value]
    return value


class LessonActivityDraft(StrictModel):
    id: str = copy.deepcopy(Activity.model_fields["id"])
    title: str = copy.deepcopy(Activity.model_fields["title"])
    kind: Literal["practice", "transfer"]
    instructions: str = copy.deepcopy(Activity.model_fields["instructions"])
    data: list[Datum] = Field(max_length=20)
    hint: str = copy.deepcopy(Activity.model_fields["hint"])
    minutes_min: int = copy.deepcopy(Activity.model_fields["minutes_min"])
    minutes_max: int = copy.deepcopy(Activity.model_fields["minutes_max"])
    diagram: Diagram | None = copy.deepcopy(Activity.model_fields["diagram"])
    # Keep the large nested payload last, with one complete shape per kind.
    fields: list[DraftAnswerField] = Field(min_length=1, max_length=10,
        description="All field explanations together must contain 40 to 4000 characters. Keep every required answer and reasoning within this shared bound.")

    @field_validator("fields")
    @classmethod
    def bounded_solution_explanations(cls, fields):
        # Enforce the canonical aggregate bound on the authoring shape itself.
        # Otherwise correction refers to worked_solution, a forbidden wire key.
        if not 40 <= sum(len(field.explanation) for field in fields) <= 4000:
            raise ValueError("Combined field explanations must contain 40 to 4000 characters")
        return fields

    @classmethod
    def model_json_schema(cls, *args, **kwargs) -> dict:
        schema = _compact_schema(super().model_json_schema(*args, **kwargs))
        for name in ("NumberDraftField", "ChoiceDraftField", "TextDraftField"):
            branch = schema["$defs"][name]
            properties = branch["properties"]
            # Present ownership and assessment before its explanation, regardless
            # of Pydantic's inherited-field order. No validation rule changes.
            order = ("id", "label", "kind", "unit", "expression", "tolerance",
                     "choices", "correct_choice", "criteria", "rubric_criterion", "explanation")
            branch["properties"] = {key: properties[key] for key in order if key in properties}
            branch["required"] = [key for key in branch["properties"] if key in branch["required"]]
        return schema


class TutorialActivityDraft(LessonActivityDraft):
    """A short phase has one response, or two tightly coupled responses."""

    fields: list[DraftAnswerField] = Field(min_length=1, max_length=2,
        description="One meaningful response, optionally a second necessary reasoning response. Simplify the task, not its timing; do not bundle a long quiz inside one text field.")


class ExplanationOwnershipVerdict(StrictModel):
    """A binding decision only; never replacement prose or a quality approval."""

    acceptable: StrictBool
    target_field_id: str | None = Field(pattern=r"^[a-z][a-z0-9_]{0,39}$")
    source_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def explicit_destination_or_decline(self):
        if self.acceptable != (self.target_field_id is not None):
            raise ValueError("Assignment requires a destination; declining requires null")
        return self


@dataclass(frozen=True)
class ExplanationOwnershipCandidate:
    """An unpublished complete draft awaiting one explicit ownership decision."""

    draft: dict
    target_field_id: str
    source_sha256: str

    def assigned_draft(self) -> dict:
        # This is a validation preview until a bound verdict is accepted. It is
        # never a checkpoint or evidence of semantic ownership by itself.
        assigned = copy.deepcopy(self.draft)
        assigned["fields"][-1]["explanation"] = assigned.pop("explanation")
        return assigned

    def bind(self, data: Any) -> dict:
        verdict = ExplanationOwnershipVerdict.model_validate(data)
        if (not verdict.acceptable or verdict.target_field_id != self.target_field_id
                or verdict.source_sha256 != self.source_sha256
                or hashlib.sha256(self.draft["explanation"].encode("utf-8")).hexdigest()
                != self.source_sha256):
            raise ValueError("Explanation ownership was declined or its binding did not match")
        return self.assigned_draft()


def explanation_ownership_candidate(data: Any) -> ExplanationOwnershipCandidate | None:
    """Recognize only an extra root explanation and a missing final owner.

    Recognizing a possible destination never assigns ownership. Every other
    wire error remains terminal for this protocol, including empty rubric
    placeholders that would otherwise have their own narrow normalization.
    """
    if type(data) is not dict or type(data.get("fields")) is not list or not data["fields"]:
        return None
    last = data["fields"][-1]
    if (type(last) is not dict or "explanation" in last or type(data.get("explanation")) is not str
            or type(last.get("kind")) is not str or last["kind"] not in {"number", "choice", "text"}):
        return None
    try:
        LessonActivityDraft.model_validate(data)
    except ValidationError as exc:
        errors = [(error["type"], tuple(error["loc"]))
                  for error in exc.errors(include_input=False, include_context=False, include_url=False)]
        expected = [("extra_forbidden", ("explanation",)),
                    ("missing", ("fields", len(data["fields"]) - 1, last.get("kind"), "explanation"))]
        if len(errors) != 2 or set(errors) != set(expected):
            return None
    else:
        return None
    try:
        SolutionStep(field_id=last["id"], explanation=data["explanation"])
        source_sha256 = hashlib.sha256(data["explanation"].encode("utf-8")).hexdigest()
    except (KeyError, ValidationError, UnicodeError):
        return None
    return ExplanationOwnershipCandidate(copy.deepcopy(data), last["id"], source_sha256)


def _without_empty_text_criteria(data: Any) -> Any:
    """Remove only zero-content fresh-wire rubric entries, without mutation.

    The original capacity limit still applies. Empty or whitespace-only entries
    carry no criterion; malformed values and an entirely empty rubric remain errors.
    Canonical/saved models do not use this provider-boundary normalization.
    """
    if not isinstance(data, dict) or type(data.get("fields")) is not list:
        return data
    normalized = data
    for index, field in enumerate(data["fields"]):
        if not isinstance(field, dict) or field.get("kind") != "text":
            continue
        criteria = field.get("criteria")
        if (type(criteria) is not list or not 1 <= len(criteria) <= 5
                or not any(type(item) is str and not item.strip() for item in criteria)
                or not any(type(item) is str and item.strip() for item in criteria)):
            continue
        if normalized is data:
            normalized = copy.deepcopy(data)
        normalized["fields"][index]["criteria"] = [
            item for item in criteria if not (type(item) is str and not item.strip())
        ]
    return normalized


def parse_activity_draft(data: Any) -> LessonPackageActivity:
    """Assemble and fully validate a canonical activity without changing prose.

    Revalidate model instances as well as dictionaries: Pydantic models may have
    been mutated after construction. The lazy import avoids a builder/DTO cycle.
    The caller still validates assigned activity identity and independent transfer.
    """
    if isinstance(data, LessonActivityDraft):
        data = data.model_dump(mode="python")
    draft = LessonActivityDraft.model_validate(_without_empty_text_criteria(data))
    canonical = draft.model_dump(mode="json")
    steps = [{"field_id": field["id"], "explanation": field.pop("explanation")}
             for field in canonical["fields"]]
    canonical["worked_solution"] = {"version": 1, "steps": steps}
    from app.services.planning.package_builder import LessonPackageActivity

    return LessonPackageActivity.model_validate(canonical)


def _without_inactive_field_defaults(data: Any) -> Any:
    """Discard only exact, inert persistence defaults on the repair wire.

    Canonical fields serialize every kind's defaults. Copying those into a
    discriminated draft must not require another paid correction. Authored or
    malformed values stay present for strict validation to reject.
    """
    if not isinstance(data, dict) or not isinstance(data.get("fields"), list):
        return data
    result = copy.deepcopy(data)
    kinds = {"number": NumberDraftField, "choice": ChoiceDraftField, "text": TextDraftField}
    defaults = {"choices": [], "expression": None, "correct_choice": None,
                "tolerance": 0.01, "criteria": []}
    for field in result["fields"]:
        if not isinstance(field, dict) or field.get("kind") not in kinds:
            continue
        allowed = kinds[field["kind"]].model_fields
        for key, default in defaults.items():
            if (key not in allowed and key in field
                    and type(field[key]) is type(default) and field[key] == default):
                del field[key]
    return result


def activity_repair_reference(activity: Activity) -> dict:
    """Present an owned structured solution in the same shape as its repair.

    Legacy prose has no declared per-field ownership and is retained verbatim;
    this adapter never assigns it to a field or invents missing reasoning.
    """
    from app.services.practice.contracts import SolutionDocument

    canonical = Activity.model_validate(activity.model_dump(mode="json"))
    if not isinstance(canonical.worked_solution, SolutionDocument):
        return canonical.model_dump(mode="json")
    result = canonical.model_dump(mode="json")
    steps = result.pop("worked_solution")["steps"]
    for field, step in zip(result["fields"], steps):
        field["explanation"] = step["explanation"]
    result = _without_inactive_field_defaults(result)
    draft = LessonActivityDraft.model_validate(result)
    if parse_activity_draft(draft).model_dump(mode="json") != canonical.model_dump(mode="json"):
        raise ValueError("Repair reference changed canonical activity content")
    return draft.model_dump(mode="json")


def parse_activity_repair_draft(data: Any, *, tutorial: bool = False) -> LessonPackageActivity:
    model = TutorialActivityDraft if tutorial else LessonActivityDraft
    draft = model.model_validate(_without_inactive_field_defaults(data))
    return parse_activity_draft(draft)
