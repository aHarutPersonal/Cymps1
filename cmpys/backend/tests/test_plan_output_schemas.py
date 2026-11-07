"""Plan output schemas the models write against (moved from the retired test_zai.py, 2026-11-07)."""
import pytest
from pydantic import ValidationError


def test_outline_schema_does_not_offer_invalid_in_app_material():
    from app.services.llm.schemas import PlanItemDetailsOutlineOutput
    schema = PlanItemDetailsOutlineOutput.model_json_schema()
    assert "in_app_lesson" not in schema["$defs"]["PlanOutlineMaterialOutput"]["properties"]["type"]["enum"]


def test_execution_schema_requires_metrics_and_mission_depth():
    from app.services.llm.schemas import ExecutionBinaryTask, ExecutionPlanWeek
    task = dict(title="Practice", description="Classify the supplied transactions", type="practice", estimated_hours=1)
    with pytest.raises(ValidationError):
        ExecutionBinaryTask.model_validate(task)
    with pytest.raises(ValidationError):
        ExecutionPlanWeek.model_validate(dict(week_number=1, primary_mission="Too short", binary_tasks=[]))
    schema = ExecutionBinaryTask.model_json_schema()
    assert "success_metric" in schema["required"]
    assert schema["properties"]["success_metric"]["type"] == "string"
