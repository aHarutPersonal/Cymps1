"""Read-only generation latency report: pure aggregation over telemetry and job rows."""
import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "generation_latency_report", Path(__file__).resolve().parents[1] / "scripts" / "generation_latency_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def _usage(operation="lesson_package_seed", **metadata):
    return {"operation": operation, "duration_ms": 3000, "prompt_tokens": 1000, "completion_tokens": 400,
            "success": True, "metadata_json": {"first_event_ms": 200, "first_content_ms": 1200, **metadata}}


def test_summarize_usage_reasoning_share():
    summary = report.summarize_usage([_usage(), _usage(cached_prompt_tokens=500, thoughts_tokens=300)])
    seed = summary["lesson_package_seed"]
    assert seed["n"] == 2 and seed["p50_ms"] == 3000
    assert seed["p50_reasoning_ms"] == 1000
    assert seed["cached_prompt_share"] == 0.25
    assert seed["mean_thoughts_tokens"] == 300


def test_summarize_usage_counts_corrections_and_truncation():
    rows = [_usage(), _usage(correction=True), _usage(attempt_role="repair", finish_reason="length")]
    seed = report.summarize_usage(rows)["lesson_package_seed"]
    assert seed["correction_calls"] == 2
    assert seed["first_pass_share"] == 1 / 3
    assert seed["truncation_rate"] == 1 / 3


def test_summarize_usage_tolerates_missing_timing():
    row = {"operation": "interview_stream", "duration_ms": None, "success": False, "metadata_json": None}
    interview = report.summarize_usage([row])["interview_stream"]
    assert interview["n"] == 1 and interview["p50_ms"] is None and interview["success_rate"] == 0


def test_critical_path_orders_stages():
    start = datetime(2026, 10, 26, tzinfo=timezone.utc)
    plans = [{"user_id": "u1", "status": "completed", "created_at": start, "updated_at": start + timedelta(seconds=90)}]
    details = [
        {"user_id": "u1", "status": "completed", "created_at": start + timedelta(seconds=95),
         "updated_at": start + timedelta(seconds=300), "result_json": {"ready_step_ids": ["step_1", "step_2"]}},
        {"user_id": "u1", "status": "queued", "created_at": start + timedelta(seconds=96),
         "updated_at": start + timedelta(seconds=96), "result_json": None},
    ]
    [path] = report.critical_path(plans, details)
    assert path["plan_ready_s"] == 90
    assert path["first_tutorial_job_upper_bound_s"] == 205
    assert path["plan_ready_to_first_tutorial_upper_bound_s"] == 210
