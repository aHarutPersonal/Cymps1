"""Offline per-tutorial timing harness for the real tutorial_v1 lesson pipeline.

PYTHONPATH=. python scripts/simulate_tutorial_timing.py --scenario all --runs 3 --out timing.json

Drives the public entry point ``_generate_plan_item_details_parallel`` (which runs
``write_lesson`` for the first tutorial) with a saved one-lesson outline and a
fake ``client_factory``. Every provider call sleeps a fixed per-stage latency
(scaled by --time-scale) and returns canned, gate-passing responses built from
the test-suite fixtures. No provider, network or telemetry write is reached.

Stages are classified from the request's ``output_model`` and the calling
module (stack inspection by module/function name, never line numbers).
Results are reported in real seconds: time spent waiting on fake calls is
divided by the time scale; local compute between calls is kept unscaled.

Limits: fixed latencies measure pipeline structure and waiting only, not
provider variance, real rejection rates or content quality.
"""
import argparse
import asyncio
import copy
import json
import os
import re
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from statistics import median

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

# Real medians from the last live run (seconds). "assumed" stages were not measured.
LATENCIES = {
    "package_seed": 10.5,
    "activity_guided": 13.0,
    "activity_transfer": 18.8,
    "preflight_semantic": 11.6,
    "preflight_evidence": 12.5,
    "lesson_writer": 10.6,
    "repair": 5.9,
    "final_review": 15.0,
}
ASSUMED = {
    "final_review": "not measured in the live run; assumed 15.0 s",
    "*_repair": "package/activity/section/evidence repairs reuse the measured public-field repair median",
}
UNCLASSIFIED_SECONDS = 10.0
# Sequential critical path of a clean pass (activities and evidence owners run in parallel).
CLEAN_CRITICAL_PATH = ("package_seed", "activity_transfer", "preflight_semantic",
                       "preflight_evidence", "lesson_writer", "final_review")
SCENARIOS = ("clean", "preflight_reject")
DATUM_BY_OWNER_PREFIX = {"teaching.": "base", "practice.": "amount"}
REJECTED_FIELD = "practice.transfer.double"


def _caller_modules() -> list[str]:
    """App modules on the current task's stack, innermost first, skipping client wrappers."""
    names, frame = [], sys._getframe(1)
    while frame is not None:
        name = frame.f_globals.get("__name__", "")
        if name.startswith("app.") and frame.f_code.co_name != "generate_json" and (not names or names[-1] != name):
            names.append(name)
        frame = frame.f_back
    return names


def classify(request: dict, modules: list[str]) -> str:
    model = getattr(request.get("output_model"), "__name__", "")
    inner = modules[0] if modules else ""
    if model == "LessonPackageSeed":
        return "package_seed"
    if model in {"TutorialActivityDraft", "LessonActivityDraft"} and inner.endswith("package_builder"):
        try:
            kind = json.loads(request["user_prompt"])["activity_brief"]["kind"]
        except (ValueError, KeyError, TypeError):
            kind = "practice"
        return "activity_transfer" if kind == "transfer" else "activity_guided"
    if model == "PackageSemanticReview":
        return "preflight_semantic"
    if model == "ReviewEvidencePatch":
        return ("preflight_evidence" if any(m.endswith("package_preflight") for m in modules)
                else "review_evidence_repair")
    if model in {"PackagedLessonReview", "LessonReview"}:
        return "final_review"
    if inner.endswith("lesson_writer"):
        return "section_repair" if "Repair" in model else "lesson_writer"
    if model == "PrivatePackageRepair":
        return "package_repair"
    if model in {"TutorialActivityDraft", "LessonActivityDraft"}:
        return "activity_repair"
    if "Repair" in model:
        return "section_repair"
    return "unclassified:" + (model or "unknown")


def latency_for(stage: str) -> float:
    if stage in LATENCIES:
        return LATENCIES[stage]
    return LATENCIES["repair"] if stage.endswith("_repair") else UNCLASSIFIED_SECONDS


