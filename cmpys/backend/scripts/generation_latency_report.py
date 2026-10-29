"""Read-only generation latency report over usage telemetry and job tables.

PYTHONPATH=. python scripts/generation_latency_report.py --database-url <read-only url> [--since 2026-10-01]

Prints JSON: per-operation latency, hidden-reasoning time, tokens, cache share,
corrections and truncation, plus a per-learner plan -> first-tutorial path.
Opens the transaction READ ONLY and performs no writes or provider calls.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime, timezone
from statistics import mean

from app.services.llm.evaluation import percentile


def _is_correction(metadata: dict) -> bool:
    return metadata.get("correction") is True or metadata.get("attempt_role") not in (None, "initial")


def summarize_usage(rows: list[dict]) -> dict:
    """Aggregate llm_usage_events rows per operation."""
    groups = defaultdict(list)
    for row in rows:
        groups[row["operation"]].append(row)
    summary = {}
    for operation, items in sorted(groups.items()):
        metas = [row.get("metadata_json") or {} for row in items]
        durations = [row["duration_ms"] for row in items if row.get("duration_ms") is not None]
        reasoning = [m["first_content_ms"] - m["first_event_ms"] for m in metas
                     if m.get("first_content_ms") is not None and m.get("first_event_ms") is not None]
        prompt_total = sum(row.get("prompt_tokens") or 0 for row in items)
        completions = [row["completion_tokens"] for row in items if row.get("completion_tokens") is not None]
        thoughts = [m["thoughts_tokens"] for m in metas if m.get("thoughts_tokens") is not None]
        corrections = sum(_is_correction(m) for m in metas)
        summary[operation] = {
            "n": len(items),
            "success_rate": sum(bool(row.get("success")) for row in items) / len(items),
            "p50_ms": percentile(durations, .5), "p95_ms": percentile(durations, .95),
            "p50_reasoning_ms": percentile(reasoning, .5),
            "mean_completion_tokens": mean(completions) if completions else None,
            "mean_thoughts_tokens": mean(thoughts) if thoughts else None,
            "cached_prompt_share": (sum(m.get("cached_prompt_tokens") or 0 for m in metas) / prompt_total
                                    if prompt_total else None),
            "correction_calls": corrections,
            "first_pass_share": (len(items) - corrections) / len(items),
            "truncation_rate": sum(m.get("finish_reason") == "length" for m in metas) / len(items),
        }
    return summary


def critical_path(plan_jobs: list[dict], detail_jobs: list[dict]) -> list[dict]:
    """Per completed plan job: plan time and the first tutorial batch after it.

    Detail jobs record no per-step timestamps, so the first-tutorial figures
    are upper bounds (the batch may publish later tutorials after step_1).
    """
    paths = []
    for plan in sorted(plan_jobs, key=lambda job: job["created_at"]):
        if plan.get("status") != "completed":
            continue
        later = [job for job in detail_jobs if job["user_id"] == plan["user_id"]
                 and job["created_at"] >= plan["created_at"]
                 and "step_1" in ((job.get("result_json") or {}).get("ready_step_ids") or [])]
        first = min(later, key=lambda job: job["created_at"], default=None)
        path = {"user_id": plan["user_id"], "plan_created_at": plan["created_at"].isoformat(),
                "plan_ready_s": (plan["updated_at"] - plan["created_at"]).total_seconds()}
        if first is not None:
            path["first_tutorial_job_upper_bound_s"] = (first["updated_at"] - first["created_at"]).total_seconds()
            path["plan_ready_to_first_tutorial_upper_bound_s"] = (first["updated_at"] - plan["updated_at"]).total_seconds()
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-url", required=True, help="Prefer a read-only role")
    parser.add_argument("--since", default="2026-10-17", help="ISO date (UTC)")
    args = parser.parse_args()
    from sqlalchemy import create_engine, text

    since = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc)
    engine = create_engine(args.database_url.replace("+asyncpg", "+psycopg"))
    with engine.connect() as connection:
        connection.execute(text("SET TRANSACTION READ ONLY"))
        usage = [dict(row._mapping) for row in connection.execute(text(
            "SELECT operation, duration_ms, prompt_tokens, completion_tokens, success, metadata_json "
            "FROM llm_usage_events WHERE created_at >= :since"), {"since": since})]
        plans = [dict(row._mapping) for row in connection.execute(text(
            "SELECT user_id, status, created_at, updated_at FROM plan_generation_jobs WHERE created_at >= :since"),
            {"since": since})]
        details = [dict(row._mapping) for row in connection.execute(text(
            "SELECT user_id, status, created_at, updated_at, result_json FROM plan_item_detail_jobs "
            "WHERE created_at >= :since"), {"since": since})]
        connection.rollback()
    print(json.dumps({"since": since.isoformat(), "operations": summarize_usage(usage),
                      "critical_path": critical_path(plans, details)}, indent=2, default=str))


if __name__ == "__main__":
    main()
