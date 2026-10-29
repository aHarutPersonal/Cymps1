"""Freeze and test a COPY-only release overlay on the verified v21 image.

This helper never pushes, deploys, changes configuration or calls a provider.
Run freeze only after runtime owners and independent review have finished.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = ('297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend@'
        'sha256:97e972c16a39963bc544ee3860ebc6ce51605dba20192df5cfae95ae55a86d73')
REPOSITORY = BASE.split('@')[0]
STAGE = Path('/private/tmp/cmpys-staged-v22-20261017-final')
ADDED = ('/app/app/services/planning/activity_draft.py',)
ALLOWED_CHANGED = {
    '/app/app/services/planning/package_builder.py',
    '/app/app/services/planning/lesson_package.py',
    '/prompts/lesson_activity_generate.txt',
    '/prompts/lesson_package_generate.txt',
}
TEST_PREFIXES = ('test_activity_', 'test_armenian_', 'test_checkpoint_', 'test_choice_',
    'test_compact_', 'test_compiled_', 'test_component_', 'test_deadline_', 'test_detail_job_',
    'test_geometry_', 'test_json_', 'test_lesson_', 'test_math_', 'test_numeric_',
    'test_package_', 'test_pilot_', 'test_preflight_', 'test_previous_release_',
    'test_private_', 'test_ready_lesson_', 'test_repaired_', 'test_restore_',
    'test_review_', 'test_scoped_', 'test_seed_', 'test_source_owned_', 'test_staged_',
    'test_structured_', 'test_text_activity_', 'test_transfer_', 'test_workload_')
EXCLUDED_IMAGE_TESTS = {
    'test_review_payload_projection.py': 'Optional unconnected prototype is not part of this release; covered by full workspace suite.'
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source(path):
    if path.startswith('/app/'):
        return ROOT / 'cmpys/backend' / path.removeprefix('/app/')
    assert path.startswith('/prompts/')
    return ROOT / 'cmpys/prompts' / path.removeprefix('/prompts/')

def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=240, **kwargs)

def info(image):
    return json.loads(subprocess.check_output(['docker', 'image', 'inspect', image], timeout=30))[0]

def verify_source(manifest):
    for path, expected in manifest.items():
        assert digest(source(path)) == expected, f'Changed source: {path}'
        assert digest(STAGE / 'context' / path.lstrip('/')) == expected, f'Changed freeze: {path}'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('freeze', 'build', 'test', 'verify'))
    parser.add_argument('--release')
    args = parser.parse_args()
    if args.action == 'freeze':
        assert args.release and args.release.startswith('20261017-') and '/' not in args.release
        prior = json.loads((ROOT / 'docs/releases/2026-10-17-staged-v21-manifest.json').read_text())
        manifest = {path: digest(source(path)) for path in sorted(set(prior) | set(ADDED))}
        changed = {path for path in prior if manifest[path] != prior[path]}
        assert changed <= ALLOWED_CHANGED, f'Unexpected changed release files: {sorted(changed - ALLOWED_CHANGED)}'
        STAGE.mkdir(exist_ok=False)
        for path, expected in manifest.items():
            target = STAGE / 'context' / path.lstrip('/')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source(path), target)
            assert digest(target) == expected
        shutil.copytree(ROOT / 'cmpys/backend/tests', STAGE / 'tests',
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        test_files = sorted(p.name for p in (STAGE / 'tests').glob('test_*.py')
                            if p.name.startswith(TEST_PREFIXES) and p.name not in EXCLUDED_IMAGE_TESTS)
        test_manifest = {str(p.relative_to(STAGE)): digest(p) for p in (STAGE / 'tests').rglob('*') if p.is_file()}
        metadata = {'release': args.release, 'base': BASE, 'image': REPOSITORY + ':' + args.release,
                    'manifest': manifest, 'test_files': test_files, 'test_manifest': test_manifest,
                    'excluded_image_tests': EXCLUDED_IMAGE_TESTS}
        (STAGE / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
        (STAGE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (STAGE / 'Dockerfile').write_text('FROM ' + BASE + '\nCOPY app/ /app/\nCOPY prompts/ /prompts/\n')
        verify_source(manifest)
        print(json.dumps({'frozen_files': len(manifest), 'test_modules': len(test_files), 'release': args.release}))
        return
    data = json.loads((STAGE / 'metadata.json').read_text())
    verify_source(data['manifest'])
    for path, expected in data['test_manifest'].items():
        assert digest(STAGE / path) == expected, f'Changed frozen test: {path}'
    if args.action == 'build':
        base = info(BASE)
        assert BASE in base['RepoDigests'] and base['Architecture'] == 'arm64'
        with (STAGE / 'build.log').open('w') as log:
            run(['docker', 'build', '--platform', 'linux/arm64', '--pull=false', '--network=none',
                 '-f', str(STAGE / 'Dockerfile'), '-t', data['image'], str(STAGE / 'context')],
                stdout=log, stderr=subprocess.STDOUT)
        candidate = info(data['image'])
        assert candidate['Config'] == base['Config'] and candidate['Architecture'] == 'arm64'
        data['image_id'] = candidate['Id']
        (STAGE / 'metadata.json').write_text(json.dumps(data, indent=2) + '\n')
    if args.action in ('build', 'verify', 'test'):
        candidate = info(data['image'])
        assert candidate['Id'] == data['image_id']
        code = ('import hashlib; from pathlib import Path; m=' + repr(data['manifest']) +
                '; assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in m.items())')
        run(['docker', 'run', '--rm', '--network', 'none', '--read-only', '--entrypoint', 'python',
             data['image_id'], '-c', code])
    if args.action == 'test':
        with (STAGE / 'image-tests.log').open('w') as log:
            run(['docker', 'run', '--rm', '--network', 'none', '--read-only', '--tmpfs', '/tmp',
                 '-v', str(STAGE / 'tests') + ':/app/tests:ro',
                 '-e', 'LLM_PROVIDER=dummy', '-e', 'BOOK_NARRATION_ENABLED=false',
                 '-e', 'PYTHONDONTWRITEBYTECODE=1', '-e', 'PYTHONPATH=/app',
                 '--entrypoint', 'python', data['image_id'], '-m', 'pytest', '-q', '--tb=short',
                 '-p', 'no:cacheprovider', *['tests/' + path for path in data['test_files']]],
                stdout=log, stderr=subprocess.STDOUT)
    verify_source(data['manifest'])
    print(json.dumps({'action': args.action, 'release': data['release'], 'image_id': data['image_id'],
                      'verified_files': len(data['manifest'])}))

if __name__ == '__main__':
    main()