def assumed(stage: str) -> bool:
    return stage in ASSUMED or (stage.endswith("_repair") and stage != "repair")


def _fixtures():
    """Gate-passing canned content reused from the offline test fixtures."""
    from tests.section_client_fixture import activity_draft_fixture
    from tests.test_lesson_review_contract import _review
    from tests.test_short_tutorial_pipeline import outline, sections
    from tests.test_staged_package_builder import components

    seed, activities = components(numeric=True)
    for activity in activities.values():
        activity.update(minutes_min=1, minutes_max=2)  # Short tutorial phases.
        for field in activity["fields"]:
            field["rubric_criterion"] = "Doubles the supplied quantity"
        value = activity["data"][0]["value"]
        # An uncompiled numeric claim gives each activity owner one evidence request.
        activity["worked_solution"]["steps"][0]["explanation"] = (
            f"Doubling the input gives {value * 2} m because the case asks for twice the supplied quantity.")
    lesson = sections()
    lesson["worked_example"] = "The doubled result is [[result:example.double]]. " + lesson["worked_example"]
    return {"seed": seed, "activities": activities, "draft": activity_draft_fixture,
            "sections": lesson, "review": _review, "outline": outline(1)}


def _evidence(spans: dict, owners: dict) -> list[dict]:
    checks = []
    for claim_id, text in spans.items():
        # Lesson prose spans have no package owner; in this fixture they render the teaching result.
        owner = owners.get(claim_id, "teaching.example")
        datum = next(datum for prefix, datum in DATUM_BY_OWNER_PREFIX.items() if owner.startswith(prefix))
        checks.append({"claim_ids": [claim_id], "case_id": owner, "expression": f"{datum} * 2",
                       "claimed_result": float(re.findall(r"-?\d+(?:\.\d+)?", text)[-1])})
    return checks


class Recorder:
    def __init__(self, scenario: str, scale: float, fixtures: dict):
        self.scenario, self.scale, self.fixtures = scenario, scale, fixtures
        self.calls: list[dict] = []
        self.semantic_calls = 0
        self.diagnostics: list[dict] = []
        self.t0 = time.perf_counter()

    def factory(self, **options):
        recorder = self

        class FakeClient:
            model = "offline-timing"
            provider_name = "dummy"
            last_attempt = None

            async def generate_json(self, **request):
                stage = classify(request, _caller_modules())
                latency = latency_for(stage)
                entry = {"stage": stage, "model": getattr(request.get("output_model"), "__name__", None),
                         "latency_s": latency, "start": time.perf_counter() - recorder.t0}
                recorder.calls.append(entry)
                try:
                    await asyncio.sleep(latency * recorder.scale)
                except asyncio.CancelledError:
                    entry["cancelled"] = True  # A discarded speculative or sibling call.
                    raise
                finally:
                    entry["end"] = time.perf_counter() - recorder.t0
                return recorder.respond(stage, request)

        return FakeClient()

    def respond(self, stage: str, request: dict):
        from app.services.llm.client import LLMResponse
        f = self.fixtures
        body = request["user_prompt"]
        try:
            data = json.loads(body)
        except ValueError:
            data = {}
        if isinstance(data, dict) and isinstance(data.get("correction"), dict):
            # A canned response the real gate rejected; surface why in the output.
            self.diagnostics.append({"stage": stage, "validation_errors": data["correction"].get("validation_errors")})
        if stage == "package_seed":
            value = copy.deepcopy(f["seed"])
        elif stage.startswith("activity_"):
            value = f["draft"](f["activities"][data["activity_brief"]["id"]])
        elif stage == "preflight_semantic":
            self.semantic_calls += 1
            if self.scenario == "preflight_reject" and self.semantic_calls == 1:
                value = {"acceptable": False, "issues": [{"target": REJECTED_FIELD, "description":
                    "The transfer explanation must state why doubling applies to the new input."}]}
            else:
                value = {"acceptable": True, "issues": []}
        elif stage == "preflight_evidence":
            value = {"calculations": _evidence(data["numeric_spans"], data["numeric_span_owners"])}
        elif stage == "lesson_writer":
            value = copy.deepcopy(f["sections"])
        elif stage == "final_review":
            context = data.get("context") or {}
            checks = _evidence(data.get("numeric_spans") or {}, context.get("numeric_span_owners") or {})
            value = f["review"](practice_minutes=3, contains_calculations=bool(checks), calculations=checks)
        elif stage == "package_repair":
            activity_id, field_id = REJECTED_FIELD.split(".")[1:]
            value_in = f["activities"][activity_id]["data"][0]["value"]
            value = {"solution_step_patches": [{"activity_id": activity_id, "field_id": field_id,
                "explanation": f"The new input is independent, so doubling it gives {value_in * 2} m."}]}
        else:
            return LLMResponse(data={}, error=f"timing harness has no canned response for {stage}",
                               retryable=False, finish_reason="stop")
        return LLMResponse(data=value, finish_reason="stop", provider="dummy",
                           prompt_tokens=1, completion_tokens=1, total_tokens=2)


