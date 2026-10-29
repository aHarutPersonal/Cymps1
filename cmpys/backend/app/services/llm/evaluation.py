"""Release comparison for synthetic generation runs, including failed attempts.

Input rows are independent runs with a blind, adjudicated quality verdict.
Unknown costs/timings are never silently treated as zero. Small sets do not
claim production tail-latency confidence.
"""
import math
import re
from collections import defaultdict
from statistics import mean

_WORD = re.compile(r"[\w']+", re.UNICODE)
_SENTENCE = re.compile(r"(?<=[.!?])\s+")


def _words(text: str) -> list[str]:
    return [word.casefold() for word in _WORD.findall(text or "")]


def _ngrams(words: list[str], n: int) -> set[tuple[str, ...]]:
    return {tuple(words[i:i + n]) for i in range(len(words) - n + 1)}


def qualitative_leak_spans(public_text: str, private_answer: str, *, min_words: int = 8) -> list[str]:
    """Word spans of a private transfer answer that also appear in public text.

    Screening for adjudication: a shared span of ``min_words`` words means the
    learner could read the answer before the independent attempt.
    """
    public = _ngrams(_words(public_text), min_words)
    private = _words(private_answer)
    return sorted({" ".join(private[i:i + min_words]) for i in range(len(private) - min_words + 1)
                   if tuple(private[i:i + min_words]) in public})


def unsupported_mentor_sentences(text: str, mentor_names: list[str], evidence_texts: list[str],
                                 *, min_shared_words: int = 4) -> list[str]:
    """Sentences naming a mentor that share no word span with any supplied evidence.

    Screening for adjudication, not a production gate: it flags candidate
    invented anecdotes for a human or model reviewer to confirm.
    """
    names = {part.casefold() for name in mentor_names for part in name.split() if len(part) >= 3}
    evidence = set().union(*(_ngrams(_words(item), min_shared_words) for item in evidence_texts)) if evidence_texts else set()
    flagged = []
    for sentence in _SENTENCE.split(text or ""):
        words = _words(sentence)
        if names.intersection(words) and not _ngrams(words, min_shared_words) & evidence:
            flagged.append(sentence.strip())
    return flagged


def percentile(values, fraction):
    values = sorted(values)
    if not values:
        return None
    return values[max(0, math.ceil(fraction * len(values)) - 1)]


def _stage_latency(rows: list[dict]) -> dict:
    """p50/p95 per pipeline stage from rows carrying ``stage_ms``."""
    by_stage = defaultdict(list)
    for row in rows:
        for stage, value in (row.get("stage_ms") or {}).items():
            if isinstance(value, (int, float)) and math.isfinite(value) and value >= 0:
                by_stage[stage].append(value)
    return {stage: {"p50": percentile(values, .5), "p95": percentile(values, .95), "observed": len(values)}
            for stage, values in sorted(by_stage.items())}


