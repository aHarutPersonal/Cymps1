"""Report reuse readiness from a local, approved catalog session export.

No database, model, network or write calls. Input is a JSON array with module_id,
skill, locale, level, published, source_verified, demand_count and sessions.
Each session uses CatalogSession's fields. This is a coverage/preparation report,
not permission to publish, bypass the matcher or enable the feature flag.
"""
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


def report(rows):
    from app.services.planning.catalog_lessons import CatalogSession, _reusable_session_fields
    from app.services.practice.contracts import Workbook
    totals, cohorts, prepare = Counter(), defaultdict(Counter), []
    for row in rows:
        state = "unverified"
        if row.get("published") is True and row.get("source_verified") is True:
            state = "native_prepared"
            if not row.get("sessions"):
                state = "missing_sessions"
            for raw in row.get("sessions", []):
                try:
                    session = CatalogSession(**raw)
                    if _reusable_session_fields(session) is None:
                        state = "legacy_normalization_required"
                        break
                    Workbook.model_validate(session.content.get("practice_workbook"))
                except (TypeError, ValueError):
                    state = "exercise_contract_required"
                    break
        totals[state] += 1
        cohort = ":".join(str(row.get(k) or "unknown") for k in ("skill", "locale", "level"))
        cohorts[cohort][state] += 1
        if state != "native_prepared":
            prepare.append({"module_id": row.get("module_id"), "reason": state,
                            "demand_count": max(0, int(row.get("demand_count") or 0))})
    return {"modules": len(rows), "readiness": dict(totals),
            "cohorts": {k: dict(v) for k, v in cohorts.items()},
            "preparation_queue": sorted(prepare, key=lambda r: -r["demand_count"]),
            "rollout_allowed": False,
            "next_gate": "Normalize legacy modules offline, run current source/practice/editorial gates, then measure verified cohort hit rate and latency"}


if __name__ == "__main__":
    import os
    # This command needs no provider credentials, including during Settings
    # initialization in imported application modules. Overrides are local to
    # this reporting process and do not modify runtime configuration files.
    os.environ["LLM_PROVIDER"] = "dummy"
    os.environ["BOOK_NARRATION_ENABLED"] = "false"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    args = parser.parse_args()
    print(json.dumps(report(json.loads(args.export.read_text())), indent=2))