def _merged(intervals):
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged


def to_real(t: float, busy: list, scale: float) -> float:
    """Map a scaled wall offset to real seconds: busy waiting /scale, local work as is."""
    inside = sum(max(0.0, min(end, t) - start) for start, end in busy if start < t)
    return inside / scale + (t - inside)


@contextmanager
def _isolated_side_effects():
    """Telemetry would write to the database; providers must never be built. Restored on exit."""
    import app.services.llm.client as client_module
    from app.services.llm import telemetry

    async def no_record(*args, **kwargs):
        return True

    def no_provider(*args, **kwargs):
        raise RuntimeError("timing harness must not build a real LLM client")

    real = telemetry.record_llm_response
    patched = [(module, "record_llm_response", real) for module in list(sys.modules.values())
               if getattr(module, "__name__", "").startswith("app.")
               and getattr(module, "record_llm_response", None) is real]
    patched.append((client_module, "get_llm_client", client_module.get_llm_client))
    try:
        for module, name, _ in patched:
            setattr(module, name, no_provider if name == "get_llm_client" else no_record)
        yield
    finally:
        for module, name, original in patched:
            setattr(module, name, original)


async def run_once(scenario: str, scale: float) -> dict:
    import app.services.planning.package_builder  # noqa: F401  (load before isolating)
    import app.services.planning.package_preflight  # noqa: F401
    import app.services.planning.lesson_review  # noqa: F401
    import app.services.planning.lesson_writer  # noqa: F401
    from app.tasks.plans import _generate_plan_item_details_parallel
    fixtures = _fixtures()
    recorder = Recorder(scenario, scale, fixtures)
    checkpoints = []

    async def on_checkpoint(payload, stage):
        checkpoints.append((stage, time.perf_counter() - recorder.t0))

    with _isolated_side_effects():
        recorder.t0 = time.perf_counter()
        # A saved one-lesson outline skips outline generation; the first tutorial runs alone.
        _, _, error = await _generate_plan_item_details_parallel(
            system_prompt="Teach accurately", task_title="Double a quantity", mission_hours=0.1,
            user_goal="Reason with quantities", learning_preferences="examples", idol_name="Mentor",
            idol_domain="measurement", idol_evidence={}, session_context="", active_tier="balanced",
            routing_reason="timing_harness", client_factory=recorder.factory,
            prepared_packages={}, validation_records={}, on_checkpoint=on_checkpoint,
            existing_checkpoint={"_generation": {"outline": fixtures["outline"], "outline_contract_version": 3}})
        wall = time.perf_counter() - recorder.t0
    ready = next((at for stage, at in checkpoints if stage.endswith("_ready") and stage != "outline_ready"), None)
    busy = _merged([(call["start"], call["end"]) for call in recorder.calls])
    end = ready if ready is not None else wall
    timeline = [{"stage": call["stage"], "output_model": call["model"],
                 "latency_s": call["latency_s"], "assumed": assumed(call["stage"]),
                 "start_s": round(to_real(call["start"], busy, scale), 2),
                 "end_s": round(to_real(call["end"], busy, scale), 2),
                 **({"cancelled": True} if call.get("cancelled") else {})} for call in recorder.calls]
    # Walk back from the last call: each step's blocker is the latest call ending before it starts.
    finished = [c for c in timeline if not c.get("cancelled")]
    path, cursor = [], max(finished, key=lambda c: c["end_s"], default=None)
    while cursor is not None:
        path.append(cursor["stage"])
        cursor = max((c for c in finished if c["end_s"] <= cursor["start_s"] + 0.05),
                     key=lambda c: c["end_s"], default=None)
    total = to_real(end, busy, scale)
    busy_real = sum(e - s for s, e in busy if s < end) / scale
    return {"scenario": scenario, "time_scale": scale, "published": error is None and ready is not None,
            "error": error, "total_real_s": round(total, 2), "llm_wait_real_s": round(busy_real, 2),
            "local_compute_s": round(total - busy_real, 3), "call_count": len(recorder.calls),
            "unclassified": sorted({c["stage"] for c in recorder.calls if c["stage"].startswith("unclassified")}),
            "critical_path": path[::-1], "rejected_canned_responses": recorder.diagnostics,
            "timeline": timeline}


