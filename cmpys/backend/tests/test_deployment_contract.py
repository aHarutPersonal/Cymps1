from __future__ import annotations

import re
import shlex
import subprocess
from pathlib import Path

import pytest

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
    "curriculum-worker",
    "curriculum-control",
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
        assert 'wait_for_celery_worker "curriculum-worker" "curriculum"' in script
        assert (
            'wait_for_celery_worker "curriculum-control" "curriculum_control"'
            in script
        )
        assert 'docker top "$container" -eo pid,args' in script or (
            'docker top "${container}" -eo pid,args' in script
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
        '"ec2-user@$SERVER_IP" "$REMOTE_COMMAND"'
    )
    assert "workflow_dispatch:" in workflow
    assert 'image: pgvector/pgvector:pg16' in workflow
    assert "python -m alembic upgrade head" in workflow
    assert "python -m pytest -q" in workflow
    assert "--ignore=tests/test_catalog_migration.py" not in workflow
    assert '- "cmpys/prompts/**"' in workflow
    assert '"ec2-user@$SERVER_IP:$RELEASE_DIR/"' in workflow
    assert "mktemp -d /tmp/cmpys-release-$IMAGE_TAG.XXXXXX" in workflow
    assert "ec2-user@$SERVER_IP:/opt/cmpys/" not in workflow
    assert "cp /opt/cmpys/docker-compose.prod.yml" not in workflow
    assert '"$RELEASE_DIR/docker-compose.prod.yml"' in workflow
    assert script.index("if grep -q '^IMAGE_TAG='") > script.index(
        'wait_for_celery_worker "catalog-control" "catalog_control"'
    )


def test_deploy_quiesces_old_writers_and_restores_matching_topology() -> None:
    for path in DEPLOY_SCRIPTS:
        script = path.read_text()

        stop_index = script.index("compose stop")
        migration_index = script.index("compose run --rm -T migrate")
        start_index = script.index("compose up -d", migration_index)
        assert stop_index < migration_index < start_index
        assert 'wait_for_web' in script
        assert 'verify_configured_workers' in script
        assert 'automatic rollback failed; operator recovery is required' in script
        assert '"${rollback_services[@]}" || true' not in script

    infra_script = (PROJECT_ROOT / "infra" / "deploy.sh").read_text()
    assert 'cp "$COMPOSE_BACKUP" "$COMPOSE"' in infra_script
    assert 'rm -f "$COMPOSE_BACKUP"' not in infra_script


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
    assert "curriculum-worker:" in compose
    assert "curriculum-control:" in compose


def test_small_host_uses_single_process_workers_and_cpu_priority() -> None:
    entrypoint = (PROJECT_ROOT / "backend" / "docker-entrypoint.sh").read_text()
    compose = (PROJECT_ROOT / "infra" / "docker-compose.prod.yml").read_text()

    assert '--pool="${CELERY_DEFAULT_POOL:-solo}"' in entrypoint
    assert '--concurrency="${CELERY_DEFAULT_CONCURRENCY:-1}"' in entrypoint
    assert '--pool="${CATALOG_WORKER_POOL:-solo}"' in entrypoint
    assert '--concurrency="${CATALOG_WORKER_CONCURRENCY:-1}"' in entrypoint
    assert '--pool="${CURRICULUM_WORKER_POOL:-prefork}"' in entrypoint
    assert '--concurrency="${CURRICULUM_WORKER_CONCURRENCY:-1}"' in entrypoint
    assert "cpu_shares: 2048" in compose
    assert "cpu_shares: 1536" in compose
    assert "cpu_shares: 256" in compose
    assert "CATALOG_DISPATCH_PER_TICK:-1" in compose


