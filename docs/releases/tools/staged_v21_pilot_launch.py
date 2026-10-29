"""Launch only the first three of six newly authorized synthetic tests, once.

Run on the deployment host after v21 deployment verification. This launcher
uses a new ledger and never reclaims a reserved test after an ambiguous
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
RELEASE_TAG = "20261017-001200-structured-solutions"
IMAGE_DIGEST = "sha256:97e972c16a39963bc544ee3860ebc6ce51605dba20192df5cfae95ae55a86d73"
PRIOR_RELEASE_TAG = "20261016-150539-validation-boundaries"
PRIOR_CONTAINER = "cmpys-staged-v19-batch-20261016"
PRIOR_FOLLOWUP_TAG = "20261016-153858-scoped-preflight"
PRIOR_FOLLOWUP_CONTAINER = "cmpys-staged-v20-batch-20261016"
CONTAINER = "cmpys-staged-v21-batch-20261017"
WEB_CONTAINER = "cmpys-web-1"
DOMAINS = ["accounting", "geometry", "writing"]
CAP = Decimal("1.97")
PRIOR_ACCOUNTED = Decimal("1.0208688")
COMBINED_LIMIT = Decimal("3.0")
ACCOUNTING_TOLERANCE = Decimal("0.000000001")
FIXTURE_SHA256 = "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
PRIOR_SCOPE = "synthetic accounting, geometry, writing across deployed revision and follow-up fixes"
SCOPE = "synthetic accounting, geometry, writing across v21 and follow-up fixes"
RELEASE_ROOT = Path("/opt/cmpys/releases")
COMMAND = (
    "umask 077; exec python -m scripts.pilot_generation --max-usd 1.97 "
    "--domains accounting,geometry,writing --tiers balanced --full-pipeline "
    "--output /pilot"
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


def completed_prior_ledger(raw):
    """Require complete known old usage; never discount or transfer it."""
    rows = [parse_json(line) for line in raw.splitlines() if line.strip()]
    require(bool(rows), "Prior ledger is empty")
    pending, seen, finished = {}, set(), set()
    spent = Decimal(0)
    for row in rows:
        require(type(row) is dict and type(row.get("id")) is str and row["id"], "Invalid ledger identity")
        ident = row["id"]
        if row.get("status") == "reserved":
            require(ident not in seen, "Repeated ledger reservation")
            value = money(row.get("reserved_usd"))
            require(value > 0, "Invalid ledger reservation")
            pending[ident] = value
            seen.add(ident)
        elif row.get("status") == "finished":
            require(ident in pending and ident not in finished, "Unmatched ledger completion")
            require(row.get("usage_unknown") is False, "Prior unknown usage is not settled")
            value = money(row.get("charged_usd"))
            require(value <= pending.pop(ident), "Prior charge exceeded its reservation")
            spent += value
            finished.add(ident)
        else:
            raise LaunchBlocked("Unknown ledger status")
    require(not pending and seen == finished, "Prior requests remain pending")
    require(abs(spent - PRIOR_ACCOUNTED) <= ACCOUNTING_TOLERANCE, "Prior cost differs from approved baseline")
    require(spent + CAP <= COMBINED_LIMIT, "Combined prior cost and new cap exceed approved bound")
    return {"prior_completed_request_count": len(finished), "prior_ledger_sha256": sha256(raw),
            "prior_accounted_usd": float(spent), "combined_max_usd": float(spent + CAP)}


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
    prior_release = root / PRIOR_RELEASE_TAG
    prior_output = prior_release / "live-batch"
    output = root / RELEASE_TAG / "live-batch"
    require(all(path.is_dir() and not path.is_symlink() for path in
                (prior_release, prior_output, root / RELEASE_TAG, output)),
            "Required release directories are unavailable")
    authorization_path = output / "authorization.json"
    ledger_path = output / "usage.jsonl"
    lock_fd = os.open(output / "authorization.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise LaunchBlocked("Another launcher holds the authorization lock") from None
        authorization_raw = regular_bytes(authorization_path)
        authorization = parse_json(authorization_raw)
        require(type(authorization) is dict and authorization.get("max_tests") == 6
                and type(authorization.get("tests_reserved")) is int
                and authorization["tests_reserved"] == 0
                and authorization.get("owner_approved") is True
                and money(authorization.get("shared_cap_usd")) == CAP
                and authorization.get("scope") == SCOPE
                and authorization.get("ledger") == str(ledger_path)
                and authorization.get("batches") == [],
                "New authorization does not match this exact first batch")
        require(regular_bytes(ledger_path) == b"", "New ledger is not empty; do not reset it")
        require({path.name for path in output.iterdir()} <= {"authorization.json", "authorization.lock", "usage.jsonl"},
                "New output already contains an artifact; do not relaunch")

        prior_files = {}

        def read_prior(path):
            raw = regular_bytes(path)
            prior_files[path] = raw
            return raw

        old_auth_path = prior_output / "authorization.json"
        old_authorization = parse_json(read_prior(old_auth_path))
        require(type(old_authorization) is dict and old_authorization.get("max_tests") == 6
                and old_authorization.get("tests_reserved") == 6
                and old_authorization.get("owner_approved") is True
                and money(old_authorization.get("shared_cap_usd")) == COMBINED_LIMIT
                and old_authorization.get("scope") == PRIOR_SCOPE
                and old_authorization.get("ledger") == str(prior_output / "usage.jsonl"),
                "Prior authorization is not the completed six-test scope")
        old_batches = old_authorization.get("batches")
        require(type(old_batches) is list and len(old_batches) == 2,
                "Prior authorization has unexpected batches")
        for batch, tag, name, label in zip(old_batches,
                (PRIOR_RELEASE_TAG, PRIOR_FOLLOWUP_TAG), (PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER), ("", "corrected")):
            require(type(batch) is dict and batch.get("release") == tag and batch.get("container") == name
                    and batch.get("label") == label and batch.get("tests_reserved") == 3
                    and batch.get("domains") == DOMAINS and batch.get("status") == "launched",
                    "A prior three-test batch does not match the completed authorization")
        old_boundary = completed_prior_ledger(read_prior(prior_output / "usage.jsonl"))
        old_boundary["prior_authorization_sha256"] = sha256(prior_files[old_auth_path])
        for domain in DOMAINS:
            case_id = domain + "_novice_missing"
            for label in ("", "-corrected"):
                report = parse_json(read_prior(prior_output / (case_id + label + "-balanced.json")))
                require(type(report) is dict and report.get("scenario_id") == case_id
                        and report.get("tier") == "balanced" and report.get("full_pipeline") is True
                        and type(report.get("accepted")) is bool and type(report.get("failures")) is list,
                        "A completed prior test report is missing")

        names = docker(runner, "ps", "-a", "--format", "{{.Names}}").splitlines()
        require(PRIOR_CONTAINER in names and PRIOR_FOLLOWUP_CONTAINER in names and CONTAINER not in names,
                "Pilot container identity guard failed")
        active = docker(runner, "ps", "--format", "{{.Names}}").splitlines()
        require(not any(name.startswith("cmpys") and any(word in name for word in ("pilot", "acceptance", "batch"))
                        for name in active), "A synthetic pilot is already active")
        for prior_name in (PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER):
            prior_container = inspect_one(runner, "inspect", prior_name)
            state = prior_container.get("State", {})
            require(state.get("Status") == "exited" and state.get("Running") is False
                    and not state.get("Paused") and not state.get("Restarting"), "A prior batch has not stopped")
        fixture = prior_release / "generation_scenarios.json"
        require(sha256(regular_bytes(fixture)) == fixture_hash, "Synthetic fixture hash differs")
        web = inspect_one(runner, "inspect", WEB_CONTAINER)
        image_ref = REGISTRY + "@" + IMAGE_DIGEST
        image = inspect_one(runner, "image", "inspect", image_ref)
        require(web.get("State", {}).get("Running") is True
                and not web["State"].get("Paused") and not web["State"].get("Restarting")
                and web.get("Config", {}).get("Image") in (REGISTRY + ":" + RELEASE_TAG, image_ref)
                and type(image.get("Id")) is str and image["Id"]
                and web.get("Image") == image["Id"] and image.get("Architecture") == "arm64"
                and image_ref in image.get("RepoDigests", []), "Production web is not the pinned v21 image")
        environment = web["Config"].get("Env")
        require(type(environment) is list and bool(environment)
                and all(type(line) is str and "=" in line and line.split("=", 1)[0]
                        and not any(char in line for char in ("\n", "\r", "\x00")) for line in environment),
                "Web environment cannot be safely passed over stdin")
        require(len({line.split("=", 1)[0] for line in environment}) == len(environment),
                "Web environment has duplicate keys")
        require(all(regular_bytes(path) == raw for path, raw in prior_files.items()),
                "Prior completed evidence changed during preflight")
        require(sha256(regular_bytes(fixture)) == fixture_hash
                and regular_bytes(authorization_path) == authorization_raw and regular_bytes(ledger_path) == b"",
                "New authorization, ledger or fixture changed during preflight")
        batch = {"container": CONTAINER, "release": RELEASE_TAG, "image_digest": IMAGE_DIGEST,
                 "label": "", "tests_reserved": 3, "domains": DOMAINS,
                 "status": "reserved", "reserved_at": datetime.now(timezone.utc).isoformat(),
                 "fixture_sha256": fixture_hash, "prior_request_ids": [], "prior_accounted_usd": 0.0,
                 "remaining_usd": float(CAP), "completed_previous_authorization": old_boundary}
        reserved = copy.deepcopy(authorization)
        reserved["tests_reserved"] = 3
        reserved["batches"].append(batch)
        atomic_json(authorization_path, reserved)
        # An unknown daemon outcome consumes the reservation; never retry here.
        try:
            container_id = docker(runner, "run", "--detach", "--pull", "never", "--name", CONTAINER,
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
                "tests_reserved": 3, "new_tests": 3, "max_tests": 6, "shared_cap_usd": float(CAP),
                "prior_request_count": 0, "prior_accounted_usd": 0.0,
                "previous_authorization_reported_usd": old_boundary["prior_accounted_usd"],
                "combined_max_usd": old_boundary["combined_max_usd"], "remaining_usd_before_launch": float(CAP)}
    finally:
        os.close(lock_fd)


class LauncherSafetyTests(unittest.TestCase):
    """All subprocesses are mocked; temporary files are cleaned in-process."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.prior_release = self.root / PRIOR_RELEASE_TAG
        self.prior_output = self.prior_release / "live-batch"
        self.output = self.root / RELEASE_TAG / "live-batch"
        self.prior_output.mkdir(parents=True)
        self.output.mkdir(parents=True)
        fixture = b'{"synthetic_fixture":true}'
        self.fixture = self.prior_release / "generation_scenarios.json"
        self.fixture.write_bytes(fixture)
        self.fixture_hash = sha256(fixture)
        self.authorization = {"max_tests": 6, "shared_cap_usd": 1.97, "owner_approved": True,
            "scope": SCOPE, "ledger": str(self.output / "usage.jsonl"), "tests_reserved": 0, "batches": []}
        self.auth_path = self.output / "authorization.json"
        self.auth_path.write_text(json.dumps(self.authorization))
        self.ledger_path = self.output / "usage.jsonl"
        self.ledger_path.write_bytes(b"")
        self.old_auth_path = self.prior_output / "authorization.json"
        self.old_authorization = {"max_tests": 6, "shared_cap_usd": 3.0, "owner_approved": True,
            "scope": PRIOR_SCOPE, "ledger": str(self.prior_output / "usage.jsonl"), "tests_reserved": 6,
            "batches": [{"release": tag, "container": name, "label": label, "tests_reserved": 3,
                         "domains": DOMAINS, "status": "launched"}
                        for tag, name, label in zip((PRIOR_RELEASE_TAG, PRIOR_FOLLOWUP_TAG),
                            (PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER), ("", "corrected"))]}
        self.old_auth_path.write_text(json.dumps(self.old_authorization))
        self.old_ledger = self.prior_output / "usage.jsonl"
        self.old_rows = [{"id": "settled", "status": "reserved", "reserved_usd": 1.1},
                         {"id": "settled", "status": "finished", "charged_usd": 1.0208688,
                          "usage_unknown": False}]
        self.write_old_ledger()
        for domain in DOMAINS:
            for label in ("", "-corrected"):
                (self.prior_output / (domain + "_novice_missing" + label + "-balanced.json")).write_text(json.dumps({
                    "scenario_id": domain + "_novice_missing", "tier": "balanced",
                    "full_pipeline": True, "accepted": False, "failures": ["Synthetic failure"]}))
        self.calls = []
        self.outcome = "success"
        self.active = []
        self.web_tag = RELEASE_TAG
        self.environment = ["LLM_PROVIDER=zai", "PRIVATE_TEST_SECRET=must-stay-in-stdin"]
        self.architecture = "arm64"
        self.before_run = None
        self.existing_new_container = False

    def write_old_ledger(self):
        self.old_ledger.write_text("".join(json.dumps(row) + "\n" for row in self.old_rows))

    def runner(self, command, **kwargs):
        self.calls.append((command, kwargs))
        args = command[1:]
        if args[:2] == ["ps", "-a"]:
            output = "\n".join([PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER, WEB_CONTAINER]
                               + ([CONTAINER] if self.existing_new_container else []))
        elif args[:1] == ["ps"]:
            output = "\n".join(self.active + [WEB_CONTAINER])
        elif args in (["inspect", PRIOR_CONTAINER], ["inspect", PRIOR_FOLLOWUP_CONTAINER]):
            output = json.dumps([{"State": {"Status": "exited", "Running": False}}])
        elif args == ["inspect", WEB_CONTAINER]:
            output = json.dumps([{"State": {"Running": True}, "Image": "sha256:local-image",
                "Config": {"Image": REGISTRY + ":" + self.web_tag, "Env": self.environment}}])
        elif args[:2] == ["image", "inspect"]:
            if self.before_run:
                self.before_run()
            output = json.dumps([{"Id": "sha256:local-image", "Architecture": self.architecture,
                                  "RepoDigests": [REGISTRY + "@" + IMAGE_DIGEST]}])
        elif args[:1] == ["run"]:
            saved = parse_json(self.auth_path.read_bytes())
            self.assertEqual(saved["tests_reserved"], 3)
            self.assertEqual(len(saved["batches"]), 1)
            batch = saved["batches"][0]
            self.assertEqual(batch["status"], "reserved")
            self.assertEqual(batch["prior_request_ids"], [])
            self.assertEqual(batch["prior_accounted_usd"], 0)
            self.assertEqual(batch["completed_previous_authorization"]["prior_accounted_usd"], 1.0208688)
            self.assertEqual(batch["label"], "")
            self.assertNotIn("--label", command[-1])
            self.assertIn("--max-usd 1.97", command[-1])
            self.assertIn("--domains accounting,geometry,writing", command[-1])
            self.assertIn(REGISTRY + "@" + IMAGE_DIGEST, command)
            self.assertIn(str(self.output) + ":/pilot", command)
            self.assertNotIn(str(self.prior_output) + ":/pilot", command)
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

    def assert_blocked_before_reservation(self):
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assertFalse(any(command[1] == "run" for command, _ in self.calls))
        self.assertEqual(parse_json(self.auth_path.read_bytes())["tests_reserved"], 0)

    def test_success_reserves_three_new_tests_preserves_old_evidence_and_blocks_rerun(self):
        prior = {path: path.read_bytes() for path in self.prior_output.iterdir()}
        result = self.launch()
        self.assertEqual(result["new_tests"], 3)
        self.assertEqual(result["tests_reserved"], 3)
        self.assertEqual(result["max_tests"], 6)
        self.assertEqual(result["shared_cap_usd"], 1.97)
        self.assertAlmostEqual(result["combined_max_usd"], 2.9908688)
        self.assertEqual(result["remaining_usd_before_launch"], 1.97)
        self.assertEqual(self.ledger_path.read_bytes(), b"")
        self.assertEqual({path: path.read_bytes() for path in prior}, prior)
        self.assertEqual(parse_json(self.auth_path.read_bytes())["batches"][0]["status"], "launched")
        self.assertNotIn("must-stay-in-stdin", self.auth_path.read_text() + json.dumps(result))
        self.calls.clear()
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assertFalse(any(command[1] == "run" for command, _ in self.calls))

    def test_ambiguous_outcome_never_reclaims_or_relaunches(self):
        for outcome in ("timeout", "failure", "bad_ack"):
            with self.subTest(outcome=outcome):
                self.auth_path.write_text(json.dumps(self.authorization))
                self.calls.clear()
                self.outcome = outcome
                with self.assertRaises(LaunchBlocked) as raised:
                    self.launch()
                self.assertNotIn("PRIVATE", str(raised.exception))
                saved = parse_json(self.auth_path.read_bytes())
                self.assertEqual(saved["tests_reserved"], 3)
                self.assertEqual(saved["batches"][0]["status"], "launch_outcome_unknown")
                self.calls.clear()
                with self.assertRaises(LaunchBlocked):
                    self.launch()
                self.assertFalse(any(command[1] == "run" for command, _ in self.calls))

    def test_old_pending_request_blocks(self):
        self.old_rows.append({"id": "pending", "status": "reserved", "reserved_usd": .01})
        self.write_old_ledger()
        self.assert_blocked_before_reservation()

    def test_old_unknown_usage_blocks_even_when_fully_reserved(self):
        self.old_rows[-1]["usage_unknown"] = True
        self.old_rows[-1]["charged_usd"] = 1.1
        self.write_old_ledger()
        self.assert_blocked_before_reservation()

    def test_old_cost_mismatch_blocks_in_both_directions(self):
        for value in (.5, 1.04):
            with self.subTest(value=value):
                self.old_rows[-1]["charged_usd"] = value
                self.write_old_ledger()
                self.assert_blocked_before_reservation()

    def test_old_authorization_not_exhausted_blocks(self):
        self.old_authorization["tests_reserved"] = 3
        self.old_auth_path.write_text(json.dumps(self.old_authorization))
        self.assert_blocked_before_reservation()

    def test_incomplete_old_report_blocks(self):
        (self.prior_output / "geometry_novice_missing-corrected-balanced.json").write_text("{}")
        self.assert_blocked_before_reservation()

    def test_nonempty_new_ledger_blocks_without_reset(self):
        self.ledger_path.write_bytes(b"prior-content\n")
        self.assert_blocked_before_reservation()
        self.assertEqual(self.ledger_path.read_bytes(), b"prior-content\n")

    def test_existing_new_artifact_blocks(self):
        (self.output / "writing_novice_missing-balanced.json").write_text("{}")
        self.assert_blocked_before_reservation()

    def test_existing_new_container_blocks(self):
        self.existing_new_container = True
        self.assert_blocked_before_reservation()

    def test_active_pilot_blocks(self):
        self.active = ["cmpys-other-acceptance"]
        self.assert_blocked_before_reservation()

    def test_wrong_web_image_and_architecture_block(self):
        self.web_tag = PRIOR_FOLLOWUP_TAG
        self.assert_blocked_before_reservation()
        self.web_tag = RELEASE_TAG
        self.architecture = "amd64"
        self.assert_blocked_before_reservation()

    def test_invalid_environment_blocks_without_leaking(self):
        for environment in (["PRIVATE_TEST_SECRET=private\nleak"], ["KEY=value", "KEY=other"], ["=value"]):
            self.environment = environment
            self.assert_blocked_before_reservation()

    def test_wrong_new_cap_scope_or_count_blocks(self):
        for key, value in (("shared_cap_usd", 3.0), ("scope", PRIOR_SCOPE), ("max_tests", 9),
                           ("tests_reserved", 3), ("owner_approved", False)):
            changed = dict(self.authorization, **{key: value})
            self.auth_path.write_text(json.dumps(changed))
            with self.assertRaises(LaunchBlocked):
                self.launch()
            self.assertFalse(any(command[1] == "run" for command, _ in self.calls))

    def test_fixture_mismatch_blocks(self):
        self.fixture.write_text("changed")
        self.assert_blocked_before_reservation()

    def test_concurrent_launcher_lock_blocks(self):
        with (self.output / "authorization.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_blocked_before_reservation()

    def test_old_ledger_change_during_preflight_blocks(self):
        self.before_run = lambda: self.old_ledger.write_text(self.old_ledger.read_text() + "\n")
        self.assert_blocked_before_reservation()

    def test_duplicate_json_and_nonfinite_amounts_fail_closed(self):
        for raw in ('{"max_tests":6,"max_tests":6}', '{"shared_cap_usd":NaN}'):
            self.auth_path.write_text(raw)
            with self.assertRaises(LaunchBlocked):
                self.launch()
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--self-test", action="store_true", help="Use mocks only; no Docker or network")
    group.add_argument("--launch", action="store_true", help="Run only on the reviewed deployment host")
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


