from __future__ import annotations

import re
import shlex
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEPLOY_SCRIPTS = (
    PROJECT_ROOT / "backend" / "deploy.sh",
    PROJECT_ROOT / "infra" / "deploy.sh",
)
EXPECTED_RELEASE_SERVICES = (
    "web",
    "worker",
    "worker-high",
    "worker-low",
    "catalog-worker",
    "catalog-control",
    "beat",
)


def _release_services(script: str) -> tuple[str, ...]:
    match = re.search(r"^RELEASE_SERVICES=\(([^)]*)\)$", script, re.MULTILINE)
    assert match is not None
    return tuple(shlex.split(match.group(1)))


def test_deploy_scripts_manage_and_verify_every_runtime_service() -> None:
    for path in DEPLOY_SCRIPTS:
        script = path.read_text()

        assert _release_services(script) == EXPECTED_RELEASE_SERVICES
        assert '"${RELEASE_SERVICES[@]}"' in script
        assert 'wait_for_celery_worker "worker" "default"' in script
        assert 'wait_for_celery_worker "worker-high" "high_priority"' in script
        assert 'wait_for_celery_worker "worker-low" "low_priority"' in script
        assert 'wait_for_celery_worker "catalog-worker" "catalog"' in script
        assert 'wait_for_celery_worker "catalog-control" "catalog_control"' in script
        assert "rollback_release" in script
        assert "ROLLBACK_ARMED=true" in script


def test_deploy_scripts_have_valid_bash_syntax() -> None:
    for path in DEPLOY_SCRIPTS:
        subprocess.run(["bash", "-n", str(path)], check=True)


def test_interactive_queues_have_reserved_worker_roles() -> None:
    entrypoint = (PROJECT_ROOT / "backend" / "docker-entrypoint.sh").read_text()
    compose = (PROJECT_ROOT / "infra" / "docker-compose.prod.yml").read_text()

    assert "worker)  exec celery" in entrypoint
    assert "-Q default" in entrypoint
    assert "worker-high) exec celery" in entrypoint
    assert "-Q high_priority" in entrypoint
    assert "worker-low) exec celery" in entrypoint
    assert "-Q low_priority" in entrypoint
    assert "worker-high:" in compose
    assert "worker-low:" in compose
