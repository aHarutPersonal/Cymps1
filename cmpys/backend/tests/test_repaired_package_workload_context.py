"""The repaired-package gate must see timing changes on unchanged tasks."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import LessonReview
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario, ScenarioClient, run_scenario


@pytest.mark.asyncio
@pytest.mark.parametrize("trigger", ["preflight", "final_review"])
async def test_timing_comparison_reaches_repair_review_and_rejection_blocks_acceptance(monkeypatch, trigger):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    monkeypatch.setattr("app.services.planning.package_builder.record_llm_response", AsyncMock())
    requests = []
    prior = {}

    class Client(ScenarioClient):
        async def generate_json(self, *, output_model, user_prompt, **kwargs):
            review_type = PackageSemanticReview if trigger == "preflight" else LessonReview
            if issubclass(output_model, review_type):
                requests.append(json.loads(user_prompt))
                issue = ("The activity scope is too short" if len(requests) == 1 else
                         "Increasing unchanged activity timers does not add work")
                data = {"acceptable": False, "issues": [{"target": "practice.guided", "description": issue}]}
                if trigger == "final_review":
                    data.update(issues=[], package_issues=[issue], practice_minutes=40,
                                contains_calculations=False, calculations=[],
                                literal_fact_ids=list(requests[-1]["numeric_spans"]))
                return LLMResponse(data=data, finish_reason="stop")
            return await super().generate_json(output_model=output_model, user_prompt=user_prompt, **kwargs)

    async def repair(step, context, *, prior_package, **kwargs):
        data = copy.deepcopy(prior_package.model_dump(mode="json"))
        activity = data["workbook"]["activities"][0]
        prior.update(id=activity["id"], low=activity["minutes_min"], high=activity["minutes_max"])
        activity["minutes_min"] += 2
        activity["minutes_max"] += 2
        package = LessonPackage.model_validate(data)
        return package, LLMResponse(data=package.model_dump(mode="json")), None

    monkeypatch.setattr("app.tasks.plans.generate_package", repair)
    case = Scenario("workload_comparison")
    case.factory = lambda **kwargs: Client(case)
    payload, _, error = await run_scenario(case)

    assert len(requests) == 2
    assert not requests[0]["context"].get("activity_timing_changes")
    assert requests[1]["context"]["activity_timing_changes"] == [{
        "activity_id": prior["id"],
        "previous_minutes": [prior["low"], prior["high"]],
        "revised_minutes": [prior["low"] + 2, prior["high"] + 2],
        "unchanged_task": True,
    }]
    assert "does not add work" in error
    assert not payload["steps"][0].get("lesson_content")
    if trigger == "preflight":
        assert not any(name.startswith("LessonSectionGroup_") for name in case.order)
    else:
        assert sum(name.startswith("LessonSectionGroup_") for name in case.order) == 8
