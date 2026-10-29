"""Initialize only the newly approved private synthetic-test files; no provider calls."""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path('/opt/cmpys/releases/20261017-001200-structured-solutions')
SOURCE = Path('/opt/cmpys/releases/20261016-150539-validation-boundaries/generation_scenarios.json')
EXPECTED = '5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc'

def write_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())

def main():
    assert ROOT.is_dir() and not ROOT.is_symlink()
    assert SOURCE.is_file() and not SOURCE.is_symlink()
    fixture = SOURCE.read_bytes()
    assert hashlib.sha256(fixture).hexdigest() == EXPECTED
    output = ROOT / 'live-batch'
    assert not output.exists() and not output.is_symlink()
    target = ROOT / 'generation_scenarios.json'
    if target.exists():
        assert target.is_file() and not target.is_symlink() and target.read_bytes() == fixture
    else:
        write_new(target, fixture)
    output.mkdir(mode=0o700)
    authorization = {'max_tests': 6, 'shared_cap_usd': 1.97, 'owner_approved': True,
        'scope': 'synthetic accounting, geometry, writing across v21 and follow-up fixes',
        'ledger': str(output / 'usage.jsonl'), 'tests_reserved': 0, 'batches': []}
    write_new(output / 'usage.jsonl', b'')
    write_new(output / 'authorization.json', (json.dumps(authorization, sort_keys=True, indent=2) + '\n').encode())
    print(json.dumps({'status': 'prepared_not_launched', 'max_tests': 6, 'shared_cap_usd': 1.97, 'tests_reserved': 0}))

if __name__ == '__main__':
    main()
