"""Prepare or run two pinned, network-disabled offline replay phases.

Private baseline output is piped only between containers on the backend host.
No provider calls, deployment, publication, private local copy, or server write.
Candidate pins intentionally fail closed until the release owner supplies them.
"""
import argparse
import ast
import hashlib
import importlib.util
import inspect
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
BASELINE_RELEASE = "20261017-013000-field-drafts"
BASELINE_DIGEST = "sha256:9b30b39bfb0f6dc5b4e82114c2dace33eef546c78c5bbba1af8225006bb68fdb"
BASELINE_MANIFEST_SHA = "28f7b62ced61c44f2f1d6159018b3e55f5b40bbab6519af9c3a67a547741b518"
BASELINE_PAYLOAD_SHA = "99ee24717a1206faefa7bf4940cba5223e2dca296e07f0deeaeb1dba8625f942"
CAPTURE_RELEASE = "20261017-001200-structured-solutions"
FIXTURE_SHA = "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
CANDIDATE_RELEASE = "20261017-020500-evidence-context"
CANDIDATE_DIGEST = "sha256:bec8540a949882fb621a13e25b274edaa1eabec58ee49bbf547bc818ed40e8d3"
CANDIDATE_MANIFEST_SHA = "f242cf3c0eb392d7316aeafadb115d620be483ea0b38f019aba3b46cc7719e27"
CANDIDATE_MANIFEST_COUNT = 30
CANDIDATE_MANIFEST_NAME = "2026-10-17-staged-v23-manifest.json"


def checked_manifest(path, expected, count):
    if not expected or not count or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("Candidate pins are not finalized")
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("Frozen manifest hash changed")
    value = json.loads(raw)
    if not isinstance(value, dict) or len(value) != count:
        raise ValueError("Unexpected frozen source scope")
    return value


def programs(cases):
    if not cases or len(cases) != len(set(cases)) or not set(cases) <= {"accounting", "geometry", "writing"}:
        raise ValueError("Explicit unique synthetic cases required")
    if (not CANDIDATE_RELEASE or not CANDIDATE_MANIFEST_NAME or not CANDIDATE_DIGEST
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", CANDIDATE_DIGEST)):
        raise ValueError("Candidate pins are not finalized")
    old = (HERE / "staged_v22_audit_payload.py").read_bytes()
    if hashlib.sha256(old).hexdigest() != BASELINE_PAYLOAD_SHA:
        raise ValueError("Reviewed baseline replay helper changed")
    replay = (HERE / "staged_v23_replay_payload.py").read_text()
    source = old.decode() + "\n" + replay
    ast.parse(source)
    baseline = {"release": BASELINE_RELEASE, "digest": BASELINE_DIGEST,
        "manifest_sha256": BASELINE_MANIFEST_SHA,
        "manifest": checked_manifest(HERE.parent / "2026-10-17-staged-v22-manifest.json", BASELINE_MANIFEST_SHA, 29),
        "fixture_sha256": FIXTURE_SHA, "cases": cases}
    candidate = {"release": CANDIDATE_RELEASE, "digest": CANDIDATE_DIGEST,
        "manifest": checked_manifest(HERE.parent / CANDIDATE_MANIFEST_NAME, CANDIDATE_MANIFEST_SHA, CANDIDATE_MANIFEST_COUNT),
        "baseline_digest": BASELINE_DIGEST, "baseline_manifest_sha256": BASELINE_MANIFEST_SHA,
        "fixture_sha256": FIXTURE_SHA, "cases": cases}
    return source + "\nbaseline_replay(" + repr(baseline) + ")\n", source + "\nrun_candidate_replay(" + repr(candidate) + ")\n"


def remote_driver(baseline_source, candidate_source, baseline_digest, candidate_digest, capture_release):
    """Executed only on the backend host; private pipe bytes are never logged."""
    import json
    import subprocess
    import threading
    base = ["sudo", "docker", "run", "--rm", "-i", "--pull", "never", "--network", "none", "--read-only",
            "--user", "0:0", "-e", "LLM_PROVIDER=dummy", "-e", "BOOK_NARRATION_ENABLED=false",
            "-e", "PYTHONPATH=/app", "-e", "PYTHONDONTWRITEBYTECODE=1"]
    mount = ["-v", "/opt/cmpys/releases/" + capture_release + "/live-batch:/captures:ro", "-v",
             "/opt/cmpys/releases/" + capture_release + "/generation_scenarios.json:/scenarios.json:ro"]
    image = "297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend@"
    first = subprocess.Popen(base + mount + ["--entrypoint", "python", image + baseline_digest, "-"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    # The baseline script enters stdin; its private output has exactly one
    # consumer: the candidate's stdin. The candidate gets no capture mount.
    writer_error = []
    def write_source():
        try:
            first.stdin.write(baseline_source.encode())
            first.stdin.close()
        except Exception:
            writer_error.append(True)
    writer = threading.Thread(target=write_source, daemon=True)
    writer.start()
    try:
        second = subprocess.run(base + ["--entrypoint", "python", image + candidate_digest, "-c", candidate_source],
            stdin=first.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=50)
        first.stdout.close()
        code = first.wait(timeout=5)
        writer.join(timeout=1)
        if code or second.returncode or writer_error or writer.is_alive():
            raise ValueError("Offline replay phase failed")
        if len(second.stdout) > 500_000:
            raise ValueError("Offline replay output exceeded bound")
        rows = [json.loads(line) for line in second.stdout.decode().splitlines()]
        if not rows or any(row.get("mode") != "fixed_evidence_offline_candidate_replay" for row in rows):
            raise ValueError("Offline replay did not return bounded reports")
        for row in rows:
            print(json.dumps(row, ensure_ascii=False, sort_keys=True), flush=True)
    except Exception:
        if first.poll() is None:
            first.kill()
            first.wait(timeout=5)
        print(json.dumps({"replay_error": "offline_phase_failed", "private_details": "suppressed"}), flush=True)
        raise SystemExit(1)


def remote_program(cases):
    baseline, candidate = programs(cases)
    # Linux bounds individual argv strings. Refuse to exceed it rather than
    # introduce an unreviewed on-server file or shell quoting fallback.
    if len(candidate.encode()) > 120_000:
        raise ValueError("Candidate replay program exceeds fixed argv bound")
    return inspect.getsource(remote_driver) + "\nremote_driver(" + ",".join(map(repr,
        (baseline, candidate, BASELINE_DIGEST, CANDIDATE_DIGEST, CAPTURE_RELEASE))) + ")\n"


def self_test():
    spec = importlib.util.spec_from_file_location("v23_replay_tests", HERE / "staged_v23_replay_tests.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run_tests()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("accounting", "geometry", "writing"), action="append")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check-syntax", action="store_true")
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--run", action="store_true")
    args = parser.parse_args()
    ast.parse((HERE / "staged_v23_replay_payload.py").read_text())
    if args.check_syntax:
        print("Offline replay syntax valid; candidate pins remain mandatory before remote execution.")
        return
    if args.self_test:
        self_test()
        return
    program = remote_program(args.case)
    try:
        result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                                 "ec2-user@54.158.122.215", "python3 -"], input=program,
                                text=True, capture_output=True, timeout=65)
    except subprocess.TimeoutExpired:
        print(json.dumps({"replay_error": "offline_ssh_timeout", "private_details": "suppressed"}))
        raise SystemExit(1)
    if result.returncode:
        print(json.dumps({"replay_error": "offline_phase_failed", "private_details": "suppressed"}))
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        print(json.dumps(json.loads(line), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
