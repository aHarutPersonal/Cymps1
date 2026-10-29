"""Run the backend suite against the existing isolated local test database."""
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import quote

def main():
    container = json.loads(subprocess.check_output([
        'docker', 'inspect', 'cmpys-generation-review-pg-20261016']))[0]
    assert container['State']['Running']
    port = container['NetworkSettings']['Ports']['5432/tcp'][0]
    assert port['HostIp'] == '127.0.0.1'
    values = dict(value.split('=', 1) for value in container['Config']['Env'] if '=' in value)
    dsn = ('postgresql+psycopg://' + quote(values['POSTGRES_USER'], safe='') + ':' +
           quote(values['POSTGRES_PASSWORD'], safe='') + '@127.0.0.1:' + port['HostPort'] +
           '/' + quote(values['POSTGRES_DB'], safe=''))
    env = dict(os.environ, DATABASE_URL=dsn, PRIVATE_CHECKPOINT_TEST_DATABASE_URL=dsn,
               LLM_PROVIDER='dummy', BOOK_NARRATION_ENABLED='false')
    root = Path(__file__).resolve().parents[3] / 'cmpys' / 'backend'
    with Path('/private/tmp/cmpys-backend-offline-tests.log').open('w') as output:
        result = subprocess.run(['.venv/bin/python', '-m', 'pytest', '-q', '--tb=short', *sys.argv[1:]],
                                cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT,
                                timeout=240)
    print(json.dumps({'exit_code': result.returncode, 'database': 'isolated_local_test_container',
                      'provider': 'dummy'}))
    raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()
