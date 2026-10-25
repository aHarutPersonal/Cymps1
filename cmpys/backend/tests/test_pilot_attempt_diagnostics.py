import json
import time
from types import SimpleNamespace

from scripts.pilot_generation import Budget, _attempt_diagnostics, _request_diagnostics


def test_concurrent_scope_attribution_excludes_private_content_and_generated_owner_names():
    body = {"numeric_spans": {"n3": "PRIVATE SOURCE"},
            "numeric_span_owners": {"n3": "practice.secret_owner"},
            "package": {"workbook": {"activities": [{"id": "first"}, {"id": "secret_owner"}]}}}
    details = _request_diagnostics(json.dumps(body), "ReviewEvidencePatch")
    assert details["request_owner_positions"] == [1]
    assert details["request_claim_ids"] == ["n3"]
    assert len(details["request_sha256"]) == 64
    assert "PRIVATE" not in json.dumps(details) and "secret_owner" not in json.dumps(details)
    body["numeric_span_owners"]["n3"] = "practice.unknown"
    assert set(_request_diagnostics(json.dumps(body), "ReviewEvidencePatch")) == {"request_sha256"}


def test_scope_attribution_does_not_guess_missing_or_malformed_context():
    for value in ("[]", "null", "{}", "invalid json"):
        assert set(_request_diagnostics(value, "ReviewEvidencePatch")) == {"request_sha256"}


def test_cancelled_attempt_retains_safe_timing_and_full_reservation(tmp_path):
    attempt = SimpleNamespace(duration_ms=120001, first_content_ms=2500,
        prompt_tokens=None, completion_tokens=None, total_tokens=None, thoughts_tokens=7,
        error="cancelled", effective_parameters={"max_tokens": 8548},
        raw_response="PRIVATE DRAFT MUST NOT BE COPIED", data={"private": "draft"})
    details = _attempt_diagnostics(None, SimpleNamespace(last_attempt=attempt), None,
        time.perf_counter(), "LessonPackage")
    budget = Budget(tmp_path / "usage.jsonl", 3)
    request_id = budget.reserve(0.1, {})
    budget.finish(request_id, None, details)
    row = json.loads((tmp_path / "usage.jsonl").read_text().splitlines()[-1])
    assert row["duration_ms"] == 120001
    assert row["first_content_ms"] == 2500
    assert row["schema"] == "LessonPackage"
    assert row["response_received"] is False
    assert row["usage_unknown"] is True
    assert row["charged_usd"] == 0.1
    assert row["thoughts_tokens"] == 7
    assert "PRIVATE" not in json.dumps(row)
    assert "data" not in row and "raw_response" not in row


def test_stale_previous_attempt_is_not_attributed_to_new_cancellation():
    previous = SimpleNamespace(duration_ms=99, first_content_ms=10,
        prompt_tokens=20, completion_tokens=30, total_tokens=50)
    details = _attempt_diagnostics(None, SimpleNamespace(last_attempt=previous), previous,
        time.perf_counter(), "LessonPackage")
    assert details["response_received"] is False
    assert "prompt_tokens" not in details
    assert "first_content_ms" not in details
    assert 0 <= details["duration_ms"] < 99


def test_returned_response_takes_precedence_over_client_state():
    response = SimpleNamespace(duration_ms=50, first_content_ms=5,
        prompt_tokens=10, completion_tokens=20, total_tokens=30,
        error=None, effective_parameters={})
    details = _attempt_diagnostics(response, SimpleNamespace(last_attempt=None), None,
        time.perf_counter(), "LessonPackage")
    assert details["response_received"] is True
    assert details["total_tokens"] == 30
    assert details["duration_ms"] == 50
