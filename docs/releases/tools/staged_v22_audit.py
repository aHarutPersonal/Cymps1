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

RELEASE = "20261017-013000-field-drafts"
DIGEST = "sha256:9b30b39bfb0f6dc5b4e82114c2dace33eef546c78c5bbba1af8225006bb68fdb"
CAPTURE_RELEASE = "20261017-001200-structured-solutions"
MANIFEST_SHA256 = "28f7b62ced61c44f2f1d6159018b3e55f5b40bbab6519af9c3a67a547741b518"
MANIFEST_COUNT = 29
FIXTURE_SHA256 = "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
HERE = Path(__file__).resolve().parent
MANIFEST = HERE.parent / "2026-10-17-staged-v22-manifest.json"
PAYLOAD = HERE / "staged_v22_audit_payload.py"


def manifest():
    if not DIGEST or not MANIFEST_SHA256 or not MANIFEST_COUNT:
        raise ValueError("Release pins are not finalized; remote audit is disabled")
    raw = MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest() != MANIFEST_SHA256:
        raise ValueError("Reviewed manifest hash changed")
    value = json.loads(raw)
    if len(value) != MANIFEST_COUNT:
        raise ValueError("Unexpected frozen manifest scope")
    return value


def script(cases, mode):
    source = PAYLOAD.read_text()
    ast.parse(source)
    config = {"release": RELEASE, "digest": DIGEST, "manifest": manifest(), "cases": cases, "mode": mode,
              "capture_release": CAPTURE_RELEASE, "manifest_sha256": MANIFEST_SHA256,
              "fixture_sha256": FIXTURE_SHA256}
    return source + "\nrun_audit(" + repr(config) + ")\n"


def self_test():
    path = HERE / "test_staged_v22_audit.py"
    spec = importlib.util.spec_from_file_location("staged_v22_audit_selftest", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run_tests()


def main(default_mode="audit"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("accounting", "geometry", "writing"), action="append")
    parser.add_argument("--components", action="store_true", help="Emit component/transport diagnostics only")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check-syntax", action="store_true")
    group.add_argument("--self-test", action="store_true")
    group.add_argument("--run", action="store_true")
    args = parser.parse_args()
    ast.parse(PAYLOAD.read_text())
    if args.check_syntax:
        print("Offline payload syntax valid; no remote access or provider calls. Remote execution requires finalized pins.")
        return
    if args.self_test:
        self_test()
        return
    if not args.case:
        parser.error("--run requires at least one explicitly selected completed --case")
    payload = script(args.case, "components" if args.components else default_mode)
    ast.parse(payload)
    # All interpolated arguments below are fixed, reviewed constants. Case
    # selection is in the Python input and never interpolated into the shell.
    remote = ("sudo docker run --rm -i --pull never --network none --read-only --user 0:0 "
              "-e LLM_PROVIDER=dummy -e BOOK_NARRATION_ENABLED=false -e PYTHONPATH=/app "
              "-e PYTHONDONTWRITEBYTECODE=1 "
              "-v /opt/cmpys/releases/" + CAPTURE_RELEASE + "/live-batch:/captures:ro "
              "-v /opt/cmpys/releases/" + CAPTURE_RELEASE + "/generation_scenarios.json:/scenarios.json:ro "
              "--entrypoint python 297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend@" + DIGEST + " -")
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
