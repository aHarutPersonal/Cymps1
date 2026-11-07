"""Offline scheduling benchmark, not a model-quality or live latency evaluation.

Run: PYTHONPATH=. python scripts/benchmark_tutorial_reviews.py --runs 3 --out reviews.json

The real full/focused review validators inspect the same saved synthetic fixture
and receive the same canned responses in each variant. No provider is built and
telemetry is replaced. Stage delays are observations from the latest QA tutorial
review passes; all times are projected from fixed, scaled waits. Models, review
prompts, token budgets and approvals are identical between variants.
"""
import argparse
import asyncio
import copy
import json
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from statistics import median
from types import SimpleNamespace

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

# Observed provider durations, seconds. These are fixed inputs, not new live runs.
PROFILES = {
    "initial_review": {"full": 11.94, "public": 21.70, "alignment": 7.74},
    "review_after_repair": {"full": 23.59, "public": 12.78, "alignment": 7.86},
}


@contextmanager
def offline():
    from app.core.config import settings
    from app.services.llm import telemetry
    previous_focused = settings.tutorial_focused_accuracy_review
    original_record = telemetry.record_llm_response
    async def record(**kwargs):
        return True
    settings.tutorial_focused_accuracy_review = True  # Enable the focused-review profile.
    telemetry.record_llm_response = record
    try:
        yield
    finally:
        settings.tutorial_focused_accuracy_review = previous_focused
        telemetry.record_llm_response = original_record


async def sequential_review(lesson, *, client_factory, context):
    """Previous scheduling, with exactly the same validators and merge logic."""
    from app.services.planning import lesson_review as review
    result = await review._review_lesson_full(lesson, client_factory=client_factory, context=context)
    failures, response, client = result
    if failures or response.error or not review._needs_public_accuracy_review(lesson, context):
        return result
    results = await review._collect_public_accuracy(lesson, client_factory=client_factory, context=context)
    return review._merge_public_accuracy(results, context=context, full_response=response, full_client=client)


async def run_once(mode, profile, scale, slots):
    from app.services.llm.client import LLMResponse
    from app.services.planning import lesson_review as review
    from tests.test_public_section_review import _conflict, _focused_review, _response
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    inputs_before = copy.deepcopy((lesson, context))
    canned = _focused_review(lesson, context)
    calls, semaphore = [], asyncio.Semaphore(slots)
    started = time.perf_counter()

    async def generate(**request):
        model = request["output_model"]
        stage = ("public" if model is review.PublicAccuracyReview else
                 "alignment" if model is review.AlignmentOnlyReview else "full")
        async with semaphore:
            call = {"stage": stage, "start_s": time.perf_counter() - started}
            calls.append(call)
            await asyncio.sleep(PROFILES[profile][stage] * scale)
            call["end_s"] = time.perf_counter() - started
        if stage == "full":
            assert issubclass(model, review.PackagedLessonReview), model
            payload = json.loads(request["user_prompt"])
            assert payload["lesson"]["lesson_content"] == lesson["lesson_content"]
            return _response(lesson)
        key = "practice_alignment" if stage == "alignment" else "public_sections"
        return LLMResponse(data={key: copy.deepcopy(canned[key])}, finish_reason="stop")

    factory = lambda **kwargs: SimpleNamespace(model="offline", generate_json=generate)
    runner = sequential_review if mode == "sequential" else review.review_lesson
    with offline():
        failures, response, _ = await runner(lesson, client_factory=factory, context=context)
    wall = time.perf_counter() - started
    # Scale provider waiting only; keep local validators/JSON work unscaled.
    busy = []
    for call in sorted(calls, key=lambda item: item["start_s"]):
        if busy and call["start_s"] <= busy[-1][1]:
            busy[-1][1] = max(busy[-1][1], call["end_s"])
        else:
            busy.append([call["start_s"], call["end_s"]])
    def project(offset):
        wait = sum(max(0, min(end, offset) - start) for start, end in busy if start < offset)
        return wait / scale + offset - wait
    elapsed = project(wall)
    for call in calls:
        call["start_s"], call["end_s"] = project(call["start_s"]), project(call["end_s"])
    assert not failures and not response.error, (failures, response.error)
    assert (lesson, context) == inputs_before, "Review changed its source inputs"
    assert sorted(call["stage"] for call in calls) == ["alignment", "full", "public"]
    return {"mode": mode, "profile": profile, "slots": slots, "projected_seconds": round(elapsed, 3),
            "call_count": len(calls), "timeline": calls, "result": response.data}


async def benchmark(runs, scale):
    measurements = []
    for profile in PROFILES:
        for slots in (2, 3):
            for _ in range(runs):
                baseline = await run_once("sequential", profile, scale, slots)
                winner = await run_once("parallel", profile, scale, slots)
                assert baseline.pop("result") == winner.pop("result"), "Scheduling changed the verdict"
                measurements.extend((baseline, winner))
    summaries = []
    for profile in PROFILES:
        for slots in (2, 3):
            values = {mode: median(row["projected_seconds"] for row in measurements
                                  if row["profile"] == profile and row["slots"] == slots and row["mode"] == mode)
                      for mode in ("sequential", "parallel")}
            saved = values["sequential"] - values["parallel"]
            summaries.append({"profile": profile, "slots": slots, "runs": runs,
                              "sequential_median_s": round(values["sequential"], 3),
                              "parallel_median_s": round(values["parallel"], 3),
                              "saved_s": round(saved, 3),
                              "review_speedup_percent": round(saved / values["sequential"] * 100, 1)})
    return {"kind": "offline fixed-delay scheduling projection; not a live generation or quality claim",
            "time_scale": scale, "latency_inputs_seconds": PROFILES,
            "summary": summaries, "runs": measurements}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--time-scale", type=float, default=.05)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.runs < 1 or not 0 < args.time_scale <= 1:
        parser.error("runs must be positive and time-scale must be in (0, 1]")
    result = asyncio.run(benchmark(args.runs, args.time_scale))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"kind": result["kind"], "summary": result["summary"]}, indent=2))


if __name__ == "__main__":
    main()
