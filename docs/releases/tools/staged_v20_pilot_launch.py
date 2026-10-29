"""Launch only the final three authorized synthetic tests, once.

Run on the deployment host after v20 deployment verification. This launcher
never resets the v19 ledger or reclaims a reserved test after an ambiguous
Docker outcome. Its only local mode, --self-test, uses mocked Docker calls.
Credentials are passed from the existing web container through stdin only.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from uuid import uuid4


REGISTRY = "297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend"
RELEASE_TAG = "20261016-153858-scoped-preflight"
IMAGE_DIGEST = "sha256:1eafe22d991943427ccb28eee78bff5ef09c455c22400145cf4ffaa55063613e"
FIRST_RELEASE_TAG = "20261016-150539-validation-boundaries"
FIRST_CONTAINER = "cmpys-staged-v19-batch-20261016"
CONTAINER = "cmpys-staged-v20-batch-20261016"
WEB_CONTAINER = "cmpys-web-1"
DOMAINS = ["accounting", "geometry", "writing"]
CAP = Decimal("3.0")
FIXTURE_SHA256 = "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
SCOPE = "synthetic accounting, geometry, writing across deployed revision and follow-up fixes"
RELEASE_ROOT = Path("/opt/cmpys/releases")
COMMAND = (
    "umask 077; exec python -m scripts.pilot_generation --max-usd 3.0 "
    "--domains accounting,geometry,writing --tiers balanced --full-pipeline "
    "--label corrected --output /pilot"
)


class LaunchBlocked(RuntimeError):
    """Static diagnostics only; never include Docker output or environment."""


def require(condition, message):
    if not condition:
        raise LaunchBlocked(message)


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise LaunchBlocked("Duplicate JSON key")
        value[key] = item
    return value


def parse_json(raw):
    try:
        return json.loads(raw, object_pairs_hook=unique_object,
                          parse_constant=lambda _: (_ for _ in ()).throw(LaunchBlocked("Nonfinite JSON value")))
    except (ValueError, TypeError, UnicodeError) as exc:
        raise LaunchBlocked("Invalid JSON document") from None


def regular_bytes(path):
    require(path.is_file() and not path.is_symlink(), "Required regular file is unavailable")
    return path.read_bytes()


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def money(value):
    require(type(value) in (int, float), "Invalid ledger amount")
    try:
        amount = Decimal(str(value))
    except InvalidOperation:
        raise LaunchBlocked("Invalid ledger amount") from None
    require(amount.is_finite() and amount >= 0, "Invalid ledger amount")
    return amount


def ledger_boundary(raw):
    """Retain known charges, unknown full reservations and unfinished calls."""
    rows = [parse_json(line) for line in raw.splitlines() if line.strip()]
    require(bool(rows), "The existing shared ledger must not be empty")
    pending, seen, finished = {}, [], set()
    spent = Decimal(0)
    for row in rows:
        require(type(row) is dict and type(row.get("id")) is str and row["id"], "Invalid ledger identity")
        request_id = row["id"]
        if row.get("status") == "reserved":
            require(request_id not in seen, "Repeated ledger reservation")
            amount = money(row.get("reserved_usd"))
            require(amount > 0, "Invalid ledger reservation")
            pending[request_id] = amount
            seen.append(request_id)
        elif row.get("status") == "finished":
            require(request_id in pending and request_id not in finished, "Unmatched ledger completion")
            charged = money(row.get("charged_usd"))
            require(type(row.get("usage_unknown")) is bool, "Missing ledger usage status")
            reserved = pending.pop(request_id)
            require(charged <= reserved, "A prior charge exceeded its reservation")
            require(not row["usage_unknown"] or charged == reserved, "Unknown usage lost its reservation")
            spent += charged
            finished.add(request_id)
        else:
            raise LaunchBlocked("Unknown ledger status")
    committed = spent + sum(pending.values(), Decimal(0))
    require(committed < CAP, "Shared pilot budget is exhausted")
    return {"prior_request_ids": seen, "prior_ledger_rows": len(rows),
            "prior_ledger_sha256": sha256(raw), "prior_accounted_usd": float(committed),
            "remaining_usd": float(CAP - committed)}


def atomic_json(path, data):
    """Fsync reservation before any potentially ambiguous launch operation."""
    temporary = path.with_name(path.name + "." + uuid4().hex + ".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write((json.dumps(data, sort_keys=True, indent=2) + "\n").encode())
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def docker(runner, *arguments, input_text=None, timeout=30):
    try:
        result = runner(["docker", *arguments], input=input_text, text=True,
                        capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise LaunchBlocked("Docker outcome is unknown; do not relaunch") from None
    except OSError:
        raise LaunchBlocked("Docker could not complete; do not relaunch") from None
    require(result.returncode == 0, "Docker command failed; do not relaunch")
    return result.stdout


def inspect_one(runner, *arguments):
    result = parse_json(docker(runner, *arguments))
    require(type(result) is list and len(result) == 1 and type(result[0]) is dict,
            "Unexpected Docker inspection result")
    return result[0]


def launch(*, root=RELEASE_ROOT, runner=subprocess.run, fixture_hash=FIXTURE_SHA256):
    require(re.fullmatch(r"[0-9]{8}-[0-9]{6}-[a-z-]+", RELEASE_TAG) is not None
            and re.fullmatch(r"sha256:[0-9a-f]{64}", IMAGE_DIGEST) is not None,
            "Release image is not pinned")
    first_release = root / FIRST_RELEASE_TAG
    output = first_release / "live-batch"
    require(output.is_dir() and not output.is_symlink(), "Existing shared output is unavailable")
    authorization_path = output / "authorization.json"
    ledger_path = output / "usage.jsonl"
    lock_fd = os.open(output / "authorization.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise LaunchBlocked("Another launcher holds the authorization lock") from None
        authorization = parse_json(regular_bytes(authorization_path))
        require(type(authorization) is dict and authorization.get("max_tests") == 6
                and type(authorization.get("tests_reserved")) is int
                and authorization["tests_reserved"] == 3
                and authorization.get("owner_approved") is True
                and money(authorization.get("shared_cap_usd")) == CAP
                and authorization.get("scope") == SCOPE
                and authorization.get("ledger") == str(ledger_path),
                "Remaining authorization does not match this exact shared batch")
        batches = authorization.get("batches")
        expected_first = {"container": FIRST_CONTAINER, "release": FIRST_RELEASE_TAG,
                          "label": "", "tests_reserved": 3, "domains": DOMAINS,
                          "status": "launched", "prior_request_ids": []}
        require(type(batches) is list and len(batches) == 1 and batches[0] == expected_first,
                "First-batch authorization differs or a second batch was already reserved")
        names = docker(runner, "ps", "-a", "--format", "{{.Names}}").splitlines()
        require(FIRST_CONTAINER in names and CONTAINER not in names, "Pilot container identity guard failed")
        active = docker(runner, "ps", "--format", "{{.Names}}").splitlines()
        require(not any(name.startswith("cmpys") and any(word in name for word in ("pilot", "acceptance", "batch"))
                        for name in active), "A synthetic pilot is already active")
        first = inspect_one(runner, "inspect", FIRST_CONTAINER)
        require(first.get("State", {}).get("Status") == "exited"
                and first["State"].get("Running") is False
                and not first["State"].get("Paused") and not first["State"].get("Restarting"),
                "The first batch has not stopped")
        for domain in DOMAINS:
            case_id = domain + "_novice_missing"
            report = parse_json(regular_bytes(output / (case_id + "-balanced.json")))
            require(type(report) is dict and report.get("scenario_id") == case_id
                    and report.get("tier") == "balanced" and report.get("full_pipeline") is True
                    and type(report.get("accepted")) is bool and type(report.get("failures")) is list,
                    "A complete first-batch report is missing")
            require(not (output / (case_id + "-corrected-balanced.json")).exists()
                    and not (output / (case_id + "-corrected-package.json")).exists(),
                    "A corrected artifact already exists")
        ledger_raw = regular_bytes(ledger_path)
        boundary = ledger_boundary(ledger_raw)
        fixture = first_release / "generation_scenarios.json"
        require(sha256(regular_bytes(fixture)) == fixture_hash, "Synthetic fixture hash differs")
        web = inspect_one(runner, "inspect", WEB_CONTAINER)
        image_ref = REGISTRY + "@" + IMAGE_DIGEST
        image = inspect_one(runner, "image", "inspect", image_ref)
        require(web.get("State", {}).get("Running") is True
                and web.get("Config", {}).get("Image") in (REGISTRY + ":" + RELEASE_TAG, image_ref)
                and web.get("Image") == image.get("Id")
                and image_ref in image.get("RepoDigests", []), "Production web is not the pinned v20 image")
        environment = web["Config"].get("Env")
        require(type(environment) is list and all(type(line) is str and "=" in line
                and not any(char in line for char in ("\n", "\r", "\x00")) for line in environment),
                "Web environment cannot be safely passed over stdin")
        require(regular_bytes(ledger_path) == ledger_raw, "Shared ledger changed during preflight")
        batch = {"container": CONTAINER, "release": RELEASE_TAG, "image_digest": IMAGE_DIGEST,
                 "label": "corrected", "tests_reserved": 3, "domains": DOMAINS,
                 "status": "reserved", "reserved_at": datetime.now(timezone.utc).isoformat(),
                 "fixture_sha256": fixture_hash, **boundary}
        reserved = copy.deepcopy(authorization)
        reserved["tests_reserved"] = 6
        reserved["batches"].append(batch)
        atomic_json(authorization_path, reserved)
        # No cleanup/reclaim on failure: the daemon may have launched the process.
        try:
            container_id = docker(runner, "run", "--detach", "--name", CONTAINER,
                "--restart", "no", "--env-file", "/dev/stdin", "--entrypoint", "sh",
                "-v", str(fixture) + ":/app/tests/fixtures/generation_scenarios.json:ro",
                "-v", str(output) + ":/pilot", image_ref, "-c", COMMAND,
                input_text="\n".join(environment) + "\n", timeout=60).strip()
            require(re.fullmatch(r"[0-9a-f]{64}", container_id) is not None,
                    "Launch acknowledgement is ambiguous; do not relaunch")
        except BaseException:
            batch["status"] = "launch_outcome_unknown"
            atomic_json(authorization_path, reserved)
            raise
        batch["status"] = "launched"
        batch["container_id"] = container_id
        atomic_json(authorization_path, reserved)
        return {"status": "launched", "release": RELEASE_TAG, "image_digest": IMAGE_DIGEST,
                "tests_reserved": 6, "new_tests": 3, "shared_cap_usd": float(CAP),
                "prior_request_count": len(boundary["prior_request_ids"]),
                "prior_accounted_usd": boundary["prior_accounted_usd"],
                "remaining_usd_before_launch": boundary["remaining_usd"]}
    finally:
        os.close(lock_fd)


class LauncherSafetyTests(unittest.TestCase):
    """All command execution is replaced; these tests cannot run Docker."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.release = self.root / FIRST_RELEASE_TAG
        self.output = self.release / "live-batch"
        self.output.mkdir(parents=True)
        fixture = json.dumps({"synthetic_fixture": True}).encode()
        (self.release / "generation_scenarios.json").write_bytes(fixture)
        self.fixture_hash = sha256(fixture)
        self.authorization = {"max_tests": 6, "shared_cap_usd": 3.0, "owner_approved": True,
            "scope": SCOPE, "ledger": str(self.output / "usage.jsonl"), "tests_reserved": 3,
            "batches": [{"container": FIRST_CONTAINER, "release": FIRST_RELEASE_TAG, "label": "",
                "tests_reserved": 3, "domains": DOMAINS, "status": "launched", "prior_request_ids": []}]}
        self.auth_path = self.output / "authorization.json"
        self.auth_path.write_text(json.dumps(self.authorization))
        self.rows = [
            {"id": "known", "status": "reserved", "reserved_usd": .4},
            {"id": "known", "status": "finished", "charged_usd": .2, "usage_unknown": False},
            {"id": "unknown", "status": "reserved", "reserved_usd": .3},
            {"id": "unknown", "status": "finished", "charged_usd": .3, "usage_unknown": True},
            {"id": "pending", "status": "reserved", "reserved_usd": .5}]
        self.ledger_path = self.output / "usage.jsonl"
        self.ledger_path.write_text("".join(json.dumps(row) + "\n" for row in self.rows))
        for domain in DOMAINS:
            (self.output / (domain + "_novice_missing-balanced.json")).write_text(json.dumps({
                "scenario_id": domain + "_novice_missing", "tier": "balanced",
                "full_pipeline": True, "accepted": False, "failures": ["Synthetic failure"]}))
        self.calls = []
        self.outcome = "success"
        self.active = []
        self.web_tag = RELEASE_TAG

    def runner(self, command, **kwargs):
        self.calls.append((command, kwargs))
        args = command[1:]
        if args[:2] == ["ps", "-a"]:
            output = FIRST_CONTAINER + "\n" + WEB_CONTAINER + "\n"
        elif args[:1] == ["ps"]:
            output = "\n".join(self.active + [WEB_CONTAINER])
        elif args == ["inspect", FIRST_CONTAINER]:
            output = json.dumps([{"State": {"Status": "exited", "Running": False}}])
        elif args == ["inspect", WEB_CONTAINER]:
            output = json.dumps([{"State": {"Running": True}, "Image": "sha256:local-image",
                "Config": {"Image": REGISTRY + ":" + self.web_tag,
                           "Env": ["LLM_PROVIDER=zai", "PRIVATE_TEST_SECRET=must-stay-in-stdin"]}}])
        elif args[:2] == ["image", "inspect"]:
            output = json.dumps([{"Id": "sha256:local-image", "RepoDigests": [REGISTRY + "@" + IMAGE_DIGEST]}])
        elif args[:1] == ["run"]:
            current = parse_json(self.auth_path.read_bytes())
            self.assertEqual(current["tests_reserved"], 6)
            self.assertEqual(current["batches"][-1]["status"], "reserved")
            self.assertEqual(current["batches"][-1]["prior_request_ids"], ["known", "unknown", "pending"])
            self.assertEqual(current["batches"][-1]["prior_accounted_usd"], 1.0)
            self.assertIn("--label corrected", command[-1])
            self.assertIn("--max-usd 3.0", command[-1])
            self.assertIn(REGISTRY + "@" + IMAGE_DIGEST, command)
            self.assertIn("must-stay-in-stdin", kwargs["input"])
            self.assertNotIn("must-stay-in-stdin", str(command))
            if self.outcome == "timeout":
                raise subprocess.TimeoutExpired(command, kwargs["timeout"])
            if self.outcome == "failure":
                return subprocess.CompletedProcess(command, 1, "PRIVATE OUTPUT", "PRIVATE ERROR")
            output = "ambiguous" if self.outcome == "bad_ack" else "a" * 64 + "\n"
        else:
            raise AssertionError("Unexpected mocked command")
        return subprocess.CompletedProcess(command, 0, output, "")

    def launch(self):
        return launch(root=self.root, runner=self.runner, fixture_hash=self.fixture_hash)

    def assert_no_run(self):
        self.assertFalse(any(command[1] == "run" for command, _ in self.calls))

    def test_success_reserves_first_preserves_shared_ledger_and_blocks_rerun(self):
        before = self.ledger_path.read_bytes()
        result = self.launch()
        self.assertEqual(result["new_tests"], 3)
        self.assertEqual(result["shared_cap_usd"], 3.0)
        self.assertEqual(result["remaining_usd_before_launch"], 2.0)
        self.assertEqual(self.ledger_path.read_bytes(), before)
        saved = parse_json(self.auth_path.read_bytes())
        self.assertEqual(saved["batches"][0], self.authorization["batches"][0])
        self.assertEqual(saved["batches"][-1]["status"], "launched")
        self.assertNotIn("must-stay-in-stdin", self.auth_path.read_text())
        self.calls.clear()
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()

    def test_ambiguous_outcomes_never_reclaim_or_relaunch(self):
        for outcome in ("timeout", "failure", "bad_ack"):
            with self.subTest(outcome=outcome):
                self.auth_path.write_text(json.dumps(self.authorization))
                self.calls.clear()
                self.outcome = outcome
                before = self.ledger_path.read_bytes()
                with self.assertRaises(LaunchBlocked):
                    self.launch()
                saved = parse_json(self.auth_path.read_bytes())
                self.assertEqual(saved["tests_reserved"], 6)
                self.assertEqual(saved["batches"][-1]["status"], "launch_outcome_unknown")
                self.assertEqual(self.ledger_path.read_bytes(), before)
                self.calls.clear()
                with self.assertRaises(LaunchBlocked):
                    self.launch()
                self.assert_no_run()

    def test_active_pilot_blocks_before_reservation(self):
        self.active = ["cmpys-other-acceptance"]
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()
        self.assertEqual(parse_json(self.auth_path.read_bytes())["tests_reserved"], 3)

    def test_old_production_image_blocks_before_reservation(self):
        self.web_tag = FIRST_RELEASE_TAG
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()
        self.assertEqual(parse_json(self.auth_path.read_bytes())["tests_reserved"], 3)

    def test_unknown_usage_cannot_be_discounted(self):
        self.rows[3]["charged_usd"] = .1
        self.ledger_path.write_text("".join(json.dumps(row) + "\n" for row in self.rows))
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()

    def test_fixture_mismatch_blocks(self):
        (self.release / "generation_scenarios.json").write_text("changed")
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()

    def test_existing_corrected_report_blocks(self):
        (self.output / "writing_novice_missing-corrected-balanced.json").write_text("{}")
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()

    def test_concurrent_launcher_lock_blocks(self):
        with (self.output / "authorization.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(LaunchBlocked):
                self.launch()
        self.assert_no_run()

    def test_exhausted_shared_cap_blocks(self):
        self.rows[-1]["reserved_usd"] = 2.5
        self.ledger_path.write_text("".join(json.dumps(row) + "\n" for row in self.rows))
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assert_no_run()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Use mocks only; no Docker or network")
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(LauncherSafetyTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        raise SystemExit(0 if result.wasSuccessful() else 1)
    try:
        print(json.dumps(launch(), sort_keys=True))
    except LaunchBlocked as exc:
        print(json.dumps({"status": "blocked", "reason": str(exc)}))
        raise SystemExit(1)