def _table(runs: list[dict]) -> str:
    lines = []
    for run in runs:
        lines.append(f"\n[{run['scenario']}] total {run['total_real_s']:.1f} s real "
                     f"(LLM wait {run['llm_wait_real_s']:.1f} s, local {run['local_compute_s']:.2f} s), "
                     f"{run['call_count']} calls, published={run['published']}"
                     + (f", error={run['error']}" if run["error"] else ""))
        lines.append("  critical path: " + " -> ".join(run["critical_path"]))
        lines.append(f"  {'stage':<22}{'start':>8}{'end':>8}{'dur':>7}  note")
        for call in run["timeline"]:
            note = "assumed" if call["assumed"] else ""
            lines.append(f"  {call['stage']:<22}{call['start_s']:>8.1f}{call['end_s']:>8.1f}"
                         f"{call['end_s'] - call['start_s']:>7.1f}  {note}")
    return "\n".join(lines)


def summarize(runs: list[dict]) -> dict:
    by = {}
    for run in runs:
        by.setdefault(run["scenario"], []).append(run["total_real_s"])
    return {scenario: {"runs": len(totals), "median_total_real_s": round(median(totals), 2),
                       "min_total_real_s": min(totals), "max_total_real_s": max(totals)}
            for scenario, totals in by.items()}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--scenario", choices=(*SCENARIOS, "all"), default="all")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--time-scale", type=float, default=0.1,
                        help="sleep seconds per real second (default 0.1)")
    parser.add_argument("--out", type=Path, help="write the full JSON result here")
    args = parser.parse_args(argv)
    if args.time_scale <= 0:
        parser.error("--time-scale must be positive")
    scenarios = SCENARIOS if args.scenario == "all" else (args.scenario,)
    runs = [asyncio.run(run_once(scenario, args.time_scale))
            for scenario in scenarios for _ in range(args.runs)]
    result = {"latencies_s": LATENCIES, "assumed": ASSUMED,
              "expected_clean_critical_path_s": round(sum(LATENCIES[s] for s in CLEAN_CRITICAL_PATH), 2),
              "summary": summarize(runs), "runs": runs}
    print(_table(runs))
    print("\nsummary:", json.dumps(result["summary"]))
    print("expected clean critical path (sum of sequential medians):", result["expected_clean_critical_path_s"], "s")
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2))
    return 0 if all(run["published"] and not run["unclassified"] for run in runs) else 1


if __name__ == "__main__":
    os.environ["LLM_PROVIDER"] = "dummy"  # Before app settings load; the fake factory replaces every client.
    sys.exit(main())
