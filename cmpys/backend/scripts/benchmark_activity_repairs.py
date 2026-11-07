"""Offline scheduling benchmark; fake provider delays do not measure live quality.

python scripts/benchmark_activity_repairs.py --runs 3 --time-scale .05 --out repairs.json

Both paths use identical valid original/repaired fixtures and real repair parsing,
scoping and package merging. Each independent draft sleeps 8 assumed seconds,
scaled for a short run. No provider or database calls are made. Passing this
fixture leaves semantic_accepted unset: full package preflight is still required.
"""
import argparse
import asyncio
import copy
import json
from pathlib import Path
from statistics import median
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import _repair_public_activities, _repair_public_activities_serial
from tests.test_parallel_activity_repair import drafts
from tests.test_scoped_activity_repair import structured_package


async def run_once(function, scale):
    original = structured_package()
    snapshot = original.model_dump(mode="json")
    responses = drafts(original)
    calls = []
    recorded = []

    async def generate(**request):
        key = json.loads(request["user_prompt"])["previous_activity"]["id"]
        calls.append(key)
        await asyncio.sleep(8 * scale)
        return LLMResponse(data=copy.deepcopy(responses[key]), attempt_id=key)

    async def record(**kwargs):
        recorded.append(kwargs["response"].attempt_id)
        return True

    async def forbidden(*args, **kwargs):
        raise AssertionError("Live provider construction is forbidden")

    with patch("app.services.llm.telemetry.record_llm_response", record), patch(
            "app.services.llm.client.get_llm_client", forbidden):
        started = time.perf_counter()
        corrected, response, _ = await function({}, {}, original,
            {activity.id: None for activity in original.workbook.activities}, [],
            client_factory=lambda **kwargs: SimpleNamespace(model="offline", generate_json=generate))
        elapsed = time.perf_counter() - started
    assert corrected is not None and not response.error and response.semantic_accepted is None
    assert original.model_dump(mode="json") == snapshot
    assert sorted(calls) == ["guided", "transfer"]
    assert len(recorded) == 1 and recorded[0] != response.attempt_id
    return {"wall_seconds": round(elapsed, 4), "simulated_seconds": round(elapsed / scale, 3),
            "calls": len(calls), "package": corrected.model_dump(mode="json")}


async def benchmark(runs, scale):
    results = {"serial": [], "parallel": []}
    for _ in range(runs):
        for key, function in (("serial", _repair_public_activities_serial),
                              ("parallel", _repair_public_activities)):
            results[key].append(await run_once(function, scale))
    packages = [row.pop("package") for rows in results.values() for row in rows]
    assert all(package == packages[0] for package in packages)
    medians = {key: round(median(row["simulated_seconds"] for row in rows), 3)
               for key, rows in results.items()}
    return {"kind": "synthetic scheduling benchmark, not live generation", "time_scale": scale,
            "assumed_seconds_per_draft": 8, "identical_validated_output": True,
            "median_simulated_seconds": medians,
            "reduction_percent": round(100 * (1 - medians["parallel"] / medians["serial"]), 2),
            "runs": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--time-scale", type=float, default=.05)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.runs < 1 or not 0 < args.time_scale <= 1:
        parser.error("runs must be positive and time-scale in (0, 1]")
    result = asyncio.run(benchmark(args.runs, args.time_scale))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