def summarize_runs(rows: list[dict], scenarios: list[dict]) -> dict:
    expected = {case["id"] for case in scenarios}
    if len(expected) != len(scenarios):
        raise ValueError("Evaluation scenario IDs must be unique")
    cases = {case["id"]: case for case in scenarios}
    observed = {row["scenario_id"] for row in rows}
    by_scenario = defaultdict(list)
    cohorts = defaultdict(list)
    identities = set()
    for row in rows:
        if row["scenario_id"] not in expected:
            raise ValueError("Unknown evaluation scenario")
        for field in ("quality_score", "usable_ms", "cost_usd", "repair_count"):
            value = row.get(field)
            if value is not None and (not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0):
                raise ValueError(f"Invalid evaluation {field}")
        if row.get("quality_score", 0) is not None and row.get("quality_score", 0) > 1:
            raise ValueError("Quality score must use the 0-1 scale")
        if row.get("run_id") is not None:
            identity = (row["scenario_id"], row["run_id"])
            if identity in identities:
                raise ValueError("Duplicate evaluation run")
            identities.add(identity)
        by_scenario[row["scenario_id"]].append(row)
        for field in ("domain", "learner_level", "evidence_status", "locale", "split"):
            if field in cases[row["scenario_id"]]:
                cohorts[f"{field}:{cases[row['scenario_id']][field]}"].append(row)
    durations = [r["usable_ms"] for r in rows if r.get("usable_ms") is not None]
    accepted = [r for r in rows if r.get("accepted") is True]
    quality = [r["quality_score"] for r in accepted if r.get("quality_score") is not None]
    known_cost = all(r.get("cost_usd") is not None for r in rows)
    critical = sum(bool(r.get("critical_defects")) for r in rows)
    coverage = expected == observed and all(len(by_scenario[c]) >= 3 for c in expected)
    adjudicated = bool(rows) and all(r.get("adjudicated") is True for r in rows)
    return {
        "runs": len(rows), "accepted": len(accepted), "missing_scenarios": sorted(expected - observed),
        "critical_defect_runs": critical, "complete_three_repeat_coverage": coverage,
        "adjudicated": adjudicated,
        "first_pass_acceptance": mean(bool(r.get("accepted")) and r.get("repair_count", 0) == 0 for r in rows) if rows else None,
        "eventual_acceptance": len(accepted) / len(rows) if rows else None,
        "all_runs_consistency": mean(all(r.get("accepted") for r in group) for group in by_scenario.values()) if rows else None,
        "mean_quality": mean(quality) if quality else None,
        "cohort_quality": {key: mean(r["quality_score"] for r in group)
                           if all(r.get("quality_score") is not None for r in group) else None
                           for key, group in cohorts.items()},
        "quality_scores_complete": len(quality) == len(rows),
        "repair_rate": mean(r.get("repair_count", 0) > 0 for r in rows) if rows else None,
        "missing_exercise_runs": sum(bool(r.get("missing_exercises")) for r in rows),
        "answer_leak_runs": sum(bool(r.get("answer_leaks")) for r in rows),
        "unsupported_mentor_claim_runs": sum(bool(r.get("unsupported_mentor_claims")) for r in rows),
        "stage_latency_ms": _stage_latency(rows),
        "reference_defect_runs": sum(bool(r.get("reference_defects")) for r in rows),
        "latency_ms": {"p50": percentile(durations, .5), "p95": percentile(durations, .95),
                       "p99": percentile(durations, .99), "observed": len(durations),
                       "unknown": len(rows) - len(durations)},
        "cost_per_accepted": sum(r["cost_usd"] for r in rows) / len(accepted) if rows and known_cost and accepted else None,
        "eligible_for_comparison": coverage and adjudicated and not critical and len(accepted) == len(rows) and len(quality) == len(rows),
        "tail_confidence": "screening only; use larger production traces for tail estimates",
    }


def promotion_decision(candidate, baseline):
    if not candidate["eligible_for_comparison"] or not baseline["eligible_for_comparison"]:
        return {"promote": False, "reason": "Incomplete coverage, unadjudicated runs or failed quality gates"}
    if candidate["mean_quality"] is None or baseline["mean_quality"] is None or candidate["mean_quality"] < baseline["mean_quality"]:
        return {"promote": False, "reason": "Quality has not matched the baseline"}
    for cohort, score in baseline["cohort_quality"].items():
        measured = candidate["cohort_quality"].get(cohort)
        if score is None or measured is None or measured < score:
            return {"promote": False, "reason": f"Quality regression or missing evidence in {cohort}"}
    for key in ("missing_exercise_runs", "reference_defect_runs", "answer_leak_runs", "unsupported_mentor_claim_runs"):
        if candidate[key]:
            return {"promote": False, "reason": key}
    c, b = candidate["latency_ms"], baseline["latency_ms"]
    if c["unknown"] or b["unknown"] or c["p95"] >= b["p95"]:
        return {"promote": False, "reason": "Accepted-artifact tail latency has not improved"}
    return {"promote": True, "reason": "Release-set quality maintained and measured p95 improved; staged rollout required"}
