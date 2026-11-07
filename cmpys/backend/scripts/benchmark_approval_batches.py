"""Measure approval bookkeeping only; no content or model decisions are skipped.

Run with LLM_PROVIDER=dummy and LLM_USAGE_TELEMETRY_ENABLED=false.
An optional first argument selects the backend source tree to benchmark.
"""

import json
from pathlib import Path
from statistics import median
import sys
import time


def main() -> None:
    backend = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[1])
    sys.path.insert(0, backend)

    from app.services.llm.schemas import PlanDetailStepOutput
    from app.services.planning.lesson_package import (
        LessonPackage,
        provenance,
        reusable_published_approval,
    )
    from app.tasks.plans import _approved_candidate_step_ids
    from tests.lesson_package_fixtures import package_payload
    from tests.test_plan_detail_output_schema import _valid_payload

    package = LessonPackage.model_validate(package_payload())
    payload = _valid_payload(lesson_count=20, material_count=1)
    payload["steps"] = [
        PlanDetailStepOutput.model_validate(step).model_dump(mode="json")
        for step in payload["steps"]
    ]
    packages = {step["id"]: package for step in payload["steps"]}
    approvals = {step["id"]: provenance(step, package) for step in payload["steps"]}
    rows = []
    for _ in range(4):
        started = time.perf_counter()
        result = _approved_candidate_step_ids(payload, packages, approvals)
        batch_ms = (time.perf_counter() - started) * 1000
        assert result == set(packages)

        started = time.perf_counter()
        for step in payload["steps"]:
            assert reusable_published_approval(step, package, approvals[step["id"]])
        rows.append({
            "batch_ms": batch_ms,
            "reuse_20_ms": (time.perf_counter() - started) * 1000,
        })

    measured = rows[1:]
    print(json.dumps({
        "case": "20 exact approved lessons",
        "warmup_excluded": True,
        "runs": measured,
        "median_batch_ms": median(row["batch_ms"] for row in measured),
        "median_reuse_20_ms": median(row["reuse_20_ms"] for row in measured),
    }, indent=2))


if __name__ == "__main__":
    main()
