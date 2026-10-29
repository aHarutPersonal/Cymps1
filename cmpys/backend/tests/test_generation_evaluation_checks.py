"""Release eval screens for transfer-answer leaks, unsupported mentor claims and stage latency."""
from app.services.llm.evaluation import (
    promotion_decision, qualitative_leak_spans, summarize_runs, unsupported_mentor_sentences,
)

CASES = [{"id": "writing", "domain": "writing"}]


def _rows(**extra):
    return [{"scenario_id": "writing", "run_id": i, "accepted": True, "adjudicated": True,
             "quality_score": .9, "usable_ms": 1000, "cost_usd": .05, **extra} for i in range(3)]


def test_leak_detects_copied_model_answer():
    answer = "The clearest closing asks members to reply by Friday to claim a Saturday morning shift."
    public = "Example: the clearest closing asks members to reply by Friday to claim a Saturday morning shift."
    assert qualitative_leak_spans(public, answer)


def test_leak_ignores_short_common_phrases():
    answer = "Name the action the reader should take and give a clear time for it."
    public = "Name the action. Give a clear time. Explain why the reader should care."
    assert qualitative_leak_spans(public, answer) == []


def test_leak_is_case_and_punctuation_insensitive():
    answer = "Booked hours divided by available hours, scaled to a percentage, exceeds the threshold."
    public = "booked hours DIVIDED by available hours; scaled to a percentage — exceeds the threshold!"
    assert qualitative_leak_spans(public, answer)


def test_mentor_sentence_without_evidence_flagged():
    text = "Dickens rewrote every chapter nine times before breakfast. Good dialogue reveals motive."
    flagged = unsupported_mentor_sentences(text, ["Charles Dickens"], ["Dickens published novels in monthly parts."])
    assert flagged == ["Dickens rewrote every chapter nine times before breakfast."]


def test_mentor_sentence_with_evidence_passes():
    text = "Dickens published his novels in monthly parts, which shaped his cliffhangers."
    assert unsupported_mentor_sentences(text, ["Charles Dickens"], ["Dickens published his novels in monthly parts."]) == []


def test_mentor_check_ignores_text_without_the_mentor():
    assert unsupported_mentor_sentences("A clear request names one action.", ["Charles Dickens"], []) == []


def test_promotion_rejects_answer_leak_runs():
    baseline = summarize_runs(_rows(usable_ms=2000), CASES)
    candidate = summarize_runs(_rows(), CASES)
    assert promotion_decision(candidate, baseline)["promote"]
    leaked = summarize_runs(_rows(answer_leaks=["copied span"]), CASES)
    assert leaked["answer_leak_runs"] == 3
    assert promotion_decision(leaked, baseline) == {"promote": False, "reason": "answer_leak_runs"}


def test_promotion_rejects_unsupported_mentor_claim_runs():
    baseline = summarize_runs(_rows(usable_ms=2000), CASES)
    claimed = summarize_runs(_rows(unsupported_mentor_claims=["invented anecdote"]), CASES)
    assert promotion_decision(claimed, baseline)["reason"] == "unsupported_mentor_claim_runs"


def test_stage_latency_is_summarized_per_stage():
    rows = [{**row, "stage_ms": {"seed": 1000 * (i + 1), "review": 500}} for i, row in enumerate(_rows())]
    summary = summarize_runs(rows, CASES)
    assert summary["stage_latency_ms"]["seed"] == {"p50": 2000, "p95": 3000, "observed": 3}
    assert summary["stage_latency_ms"]["review"]["p50"] == 500
