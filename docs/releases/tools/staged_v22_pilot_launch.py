"""Launch only the final three of the existing six authorized tests, once.

Run on the deployment host after v22 deployment verification. This launcher
reuses the v21 ledger and never reclaims a reserved test after an ambiguous
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
from unittest.mock import patch
from uuid import uuid4


REGISTRY = "297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend"
RELEASE_TAG = "20261017-013000-field-drafts"
# Registry digest and manifest pinned after frozen-image verification.
IMAGE_DIGEST = "sha256:9b30b39bfb0f6dc5b4e82114c2dace33eef546c78c5bbba1af8225006bb68fdb"
MANIFEST_SHA256 = "28f7b62ced61c44f2f1d6159018b3e55f5b40bbab6519af9c3a67a547741b518"
FIRST_RELEASE_TAG = "20261017-001200-structured-solutions"
FIRST_IMAGE_DIGEST = "sha256:97e972c16a39963bc544ee3860ebc6ce51605dba20192df5cfae95ae55a86d73"
FIRST_CONTAINER = "cmpys-staged-v21-batch-20261017"
PRIOR_RELEASE_TAG = "20261016-150539-validation-boundaries"
PRIOR_CONTAINER = "cmpys-staged-v19-batch-20261016"
PRIOR_FOLLOWUP_TAG = "20261016-153858-scoped-preflight"
PRIOR_FOLLOWUP_CONTAINER = "cmpys-staged-v20-batch-20261016"
CONTAINER = "cmpys-staged-v22-batch-20261017"
WEB_CONTAINER = "cmpys-web-1"
DOMAINS = ["accounting", "geometry", "writing"]
CAP = Decimal("1.97")
PRIOR_ACCOUNTED = Decimal("1.0208688")
FIRST_ACCOUNTED = Decimal("0.2193908")
FIRST_REQUEST_COUNT = 10
COMBINED_LIMIT = Decimal("3.0")
ACCOUNTING_TOLERANCE = Decimal("0.000000001")
FIXTURE_SHA256 = "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
PRIOR_SCOPE = "synthetic accounting, geometry, writing across deployed revision and follow-up fixes"
SCOPE = "synthetic accounting, geometry, writing across v21 and follow-up fixes"
RELEASE_ROOT = Path("/opt/cmpys/releases")
COMMAND = (
    "umask 077; exec python -m scripts.pilot_generation --max-usd 1.97 "
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


def completed_ledger(raw, *, expected_cost, expected_count=None):
    """Require the exact settled baseline; retain its bytes and ordered IDs."""
    rows = [parse_json(line) for line in raw.splitlines() if line.strip()]
    require(bool(rows), "Existing ledger must not be empty or reset")
    pending, seen, finished = {}, [], set()
    spent = Decimal(0)
    for row in rows:
        require(type(row) is dict and type(row.get("id")) is str and row["id"], "Invalid ledger identity")
        ident = row["id"]
        if row.get("status") == "reserved":
            require(ident not in seen, "Repeated ledger reservation")
            value = money(row.get("reserved_usd"))
            require(value > 0, "Invalid ledger reservation")
            pending[ident] = value
            seen.append(ident)
        elif row.get("status") == "finished":
            require(ident in pending and ident not in finished, "Unmatched ledger completion")
            require(row.get("usage_unknown") is False, "Prior unknown usage is not settled")
            value = money(row.get("charged_usd"))
            require(value <= pending.pop(ident), "Prior charge exceeded its reservation")
            spent += value
            finished.add(ident)
        else:
            raise LaunchBlocked("Unknown ledger status")
    require(not pending and set(seen) == finished, "Prior requests remain pending")
    require(expected_count is None or len(finished) == expected_count, "Prior request count differs")
    require(abs(spent - expected_cost) <= ACCOUNTING_TOLERANCE, "Prior cost differs from approved baseline")
    return {"prior_request_ids": seen, "prior_ledger_rows": len(rows),
            "prior_ledger_sha256": sha256(raw), "prior_accounted_usd": float(spent)}


def launch(*, root=RELEASE_ROOT, runner=subprocess.run, fixture_hash=FIXTURE_SHA256):
    require(re.fullmatch(r"[0-9]{8}-[0-9]{6}-[a-z-]+", RELEASE_TAG) is not None
            and re.fullmatch(r"sha256:[0-9a-f]{64}", IMAGE_DIGEST) is not None
            and re.fullmatch(r"[0-9a-f]{64}", MANIFEST_SHA256) is not None,
            "Release image and manifest are not pinned")
    first_release = root / FIRST_RELEASE_TAG
    output = first_release / "live-batch"
    older_output = root / PRIOR_RELEASE_TAG / "live-batch"
    release = root / RELEASE_TAG
    require(all(path.is_dir() and not path.is_symlink() for path in
                (first_release, output, older_output.parent, older_output, release)),
            "Required existing release directories are unavailable")
    authorization_path = output / "authorization.json"
    ledger_path = output / "usage.jsonl"
    lock_fd = os.open(output / "authorization.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise LaunchBlocked("Another launcher holds the authorization lock") from None
        evidence = {}

        def read_frozen(path):
            raw = regular_bytes(path)
            evidence[path] = raw
            return raw

        authorization = parse_json(read_frozen(authorization_path))
        require(type(authorization) is dict and authorization.get("max_tests") == 6
                and type(authorization.get("tests_reserved")) is int
                and authorization["tests_reserved"] == 3
                and authorization.get("owner_approved") is True
                and money(authorization.get("shared_cap_usd")) == CAP
                and authorization.get("scope") == SCOPE
                and authorization.get("ledger") == str(ledger_path),
                "Remaining authorization does not match the existing shared batch")
        batches = authorization.get("batches")
        require(type(batches) is list and len(batches) == 1 and type(batches[0]) is dict,
                "Follow-up tests were already reserved or authorization is ambiguous")
        first = batches[0]
        expected_first = {"container": FIRST_CONTAINER, "release": FIRST_RELEASE_TAG,
                          "image_digest": FIRST_IMAGE_DIGEST, "label": "", "tests_reserved": 3,
                          "domains": DOMAINS, "status": "launched", "prior_request_ids": [],
                          "fixture_sha256": fixture_hash}
        require(all(first.get(key) == value for key, value in expected_first.items())
                and money(first.get("prior_accounted_usd")) == 0
                and money(first.get("remaining_usd")) == CAP
                and type(first.get("container_id")) is str
                and re.fullmatch(r"[0-9a-f]{64}", first["container_id"]) is not None,
                "First-batch authorization differs from the completed v21 batch")

        older = first.get("completed_previous_authorization")
        require(type(older) is dict and type(older.get("prior_completed_request_count")) is int
                and older["prior_completed_request_count"] > 0,
                "Older accounting boundary is missing")
        old_auth_raw = read_frozen(older_output / "authorization.json")
        old_auth = parse_json(old_auth_raw)
        require(sha256(old_auth_raw) == older.get("prior_authorization_sha256")
                and type(old_auth) is dict and old_auth.get("max_tests") == 6
                and old_auth.get("tests_reserved") == 6 and old_auth.get("owner_approved") is True
                and money(old_auth.get("shared_cap_usd")) == COMBINED_LIMIT
                and old_auth.get("scope") == PRIOR_SCOPE
                and old_auth.get("ledger") == str(older_output / "usage.jsonl"),
                "Older authorization no longer matches the verified baseline")
        old_batches = old_auth.get("batches")
        require(type(old_batches) is list and len(old_batches) == 2, "Older authorization batch count differs")
        for old_batch, tag, name, label in zip(old_batches,
                (PRIOR_RELEASE_TAG, PRIOR_FOLLOWUP_TAG), (PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER), ("", "corrected")):
            require(type(old_batch) is dict and old_batch.get("release") == tag
                    and old_batch.get("container") == name and old_batch.get("label") == label
                    and old_batch.get("tests_reserved") == 3 and old_batch.get("domains") == DOMAINS
                    and old_batch.get("status") == "launched", "Older batch boundary differs")
        old_boundary = completed_ledger(read_frozen(older_output / "usage.jsonl"),
            expected_cost=PRIOR_ACCOUNTED, expected_count=older["prior_completed_request_count"])
        require(old_boundary["prior_ledger_sha256"] == older.get("prior_ledger_sha256")
                and abs(money(older.get("prior_accounted_usd")) - PRIOR_ACCOUNTED) <= ACCOUNTING_TOLERANCE
                and abs(money(older.get("combined_max_usd")) - (PRIOR_ACCOUNTED + CAP)) <= ACCOUNTING_TOLERANCE
                and money(old_boundary["prior_accounted_usd"]) + CAP <= COMBINED_LIMIT,
                "Combined accounting no longer matches the approved ceiling")

        boundary = completed_ledger(read_frozen(ledger_path), expected_cost=FIRST_ACCOUNTED,
                                    expected_count=FIRST_REQUEST_COUNT)
        require(FIRST_ACCOUNTED < CAP, "Shared pilot budget is exhausted")
        boundary["remaining_usd"] = float(CAP - money(boundary["prior_accounted_usd"]))
        for domain in DOMAINS:
            case_id = domain + "_novice_missing"
            report = parse_json(read_frozen(output / (case_id + "-balanced.json")))
            require(type(report) is dict and report.get("scenario_id") == case_id
                    and report.get("tier") == "balanced" and report.get("full_pipeline") is True
                    and type(report.get("accepted")) is bool and type(report.get("failures")) is list,
                    "A completed first-batch report is missing")
        require(not any("-corrected-" in path.name for path in output.iterdir()),
                "A follow-up artifact already exists; do not relaunch")

        fixture = first_release / "generation_scenarios.json"
        require(sha256(read_frozen(fixture)) == fixture_hash, "Synthetic fixture hash differs")
        manifest_path = release / "manifest.json"
        manifest_raw = read_frozen(manifest_path)
        require(sha256(manifest_raw) == MANIFEST_SHA256, "Reviewed release manifest differs")
        manifest = parse_json(manifest_raw)
        require(type(manifest) is dict and bool(manifest)
                and all(type(path) is str and path and type(value) is str
                        and re.fullmatch(r"[0-9a-f]{64}", value) for path, value in manifest.items()),
                "Reviewed release manifest is invalid")
        names = docker(runner, "ps", "-a", "--format", "{{.Names}}").splitlines()
        require(FIRST_CONTAINER in names and CONTAINER not in names, "Pilot container identity guard failed")
        active = docker(runner, "ps", "--format", "{{.Names}}").splitlines()
        require(not any(name.startswith("cmpys") and any(word in name for word in ("pilot", "acceptance", "batch"))
                        for name in active), "A synthetic pilot is already active")
        first_container = inspect_one(runner, "inspect", FIRST_CONTAINER)
        state = first_container.get("State", {})
        require(state.get("Status") == "exited" and state.get("Running") is False
                and not state.get("Paused") and not state.get("Restarting")
                and first_container.get("Id") == first["container_id"], "The first batch has not stopped or its identity changed")
        web = inspect_one(runner, "inspect", WEB_CONTAINER)
        image_ref = REGISTRY + "@" + IMAGE_DIGEST
        image = inspect_one(runner, "image", "inspect", image_ref)
        require(web.get("State", {}).get("Running") is True
                and not web["State"].get("Paused") and not web["State"].get("Restarting")
                and web.get("Config", {}).get("Image") in (REGISTRY + ":" + RELEASE_TAG, image_ref)
                and type(image.get("Id")) is str and image["Id"]
                and web.get("Image") == image["Id"] and image.get("Architecture") == "arm64"
                and image_ref in image.get("RepoDigests", []), "Production web is not the pinned v22 image")
        environment = web["Config"].get("Env")
        require(type(environment) is list and bool(environment)
                and all(type(line) is str and "=" in line and line.split("=", 1)[0]
                        and not any(char in line for char in ("\n", "\r", "\x00")) for line in environment),
                "Web environment cannot be safely passed over stdin")
        require(len({line.split("=", 1)[0] for line in environment}) == len(environment),
                "Web environment has duplicate keys")
        require(all(regular_bytes(path) == raw for path, raw in evidence.items()),
                "Authorization, ledger, reports, fixture or manifest changed during preflight")
        require(not any("-corrected-" in path.name for path in output.iterdir()),
                "A follow-up artifact appeared during preflight")
        batch = {"container": CONTAINER, "release": RELEASE_TAG, "image_digest": IMAGE_DIGEST,
                 "manifest_sha256": MANIFEST_SHA256, "label": "corrected", "tests_reserved": 3, "domains": DOMAINS,
                 "status": "reserved", "reserved_at": datetime.now(timezone.utc).isoformat(),
                 "fixture_sha256": fixture_hash, **boundary, "completed_previous_authorization": copy.deepcopy(older)}
        reserved = copy.deepcopy(authorization)
        reserved["tests_reserved"] = 6
        reserved["batches"].append(batch)
        atomic_json(authorization_path, reserved)
        # No reclaim after reservation: the daemon may have launched the process.
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
                "manifest_sha256": MANIFEST_SHA256, "tests_reserved": 6, "new_tests": 3, "max_tests": 6,
                "shared_cap_usd": float(CAP), "prior_request_count": FIRST_REQUEST_COUNT,
                "prior_accounted_usd": boundary["prior_accounted_usd"],
                "previous_authorization_reported_usd": older["prior_accounted_usd"],
                "combined_max_usd": older["combined_max_usd"],
                "remaining_usd_before_launch": boundary["remaining_usd"]}
    finally:
        os.close(lock_fd)


class LauncherSafetyTests(unittest.TestCase):
    """Every subprocess is mocked. No Docker, credentials or provider calls."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / FIRST_RELEASE_TAG / "live-batch"
        self.older_output = self.root / PRIOR_RELEASE_TAG / "live-batch"
        self.release = self.root / RELEASE_TAG
        for directory in (self.output, self.older_output, self.release):
            directory.mkdir(parents=True)
        self.fixture = self.output.parent / "generation_scenarios.json"
        self.fixture.write_bytes(b'{"synthetic_fixture":true}')
        self.fixture_hash = sha256(self.fixture.read_bytes())
        self.manifest = self.release / "manifest.json"
        self.manifest.write_text(json.dumps({"app/services/planning/activity_draft.py": "d" * 64}))
        pins = patch.dict(globals(), IMAGE_DIGEST="sha256:" + "e" * 64,
                          MANIFEST_SHA256=sha256(self.manifest.read_bytes()))
        pins.start()
        self.addCleanup(pins.stop)
        self.older_auth_path = self.older_output / "authorization.json"
        self.older_auth = {"max_tests": 6, "shared_cap_usd": 3.0, "owner_approved": True,
            "scope": PRIOR_SCOPE, "ledger": str(self.older_output / "usage.jsonl"), "tests_reserved": 6,
            "batches": [{"release": tag, "container": name, "label": label, "tests_reserved": 3,
                         "domains": DOMAINS, "status": "launched"}
                        for tag, name, label in zip((PRIOR_RELEASE_TAG, PRIOR_FOLLOWUP_TAG),
                            (PRIOR_CONTAINER, PRIOR_FOLLOWUP_CONTAINER), ("", "corrected"))]}
        self.older_auth_path.write_text(json.dumps(self.older_auth))
        self.older_ledger = self.older_output / "usage.jsonl"
        self.older_rows = [{"id": "older", "status": "reserved", "reserved_usd": 1.1},
                           {"id": "older", "status": "finished", "charged_usd": 1.0208688,
                            "usage_unknown": False}]
        self.write_rows(self.older_ledger, self.older_rows)
        old_boundary = {"prior_completed_request_count": 1,
                        "prior_ledger_sha256": sha256(self.older_ledger.read_bytes()),
                        "prior_authorization_sha256": sha256(self.older_auth_path.read_bytes()),
                        "prior_accounted_usd": 1.0208688, "combined_max_usd": 2.9908688}
        self.authorization = {"max_tests": 6, "shared_cap_usd": 1.97, "owner_approved": True,
            "scope": SCOPE, "ledger": str(self.output / "usage.jsonl"), "tests_reserved": 3,
            "batches": [{"container": FIRST_CONTAINER, "release": FIRST_RELEASE_TAG,
                "image_digest": FIRST_IMAGE_DIGEST, "label": "", "tests_reserved": 3,
                "domains": DOMAINS, "status": "launched", "prior_request_ids": [],
                "fixture_sha256": self.fixture_hash, "prior_accounted_usd": 0.0, "remaining_usd": 1.97,
                "container_id": "b" * 64, "completed_previous_authorization": old_boundary}]}
        self.auth_path = self.output / "authorization.json"
        self.auth_path.write_text(json.dumps(self.authorization))
        self.rows = []
        for index in range(10):
            self.rows.extend([{"id": "call-" + str(index), "status": "reserved", "reserved_usd": .1},
                {"id": "call-" + str(index), "status": "finished", "charged_usd": .02193908,
                 "usage_unknown": False}])
        self.ledger = self.output / "usage.jsonl"
        self.write_rows(self.ledger, self.rows)
        for domain in DOMAINS:
            (self.output / (domain + "_novice_missing-balanced.json")).write_text(json.dumps({
                "scenario_id": domain + "_novice_missing", "tier": "balanced", "full_pipeline": True,
                "accepted": False, "failures": ["Synthetic shape error"]}))
        self.calls = []
        self.outcome = "success"
        self.active = []
        self.existing_new_container = False
        self.first_state = {"Status": "exited", "Running": False}
        self.first_id = "b" * 64
        self.web_tag = RELEASE_TAG
        self.architecture = "arm64"
        self.environment = ["LLM_PROVIDER=zai", "PRIVATE_TEST_SECRET=must-stay-in-stdin"]
        self.preflight_mutation = None
        self.reservation_check = None

    @staticmethod
    def write_rows(path, rows):
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))

    def runner(self, command, **kwargs):
        self.calls.append((command, kwargs))
        args = command[1:]
        if args[:2] == ["ps", "-a"]:
            output = "\n".join([FIRST_CONTAINER, WEB_CONTAINER] + ([CONTAINER] if self.existing_new_container else []))
        elif args[:1] == ["ps"]:
            output = "\n".join(self.active + [WEB_CONTAINER])
        elif args == ["inspect", FIRST_CONTAINER]:
            output = json.dumps([{"State": self.first_state, "Id": self.first_id}])
        elif args == ["inspect", WEB_CONTAINER]:
            output = json.dumps([{"State": {"Running": True}, "Image": "sha256:local-image",
                "Config": {"Image": REGISTRY + ":" + self.web_tag, "Env": self.environment}}])
        elif args[:2] == ["image", "inspect"]:
            if self.preflight_mutation:
                self.preflight_mutation()
            output = json.dumps([{"Id": "sha256:local-image", "Architecture": self.architecture,
                                  "RepoDigests": [REGISTRY + "@" + IMAGE_DIGEST]}])
        elif args[:1] == ["run"]:
            saved = parse_json(self.auth_path.read_bytes())
            self.assertEqual(saved["tests_reserved"], 6)
            self.assertEqual(len(saved["batches"]), 2)
            self.assertEqual(saved["batches"][0], self.authorization["batches"][0])
            batch = saved["batches"][1]
            self.assertEqual(batch["status"], "reserved")
            self.assertEqual(batch["prior_request_ids"], ["call-" + str(i) for i in range(10)])
            self.assertEqual(batch["prior_accounted_usd"], .2193908)
            self.assertEqual(batch["remaining_usd"], 1.7506092)
            self.assertEqual(batch["completed_previous_authorization"]["prior_accounted_usd"], 1.0208688)
            self.assertEqual(batch["manifest_sha256"], MANIFEST_SHA256)
            self.assertEqual(batch["label"], "corrected")
            self.assertIn("--label corrected", command[-1])
            self.assertIn("--max-usd 1.97", command[-1])
            self.assertIn("--domains accounting,geometry,writing", command[-1])
            self.assertIn(REGISTRY + "@" + IMAGE_DIGEST, command)
            self.assertIn(str(self.output) + ":/pilot", command)
            self.assertNotIn(str(self.release / "live-batch") + ":/pilot", command)
            self.assertIn("--pull", command)
            self.assertEqual(command[command.index("--pull") + 1], "never")
            self.assertEqual(command[command.index("--env-file") + 1], "/dev/stdin")
            self.assertIn("must-stay-in-stdin", kwargs["input"])
            self.assertNotIn("must-stay-in-stdin", str(command))
            if self.reservation_check:
                self.reservation_check()
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

    def assert_blocked(self):
        original = self.auth_path.read_bytes()
        with self.assertRaises(LaunchBlocked):
            self.launch()
        self.assertFalse(any(command[1] == "run" for command, _ in self.calls))
        self.assertEqual(self.auth_path.read_bytes(), original)

    def test_success_preserves_both_ledgers_and_reserves_only_remaining_three_once(self):
        before = {path: path.read_bytes() for path in (self.ledger, self.older_ledger, self.older_auth_path)}
        with patch.object(os, "fsync", wraps=os.fsync) as sync:
            self.reservation_check = lambda: self.assertGreaterEqual(sync.call_count, 2)
            result = self.launch()
        self.assertEqual(result["new_tests"], 3)
        self.assertEqual(result["tests_reserved"], 6)
        self.assertEqual(result["prior_request_count"], 10)
        self.assertEqual(result["shared_cap_usd"], 1.97)
        self.assertEqual(result["combined_max_usd"], 2.9908688)
        self.assertEqual(result["remaining_usd_before_launch"], 1.7506092)
        self.assertEqual({path: path.read_bytes() for path in before}, before)
        saved = parse_json(self.auth_path.read_bytes())
        self.assertEqual(saved["batches"][1]["status"], "launched")
        self.assertNotIn("must-stay-in-stdin", self.auth_path.read_text() + json.dumps(result))
        self.calls.clear()
        self.assert_blocked()

    def test_ambiguous_outcome_consumes_reservation_and_blocks_relaunch(self):
        for outcome in ("timeout", "failure", "bad_ack"):
            with self.subTest(outcome=outcome):
                self.auth_path.write_text(json.dumps(self.authorization))
                self.calls.clear()
                self.outcome = outcome
                with self.assertRaises(LaunchBlocked) as raised:
                    self.launch()
                self.assertNotIn("PRIVATE", str(raised.exception))
                saved = parse_json(self.auth_path.read_bytes())
                self.assertEqual(saved["tests_reserved"], 6)
                self.assertEqual(saved["batches"][1]["status"], "launch_outcome_unknown")
                self.calls.clear()
                self.assert_blocked()

    def test_missing_pins_fail_before_docker_or_reservation(self):
        for key in ("IMAGE_DIGEST", "MANIFEST_SHA256"):
            with patch.dict(globals(), {key: ""}):
                self.assert_blocked()
        self.assertEqual(self.calls, [])

    def test_empty_shared_ledger_blocks_without_reset(self):
        self.ledger.write_bytes(b"")
        self.assert_blocked()
        self.assertEqual(self.ledger.read_bytes(), b"")

    def test_pending_current_request_blocks(self):
        self.write_rows(self.ledger, self.rows[:-1])
        self.assert_blocked()

    def test_unknown_current_request_blocks(self):
        self.rows[-1].update(usage_unknown=True, charged_usd=.1)
        self.write_rows(self.ledger, self.rows)
        self.assert_blocked()

    def test_current_cost_or_count_mismatch_blocks(self):
        self.rows[-1]["charged_usd"] = .03
        self.write_rows(self.ledger, self.rows)
        self.assert_blocked()
        self.write_rows(self.ledger, self.rows[:-2])
        self.assert_blocked()

    def test_older_cost_unknown_pending_or_hash_change_blocks(self):
        for defect in ("cost", "unknown", "pending", "hash"):
            with self.subTest(defect=defect):
                changed = copy.deepcopy(self.older_rows)
                if defect == "cost":
                    changed[-1]["charged_usd"] = 1.01
                elif defect == "unknown":
                    changed[-1].update(usage_unknown=True, charged_usd=1.1)
                elif defect == "pending":
                    changed.pop()
                self.write_rows(self.older_ledger, changed)
                if defect == "hash":
                    self.older_ledger.write_text(self.older_ledger.read_text() + "\n")
                self.assert_blocked()

    def test_older_authorization_mutation_blocks(self):
        self.older_auth["tests_reserved"] = 3
        self.older_auth_path.write_text(json.dumps(self.older_auth))
        self.assert_blocked()

    def test_incomplete_first_report_blocks(self):
        (self.output / "geometry_novice_missing-balanced.json").write_text("{}")
        self.assert_blocked()

    def test_existing_labeled_artifact_blocks(self):
        (self.output / "writing_novice_missing-corrected-package.json").write_text("{}")
        self.assert_blocked()

    def test_existing_followup_container_blocks(self):
        self.existing_new_container = True
        self.assert_blocked()

    def test_active_pilot_blocks(self):
        self.active = ["cmpys-other-acceptance"]
        self.assert_blocked()

    def test_first_container_running_or_replaced_blocks(self):
        self.first_state = {"Status": "running", "Running": True}
        self.assert_blocked()
        self.first_state = {"Status": "exited", "Running": False}
        self.first_id = "c" * 64
        self.assert_blocked()

    def test_wrong_web_image_or_architecture_blocks(self):
        self.web_tag = FIRST_RELEASE_TAG
        self.assert_blocked()
        self.web_tag = RELEASE_TAG
        self.architecture = "amd64"
        self.assert_blocked()

    def test_unsafe_environment_blocks(self):
        for environment in (["KEY=private\nvalue"], ["KEY=a", "KEY=b"], ["=value"], []):
            self.environment = environment
            self.assert_blocked()

    def test_changed_cap_scope_count_or_authorization_blocks(self):
        for key, value in (("shared_cap_usd", 3.0), ("max_tests", 9), ("tests_reserved", 6),
                           ("scope", PRIOR_SCOPE), ("owner_approved", False), ("ledger", "/new/usage.jsonl")):
            self.auth_path.write_text(json.dumps(dict(self.authorization, **{key: value})))
            self.assert_blocked()

    def test_first_batch_identity_or_unknown_launch_state_blocks(self):
        for key, value in (("status", "launch_outcome_unknown"), ("release", RELEASE_TAG),
                           ("image_digest", "sha256:" + "c" * 64), ("prior_request_ids", ["unreviewed"])):
            changed = copy.deepcopy(self.authorization)
            changed["batches"][0][key] = value
            self.auth_path.write_text(json.dumps(changed))
            self.assert_blocked()

    def test_manifest_or_fixture_hash_mismatch_blocks(self):
        self.manifest.write_text("{}")
        self.assert_blocked()
        self.fixture.write_text("changed")
        self.assert_blocked()

    def test_concurrent_launcher_is_blocked_by_lock(self):
        with (self.output / "authorization.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_blocked()

    def test_evidence_changes_during_preflight_block_before_reserving(self):
        for path in (self.ledger, self.older_ledger, self.auth_path, self.manifest):
            before = path.read_bytes()
            self.preflight_mutation = lambda path=path: path.write_bytes(before + b"\n")
            with self.assertRaises(LaunchBlocked):
                self.launch()
            self.assertFalse(any(command[1] == "run" for command, _ in self.calls))
            self.assertEqual(parse_json(self.auth_path.read_bytes())["tests_reserved"], 3)
            path.write_bytes(before)

    def test_duplicate_json_and_nonfinite_usage_fail_closed(self):
        for raw in ('{"max_tests":6,"max_tests":6}', '{"shared_cap_usd":NaN}'):
            self.auth_path.write_text(raw)
            self.assert_blocked()
        self.assertEqual(self.calls, [])

    def test_duplicate_or_unmatched_ledger_entries_block(self):
        for rows in (self.rows + self.rows[:1], self.rows[1:], self.rows + self.rows[-1:]):
            self.write_rows(self.ledger, rows)
            self.assert_blocked()

    def test_reservation_fsync_failure_does_not_launch(self):
        with patch.object(os, "fsync", side_effect=OSError("synthetic storage failure")):
            with self.assertRaises(OSError):
                self.launch()
        self.assertFalse(any(command[1] == "run" for command, _ in self.calls))
        self.assertEqual(parse_json(self.auth_path.read_bytes())["tests_reserved"], 3)


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
    except OSError:
        print(json.dumps({"status": "blocked", "reason": "Local storage operation failed; do not relaunch"}))
        raise SystemExit(1)


