#!/usr/bin/env bash
# Runs on the EC2 server. Called by GitHub Actions via SSH.
# Usage: ./deploy.sh <ecr-url> <image-tag> <aws-region>
set -euo pipefail

ECR_URL="${1:?ECR_URL required}"
IMAGE_TAG="${2:-latest}"
AWS_REGION="${3:-us-east-1}"

APP_DIR="/opt/cmpys"
ENV_FILE="$APP_DIR/.env"
COMPOSE="$APP_DIR/docker-compose.prod.yml"
RELEASE_SERVICES=(web worker worker-high worker-low catalog-worker catalog-control beat)
PREVIOUS_TAG="$(sed -n 's/^IMAGE_TAG=//p' "$ENV_FILE" | tail -1)"
PREVIOUS_TAG="${PREVIOUS_TAG:-latest}"
ROLLBACK_ARMED=false

compose() {
  docker compose -p cmpys -f "$COMPOSE" --env-file "$ENV_FILE" "$@"
}

configured_release_services() {
  local configured service
  configured="$(compose config --services 2>/dev/null || true)"
  for service in "${RELEASE_SERVICES[@]}"; do
    if grep -Fxq "$service" <<<"$configured"; then
      printf '%s\n' "$service"
    fi
  done
}

rollback_release() {
  local rollback_services=()
  trap - ERR
  if [[ "$ROLLBACK_ARMED" == "true" ]]; then
    mapfile -t rollback_services < <(configured_release_services)
    echo "Rolling back services to $PREVIOUS_TAG..." >&2
    IMAGE_TAG="$PREVIOUS_TAG" compose up -d --no-deps --force-recreate \
      "${rollback_services[@]}" || true
  fi
}

on_deploy_error() {
  local exit_code=$?
  rollback_release
  exit "$exit_code"
}

trap on_deploy_error ERR

service_container() {
  compose ps -q "$1"
}

service_is_running() {
  local service="$1"
  local container
  container="$(service_container "$service")"
  [[ -n "$container" ]] &&
    [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]] &&
    [[ "$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null)" == "false" ]]
}

wait_for_celery_worker() {
  local service="$1"
  local expected_queue="$2"
  local container node ping_output queue_output

  for _ in $(seq 1 15); do
    container="$(service_container "$service")"
    if [[ -n "$container" ]] && service_is_running "$service"; then
      node="celery@$(docker exec "$container" hostname 2>/dev/null)"
      ping_output="$(
        docker exec "$container" \
          celery -A app.core.celery.celery_app inspect ping \
          --destination "$node" --timeout=5 2>/dev/null || true
      )"
      queue_output="$(
        docker exec "$container" \
          celery -A app.core.celery.celery_app inspect active_queues \
          --destination "$node" --timeout=5 2>/dev/null || true
      )"
      if grep -q "pong" <<<"$ping_output" &&
        grep -q "'name': '$expected_queue'" <<<"$queue_output"; then
        return 0
      fi
    fi
    sleep 2
  done

  echo "ERROR: $service did not become a healthy $expected_queue consumer" >&2
  compose logs --tail=60 "$service" >&2 || true
  return 1
}

# Authenticate Docker with ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_URL"

# Pull the new image
docker pull "$ECR_URL:$IMAGE_TAG"

# Run migration first (one-off container)
IMAGE_TAG="$IMAGE_TAG" compose run --rm -T migrate </dev/null

# Roll every runtime service to the new image. Book requests first enter the
# catalog_control queue, then move to the catalog queue, so both dedicated
# workers are part of the deployment contract rather than optional extras.
ROLLBACK_ARMED=true
IMAGE_TAG="$IMAGE_TAG" compose up -d --no-deps --force-recreate \
  "${RELEASE_SERVICES[@]}"

# Gate success on web actually becoming healthy. `up -d` returns the moment the
# container *starts*, not when it serves traffic — without this a crash-looping
# image still reports a green deploy. Poll the in-container health endpoint and
# fail loudly (non-zero exit) if it never comes up, so the caller can roll back.
echo "Waiting for web to become healthy..."
for i in $(seq 1 30); do
  if compose exec -T web curl -sf http://localhost:8000/ready >/dev/null 2>&1; then
    echo "web is healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: web did not become healthy within 60s" >&2
    compose logs --tail=40 web >&2
    exit 1
  fi
  sleep 2
done

for service in "${RELEASE_SERVICES[@]}"; do
  if ! service_is_running "$service"; then
    echo "ERROR: $service is not running" >&2
    compose logs --tail=60 "$service" >&2 || true
    exit 1
  fi
done

echo "Checking Celery workers and queue bindings..."
wait_for_celery_worker "worker" "default"
wait_for_celery_worker "worker-high" "high_priority"
wait_for_celery_worker "worker-low" "low_priority"
wait_for_celery_worker "catalog-worker" "catalog"
wait_for_celery_worker "catalog-control" "catalog_control"

# Persist the successful release only after every service and queue consumer
# has passed its health check. Until this point the previous tag remains the
# rollback target, and :latest still refers to the previous successful image.
if grep -q '^IMAGE_TAG=' "$ENV_FILE"; then
  sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
else
  printf '\nIMAGE_TAG=%s\n' "$IMAGE_TAG" >> "$ENV_FILE"
fi
docker tag "$ECR_URL:$IMAGE_TAG" "$ECR_URL:latest"
ROLLBACK_ARMED=false
trap - ERR

# Clean up old images (dangling only) once the new one is confirmed good.
docker image prune -f

echo "Deploy complete: $ECR_URL:$IMAGE_TAG"
