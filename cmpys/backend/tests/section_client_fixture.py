"""Adapt legacy lesson fixtures to the new provider request granularity.

The fake providers reuse their existing full-lesson text as a fixture, but
return only the exact fields requested by each real section schema. Production
orchestration is not patched or bypassed. Dedicated section-writer tests cover
malformed/extra response fields and the preflight tests cover its rejection.
"""
from functools import wraps
import copy
import json

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanDetailLessonSectionsOutput
from app.services.planning.package_review import PackageReview
from app.services.planning.package_preflight import PackageSemanticReview


def structured_activity_fixture(activity):
    """Upgrade only mocked new generation, leaving saved legacy fixtures intact."""
    value = copy.deepcopy(activity)
    if isinstance(value.get("worked_solution"), str):
        value["worked_solution"] = {
            "version": 1,
            "steps": [{"field_id": field["id"], "explanation": activity["worked_solution"]}
                      for field in activity["fields"]],
        }
    return value


def structured_package_fixture(package):
    value = copy.deepcopy(package)
    value["workbook"]["activities"] = [
        structured_activity_fixture(activity) for activity in value["workbook"]["activities"]]
    return value


def activity_draft_fixture(activity):
    """Project canonical mocked generation into its field-local wire shape.

    This is only a fake-provider fixture adapter. Saved-state fixtures retain
    their canonical form, and the real draft converter validates every response.
    Malformed values and nonempty incompatible properties remain visible to it.
    """
    value = structured_activity_fixture(activity)
    document = value.pop("worked_solution", None)
    if isinstance(document, dict) and isinstance(document.get("steps"), list):
        steps = {step.get("field_id"): step.get("explanation")
                 for step in document["steps"] if isinstance(step, dict)}
        for field in value.get("fields", []):
            if not isinstance(field, dict):
                continue
            if field.get("id") in steps:
                field["explanation"] = steps[field["id"]]
            common = {"id", "label", "kind", "explanation", "rubric_criterion", "unit"}
            allowed = common | {"number": {"expression", "unit", "tolerance"},
                                "text": {"criteria"},
                                "choice": {"choices", "correct_choice"}}.get(field.get("kind"), set())
            defaults = {"unit": "", "choices": [], "expression": None,
                        "correct_choice": None, "tolerance": 0.01, "criteria": []}
            for key, default in defaults.items():
                if key not in allowed and field.get(key) == default:
                    field.pop(key, None)
    else:
        # Preserve deliberately malformed legacy material for rejection tests.
        value["worked_solution"] = document
    return value


def section_client(method):
    @wraps(method)
    async def generate(self, *args, **kwargs):
        schema = kwargs.get("output_model")
        if isinstance(schema, type) and issubclass(schema, (PackageReview, PackageSemanticReview)):
            return LLMResponse(data={"acceptable": True, "issues": []})
        grouped = schema is not None and schema.__name__.startswith("LessonSectionGroup_")
        package_piece = schema is not None and schema.__name__ in {"LessonPackageSeed", "LessonPackageActivity", "LessonActivityDraft"}
        from app.services.planning.lesson_package import LessonPackage
        result = await method(self, *args, **{**kwargs, **(
            {"output_model": PlanDetailLessonSectionsOutput} if grouped else
            {"output_model": LessonPackage} if package_piece else {})})
        if grouped and isinstance(result.data, dict):
            result.data = {key: value for key, value in result.data.items() if key in schema.model_fields}
        if package_piece and not result.error and isinstance(result.data, dict):
            package = copy.deepcopy(result.data)
            activities = package["workbook"]["activities"]
            if schema.__name__ == "LessonPackageSeed":
                result.data = {
                    "workbook_title": package["workbook"]["title"],
                    "teaching_cases": package.get("teaching_cases", []),
                    "activity_briefs": [
                        {"id": activity["id"], "kind": activity["kind"], "scope": activity["instructions"]}
                        for activity in activities
                    ],
                }
            else:
                brief = json.loads(kwargs["user_prompt"])["activity_brief"]
                adapter = activity_draft_fixture if schema.__name__ == "LessonActivityDraft" else structured_activity_fixture
                result.data = adapter(next(activity for activity in activities if activity["id"] == brief["id"]))
        if package_piece and not isinstance(result, LLMResponse):
            result = LLMResponse(**{key: getattr(result, key) for key in LLMResponse.model_fields
                                    if hasattr(result, key)})
        return result
    return generate
