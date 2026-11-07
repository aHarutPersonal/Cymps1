"""Offline SQL benchmark of identical library reads before/after optimization.

Example:
python scripts/benchmark_api_reads.py --baseline-backend /path/to/before/cmpys/backend --runs 3 --out api-reads.json

Uses seeded SQLite in-memory data (no app DB/network/provider). Includes model
hydration and serialization, but no remote database RTT. Cross-version response
identity and query counts are checked for every sample. This is not production
latency or a PostgreSQL query-plan benchmark.
"""
import argparse
import asyncio
import importlib.util
import json
import math
import sys
import time
from pathlib import Path
from statistics import median
from types import SimpleNamespace

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from sqlalchemy.orm import Session
from app.api.v1.content_resources import list_library_resources
from tests.test_api_read_performance import LocalDatabase, make_library_database, seed_library


def baseline_handler(path):
    path = Path(path) / "app/api/v1/content_resources.py"
    spec = importlib.util.spec_from_file_location("baseline_content_resource_api", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.list_library_resources


async def sample(engine, handler, owner):
    with Session(engine) as session:
        db = LocalDatabase(session)
        start = time.perf_counter()
        result = await handler(db, SimpleNamespace(id=owner), kind=None, q=None,
                               sort="title", limit=50, offset=0)
        output = result.model_dump(mode="json")
        elapsed = (time.perf_counter() - start) * 1000
        return output, {"milliseconds": elapsed, "queries": len(db.statements)}


async def benchmark(baseline, runs):
    scenarios = []
    for size in (50, 500, 5000):
        engine = make_library_database()
        with Session(engine, expire_on_commit=False) as session:
            seed = seed_library(session, shared_count=size)
            owner = seed.owner
        # Warm imported code and each compiled statement cache separately.
        await sample(engine, baseline, owner)
        await sample(engine, list_library_resources, owner)
        samples = {"baseline": [], "candidate": []}
        for _ in range(runs):
            before, old = await sample(engine, baseline, owner)
            after, new = await sample(engine, list_library_resources, owner)
            assert before == after, "Library results changed"
            assert new["queries"] == 2
            samples["baseline"].append(old); samples["candidate"].append(new)
        summary = {}
        for variant, values in samples.items():
            durations = sorted(value["milliseconds"] for value in values)
            summary[variant] = {"median_ms": round(median(durations), 3),
                                "p95_ms": round(durations[math.ceil(.95 * len(durations)) - 1], 3),
                                "queries": sorted(set(value["queries"] for value in values))}
        scenarios.append({"shared_resources": size, "page_size": 50,
                          "identical_responses": True, "summary": summary, "samples": samples})
        engine.dispose()
    return {"kind": "offline in-memory SQLite ORM read; no remote RTT or live load", "runs": runs,
            "scenarios": scenarios}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-backend", required=True, type=Path)
    parser.add_argument("--runs", default=3, type=int)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("runs must be positive")
    result = asyncio.run(benchmark(baseline_handler(args.baseline_backend), args.runs))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"kind": result["kind"], "scenarios": [
        {key: value for key, value in scenario.items() if key != "samples"}
        for scenario in result["scenarios"]]}, indent=2))


if __name__ == "__main__":
    main()
