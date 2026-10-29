"""Read-only verification; execute on the deployment host after rollout."""
import hashlib
import json
import subprocess
from pathlib import Path

RELEASE = '20261016-153858-scoped-preflight'
DIGEST = 'sha256:1eafe22d991943427ccb28eee78bff5ef09c455c22400145cf4ffaa55063613e'
REGISTRY = '297601879897.dkr.ecr.us-east-1.amazonaws.com/cmpys-backend'

def main():
    manifest = json.loads((Path('/opt/cmpys/releases') / RELEASE / 'manifest.json').read_text())
    image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', REGISTRY + ':' + RELEASE]))[0]
    assert REGISTRY + '@' + DIGEST in image['RepoDigests']
    assert image['Architecture'] == 'arm64'
    services = ['web', 'worker', 'worker-high', 'worker-low', 'catalog-worker', 'catalog-control',
                'curriculum-worker', 'curriculum-control', 'beat']
    code = ('import hashlib;from pathlib import Path;m=' + repr(manifest) +
            ';assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in m.items())')
    for service in services:
        name = 'cmpys-' + service + '-1'
        data = json.loads(subprocess.check_output(['docker', 'inspect', name]))[0]
        assert data['State']['Running'] and not data['State']['Restarting'] and data['Image'] == image['Id'], service
        subprocess.run(['docker', 'exec', name, 'python', '-c', code], check=True, timeout=20)
    assert 'IMAGE_TAG=' + RELEASE in Path('/opt/cmpys/.env').read_text().splitlines()
    print(json.dumps({'release': RELEASE, 'image_digest': DIGEST, 'verified_services': services,
                      'verified_files': len(manifest), 'file_hashes_verified_in_every_service': True}))

if __name__ == '__main__':
    main()