def test_local_stack_starts_and_monitors_curriculum_workers() -> None:
    launcher = (PROJECT_ROOT.parent / "start_app.sh").read_text()

    assert "CURRICULUM_WORKER_PID=$!" in launcher
    assert "CURRICULUM_CONTROL_PID=$!" in launcher
    assert "-Q curriculum" in launcher
    assert "-Q curriculum_control" in launcher
    assert 'kill -0 "$CURRICULUM_WORKER_PID"' in launcher
    assert 'kill -0 "$CURRICULUM_CONTROL_PID"' in launcher
    assert '[ "$PONG_COUNT" -ge 5 ]' in launcher


def test_production_curriculum_safety_limits_are_explicit() -> None:
    compose = (PROJECT_ROOT / "infra" / "docker-compose.prod.yml").read_text()
    assert "CURRICULUM_MAX_RUNNING_JOBS" in compose
    assert "CURRICULUM_JOB_BUDGET_USD" in compose
    assert "CURRICULUM_DURABLE_SPACING_SCHEDULER_ENABLED" in compose


def test_checked_in_env_example_matches_the_settings_schema() -> None:
    from app.core.config import Settings

    configured = Settings(_env_file=PROJECT_ROOT / "backend" / ".env.example")
    assert configured.curriculum_worker_pool
    assert configured.curriculum_worker_concurrency > 0
    assert configured.curriculum_control_pool


def test_all_live_compose_writes_happen_under_shared_host_lock() -> None:
    for path in DEPLOY_SCRIPTS:
        script = path.read_text()
        lock = script.index("flock -n 9")
        live_copy = re.search(r'^cp .*\$(?:\{)?INCOMING_COMPOSE', script, re.MULTILINE)
        assert live_copy is not None
        assert lock < live_copy.start()
        backup = re.search(r'^cp .*\$(?:\{)?COMPOSE(?:_FILE)?', script, re.MULTILINE)
        assert backup is not None
        assert lock < backup.start() < live_copy.start()
        assert "docker image prune" not in script
        rollback = re.search(r'^rollback_release\(\) \{.*?^\}', script, re.MULTILINE | re.DOTALL)
        assert rollback is not None
        assert "compose up -d --no-deps --force-recreate" in rollback.group()
        assert '"${rollback_services[@]}" || return 1' in rollback.group()


@pytest.mark.parametrize("path", DEPLOY_SCRIPTS, ids=["manual", "ci"])
@pytest.mark.parametrize("armed,compose_fails", [(False, False), (True, False), (True, True)])
def test_rollback_restores_topology_and_reports_restart_failure(tmp_path, path, armed, compose_fails):
    """Exercise the real rollback body with harmless service stand-ins."""
    script = path.read_text()
    rollback = re.search(r'^rollback_release\(\) \{.*?^\}', script, re.MULTILINE | re.DOTALL)
    assert rollback is not None
    live = tmp_path / "compose.yml"
    backup = tmp_path / "compose.previous.yml"
    live.write_text("new release")
    backup.write_text("previous release")
    # The production host uses Bash 4+. Supply the one mapfile operation for
    # macOS's Bash 3 so these isolated failure checks run on both platforms.
    setup = f"""
set -e
COMPOSE={shlex.quote(str(live))}
COMPOSE_FILE="$COMPOSE"
COMPOSE_BACKUP={shlex.quote(str(backup))}
COMPOSE_REPLACED=true
ROLLBACK_ARMED={str(armed).lower()}
PREVIOUS_TAG=old
RELEASE_SERVICES=(web)
mapfile() {{ rollback_services=(web); }}
configured_release_services() {{ echo web; }}
service_container() {{ echo current-web; }}
compose() {{ return {1 if compose_fails else 0}; }}
wait_for_web() {{ return 0; }}
service_is_running() {{ return 0; }}
verify_configured_workers() {{ return 0; }}
"""
    result = subprocess.run(
        ["bash", "-c", setup + rollback.group() + "\nif rollback_release; then exit 0; else exit 17; fi\n"],
        capture_output=True, text=True, timeout=5,
    )
    assert result.returncode == (17 if armed and compose_fails else 0), result.stderr
    assert live.read_text() == "previous release"
    assert backup.read_text() == "previous release"
