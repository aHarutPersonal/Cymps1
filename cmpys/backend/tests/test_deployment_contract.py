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
        assert 'docker top "$container" -eo args' in script or (
            'docker top "${container}" -eo args' in script
        )
        assert "inspect active_queues" not in script
        assert "rollback_release" in script
        assert "ROLLBACK_ARMED=true" in script


def test_deploy_scripts_have_valid_bash_syntax() -> None:
    for path in DEPLOY_SCRIPTS:
        subprocess.run(["bash", "-n", str(path)], check=True)


def test_ci_serializes_deploys_and_promotes_latest_only_after_health() -> None:
    workflow = (PROJECT_ROOT.parent / ".github" / "workflows" / "deploy.yml").read_text()
    script = (PROJECT_ROOT / "infra" / "deploy.sh").read_text()

    assert "group: cmpys-production-deploy" in workflow
    assert "cancel-in-progress: false" in workflow
    assert "-t $ECR_URL:latest" not in workflow
    assert 'flock -n 9' in script
    assert 'docker push "$ECR_URL:latest"' not in script
    assert "docker buildx imagetools create" in workflow
    assert workflow.index("docker buildx imagetools create") > workflow.index(
        "/opt/cmpys/deploy.sh $ECR_URL $IMAGE_TAG"
    )
    assert script.index("if grep -q '^IMAGE_TAG='") > script.index(
        'wait_for_celery_worker "catalog-control" "catalog_control"'
    )


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


def test_small_host_uses_single_process_workers_and_cpu_priority() -> None:
    entrypoint = (PROJECT_ROOT / "backend" / "docker-entrypoint.sh").read_text()
    compose = (PROJECT_ROOT / "infra" / "docker-compose.prod.yml").read_text()

    assert '--pool="${CELERY_DEFAULT_POOL:-solo}"' in entrypoint
    assert '--concurrency="${CELERY_DEFAULT_CONCURRENCY:-1}"' in entrypoint
    assert '--pool="${CATALOG_WORKER_POOL:-solo}"' in entrypoint
    assert '--concurrency="${CATALOG_WORKER_CONCURRENCY:-1}"' in entrypoint
    assert "cpu_shares: 2048" in compose
    assert "cpu_shares: 1536" in compose
    assert "cpu_shares: 256" in compose
    assert "CATALOG_DISPATCH_PER_TICK:-1" in compose
