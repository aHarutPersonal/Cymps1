"""Verify local follow-up code with the deployed image's dependencies, offline.

This does not build, pull, push or deploy an image. The existing v23 image is
read-only, has no network, and receives only explicit source/test mounts.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import time

from stage_v23_release import TEST_PREFIXES, EXCLUDED_IMAGE_TESTS

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / 'docs/releases'
BASE = ('297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend@'
        'sha256:bec8540a949882fb621a13e25b274edaa1eabec58ee49bbf547bc818ed40e8d3')
ALLOWED_CHANGED = {
    '/app/app/services/planning/lesson_review.py',
    '/app/app/services/planning/package_review.py',
    '/prompts/lesson_activity_generate.txt',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source(path):
    if path.startswith('/app/'):
        return ROOT / 'cmpys/backend' / path.removeprefix('/app/')
    assert path.startswith('/prompts/')
    return ROOT / 'cmpys/prompts' / path.removeprefix('/prompts/')


def test_inputs(root):
    return {str(path.relative_to(root)): digest(path)
            for path in root.rglob('*')
            if path.is_file() and path.suffix not in {'.pyc', '.pyo'}
            and not {'__pycache__', '.pytest_cache'} & set(path.relative_to(root).parts)}


def main():
    baseline = json.loads((EVIDENCE / '2026-10-17-staged-v23-manifest.json').read_text())
    current = {path: digest(source(path)) for path in baseline}
    changed = {path for path in baseline if current[path] != baseline[path]}
    assert changed <= ALLOWED_CHANGED, 'Unreviewed runtime changes: ' + repr(sorted(changed - ALLOWED_CHANGED))
    test_root = ROOT / 'cmpys/backend/tests'
    modules = sorted(path.name for path in test_root.glob('test_*.py')
                     if path.name.startswith(TEST_PREFIXES + ('test_evidence_',))
                     and path.name not in EXCLUDED_IMAGE_TESTS)
    test_hashes = test_inputs(test_root)
    image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', BASE], timeout=30))[0]
    assert BASE in image['RepoDigests'] and image['Architecture'] == 'arm64'
    verify = ('import hashlib; from pathlib import Path; m=' + repr(baseline) +
              '; assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in m.items())')
    subprocess.run(['docker', 'run', '--rm', '--pull=never', '--network=none', '--read-only',
                    '--entrypoint', 'python', image['Id'], '-c', verify], check=True, timeout=30)
    command = ['docker', 'run', '--rm', '--pull=never', '--network=none', '--read-only',
               '--tmpfs', '/tmp', '-v', str(test_root) + ':/app/tests:ro']
    for path in sorted(changed):
        command.extend(['-v', str(source(path)) + ':' + path + ':ro'])
    command.extend(['-e', 'LLM_PROVIDER=dummy', '-e', 'BOOK_NARRATION_ENABLED=false',
                    '-e', 'PYTHONDONTWRITEBYTECODE=1', '-e', 'PYTHONPATH=/app',
                    '--entrypoint', 'python', image['Id'], '-m', 'pytest', '-q', '--tb=short',
                    '-p', 'no:cacheprovider', *['tests/' + name for name in modules]])
    log_path = EVIDENCE / '2026-10-17-offline-followup-image-tests.log'
    started = time.monotonic()
    with log_path.open('w') as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=240)
    assert all(digest(source(path)) == expected for path, expected in current.items()), 'Runtime source changed during test'
    assert test_hashes == test_inputs(test_root), 'Tests or fixtures changed during run'
    report = {
        'status': 'passed' if result.returncode == 0 else 'failed',
        'scope': 'local source mounts on deployed image dependencies; not a new release image',
        'provider': 'dummy', 'network': 'none', 'read_only': True,
        'provider_calls': 0, 'deployment_performed': False,
        'base_digest': BASE.split('@')[1], 'base_image_id': image['Id'],
        'runtime_manifest': current, 'changed_files': sorted(changed),
        'test_manifest': test_hashes, 'test_modules': modules,
        'excluded_test_modules': EXCLUDED_IMAGE_TESTS,
        'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic() - started, 2),
        'log': log_path.name,
    }
    (EVIDENCE / '2026-10-17-offline-followup-image-verification.json').write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: report[key] for key in ('status', 'scope', 'exit_code', 'elapsed_seconds', 'changed_files')}))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
