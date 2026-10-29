"""Run an explicitly selected completed synthetic case in the pinned offline image.

Default use is --check-syntax or --self-test. --run performs only a read-only
SSH/Docker audit. It never starts generation, deploys, or publishes content.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

RELEASE = "20261016-153858-scoped-preflight"
DIGEST = "sha256:1eafe22d991943427ccb28eee78bff5ef09c455c22400145cf4ffaa55063613e"
IMAGE = "297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend@" + DIGEST
CAPTURE_RELEASE = "20261016-150539-validation-boundaries"
MANIFEST_SHA256 = "60ce5db80b4c30bd9e90be9504293fc79e943360c0d8f5805283d423b10e8cc6"
HERE = Path(__file__).resolve().parent
MANIFEST = HERE.parent / "2026-10-16-staged-v20-manifest.json"
PAYLOAD = HERE / "staged_v20_audit_payload.py"


def manifest():
    raw = MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest() != MANIFEST_SHA256:
        raise ValueError("Reviewed manifest hash changed")
    value = json.loads(raw)
    if len(value) != 24:
        raise ValueError("Unexpected frozen manifest scope")
    return value


def script(cases, mode):
    source = PAYLOAD.read_text()
    ast.parse(source)
    config = {"release": RELEASE, "digest": DIGEST, "manifest": manifest(), "cases": cases, "mode": mode}
    return source + "\nrun_audit(" + repr(config) + ")\n"


def self_test():
    path = HERE / "test_staged_v20_audit.py"
    spec = importlib.util.spec_from_file_location("staged_v20_audit_selftest", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run_tests()


def main(default_mode="audit"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("accounting", "geometry", "writing"), action="append")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check-syntax", action="store_true")
    group.add_argument("--self-test", action="store_true")
    group.add_argument("--run", action="store_true")
    args = parser.parse_args()
    payload = script(args.case or [], default_mode)
    ast.parse(payload)
    if args.check_syntax:
        print("Pinned offline payload syntax valid; no remote access or provider calls.")
        return
    if args.self_test:
        self_test()
        return
    if not args.case:
        parser.error("--run requires at least one explicitly selected completed --case")
    # All interpolated arguments below are fixed, reviewed constants. Case
    # selection is in the Python input and never interpolated into the shell.
    remote = ("sudo docker run --rm -i --pull never --network none --read-only --user 0:0 "
              "-e LLM_PROVIDER=dummy -e BOOK_NARRATION_ENABLED=false -e PYTHONPATH=/app "
              "-e PYTHONDONTWRITEBYTECODE=1 "
              "-v /opt/cmpys/releases/" + CAPTURE_RELEASE + "/live-batch:/captures:ro "
              "-v /opt/cmpys/releases/" + RELEASE + "/generation_scenarios.json:/scenarios.json:ro "
              "--entrypoint python " + IMAGE + " -")
    try:
        result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                                 "ec2-user@54.158.122.215", remote], input=payload,
                                text=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        print(json.dumps({"audit_error": "offline_ssh_timeout", "stderr": "suppressed"}))
        raise SystemExit(1)
    if result.returncode:
        # Traceback text can contain source data. It must never be echoed.
        print(json.dumps({"audit_exit_code": result.returncode, "stderr": "suppressed"}))
        raise SystemExit(result.returncode)
    for line in result.stdout.splitlines():
        print(json.dumps(json.loads(line), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
