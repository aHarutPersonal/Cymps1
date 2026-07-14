#!/usr/bin/env bash
set -euo pipefail

SERVER="ec2-user@54.158.122.215"
REMOTE_DIR="/opt/cmpys"
IMAGE="cmpys-backend"
TAG="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="/tmp/cmpys-backend-${TAG}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_DIR}/infra/docker-compose.prod.yml"

cleanup() {
  rm -f "${ARCHIVE}"
}
trap cleanup EXIT

REMOTE_ARCH="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${SERVER}" uname -m)"
case "${REMOTE_ARCH}" in
  aarch64|arm64) TARGET_PLATFORM="linux/arm64" ;;
  x86_64|amd64) TARGET_PLATFORM="linux/amd64" ;;
  *) echo "Unsupported server architecture: ${REMOTE_ARCH}" >&2; exit 1 ;;
esac

echo "==> Building Docker image ${IMAGE}:${TAG} for ${TARGET_PLATFORM}"
cd "${PROJECT_DIR}"
docker build \
  --platform "${TARGET_PLATFORM}" \
  -f backend/Dockerfile \
  -t "${IMAGE}:${TAG}" \
  .

echo "==> Saving image"
docker save "${IMAGE}:${TAG}" | gzip > "${ARCHIVE}"

echo "==> Uploading image and Compose release"
scp "${ARCHIVE}" "${SERVER}:/tmp/cmpys-backend-${TAG}.tar.gz"
scp "${COMPOSE_FILE}" "${SERVER}:/tmp/cmpys-compose-${TAG}.yml"

echo "==> Deploying release ${TAG}"
ssh "${SERVER}" bash -s "${IMAGE}" "${TAG}" "${REMOTE_DIR}" <<'REMOTE'
set -euo pipefail
IMAGE="$1"
TAG="$2"
DIR="$3"
ENV_FILE="${DIR}/.env"
COMPOSE_FILE="${DIR}/docker-compose.prod.yml"
COMPOSE_BACKUP="${DIR}/docker-compose.prod.yml.rollback-${TAG}"
INCOMING_COMPOSE="/tmp/cmpys-compose-${TAG}.yml"
ARCHIVE="/tmp/cmpys-backend-${TAG}.tar.gz"
ROLLBACK_ARMED=false
COMPOSE_REPLACED=false
RELEASE_SERVICES=(web worker catalog-worker catalog-control beat)

compose() {
  docker compose -p cmpys --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

rollback_release() {
  trap - ERR
  echo "  Rolling back release..."
  if [[ -f "${COMPOSE_BACKUP}" ]]; then
    cp "${COMPOSE_BACKUP}" "${COMPOSE_FILE}"
  fi
  if [[ "${ROLLBACK_ARMED}" == "true" ]]; then
    IMAGE_TAG="${PREVIOUS_TAG}" compose up -d --force-recreate \
      "${RELEASE_SERVICES[@]}" || true
  fi
}

service_container() {
  compose ps -q "$1"
}

service_is_running() {
  local service="$1"
  local container
  container="$(service_container "${service}")"
  [[ -n "${container}" ]] &&
    [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" == "true" ]] &&
    [[ "$(docker inspect -f '{{.State.Restarting}}' "${container}" 2>/dev/null)" == "false" ]]
}

wait_for_celery_worker() {
  local service="$1"
  local expected_queue="$2"
  local container node ping_output queue_output

  for _ in $(seq 1 15); do
    container="$(service_container "${service}")"
    if [[ -n "${container}" ]] && service_is_running "${service}"; then
      node="celery@$(docker exec "${container}" hostname 2>/dev/null)"
      ping_output="$(
        docker exec "${container}" \
          celery -A app.core.celery.celery_app inspect ping \
          --destination "${node}" --timeout=5 2>/dev/null || true
      )"
      queue_output="$(
        docker exec "${container}" \
          celery -A app.core.celery.celery_app inspect active_queues \
          --destination "${node}" --timeout=5 2>/dev/null || true
      )"
      if grep -q "pong" <<<"${ping_output}" &&
        grep -q "'name': '${expected_queue}'" <<<"${queue_output}"; then
        return 0
      fi
    fi
    sleep 2
  done

  echo "  ERROR: ${service} did not become a healthy ${expected_queue} consumer" >&2
  compose logs --tail 60 "${service}" >&2 || true
  return 1
}

on_deploy_error() {
  EXIT_CODE=$?
  if [[ "${COMPOSE_REPLACED}" == "true" ]]; then
    rollback_release
  fi
  rm -f "${ARCHIVE}" "${INCOMING_COMPOSE}"
  exit "${EXIT_CODE}"
}
trap on_deploy_error ERR

if [[ ! -f "${ENV_FILE}" || ! -f "${COMPOSE_FILE}" ]]; then
  echo "  ERROR: production .env or Compose file is missing" >&2
  exit 1
fi

REMOTE_IMAGE="$(sed -n 's/^ECR_URL=//p' "${ENV_FILE}" | tail -1)"
PREVIOUS_TAG="$(sed -n 's/^IMAGE_TAG=//p' "${ENV_FILE}" | tail -1)"
PREVIOUS_TAG="${PREVIOUS_TAG:-latest}"
if [[ -z "${REMOTE_IMAGE}" ]]; then
  echo "  ERROR: ECR_URL is missing from production .env" >&2
  exit 1
fi

if ! grep -q '^JWT_SECRET_KEY=' "${ENV_FILE}"; then
  echo "  Adding missing JWT signing secret..."
  umask 077
  printf '\nJWT_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" >> "${ENV_FILE}"
fi

cp "${COMPOSE_FILE}" "${COMPOSE_BACKUP}"
cp "${INCOMING_COMPOSE}" "${COMPOSE_FILE}"
COMPOSE_REPLACED=true

echo "  Loading and tagging image..."
docker load < "${ARCHIVE}"
docker tag "${IMAGE}:${TAG}" "${REMOTE_IMAGE}:${TAG}"

echo "  Validating Compose configuration..."
IMAGE_TAG="${TAG}" compose config --quiet

echo "  Running migrations before switching traffic..."
IMAGE_TAG="${TAG}" compose run --rm -T migrate </dev/null

echo "  Recreating API, interactive workers, catalog workers, and beat..."
ROLLBACK_ARMED=true
IMAGE_TAG="${TAG}" compose up -d --force-recreate "${RELEASE_SERVICES[@]}"

echo "  Waiting for API readiness..."
READY=false
for _ in $(seq 1 30); do
  if curl -sf http://localhost:8000/ready >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 2
done
if [[ "${READY}" != "true" ]]; then
  echo "  ERROR: readiness check failed after 60s" >&2
  docker logs --tail 60 cmpys-web-1 2>/dev/null || true
  false
fi

for SERVICE in "${RELEASE_SERVICES[@]}"; do
  if ! service_is_running "${SERVICE}"; then
    echo "  ERROR: ${SERVICE} is not running" >&2
    compose logs --tail 60 "${SERVICE}" >&2 || true
    false
  fi
done

echo "  Checking Celery workers and queue bindings..."
wait_for_celery_worker "worker" "default"
wait_for_celery_worker "catalog-worker" "catalog"
wait_for_celery_worker "catalog-control" "catalog_control"

if grep -q '^IMAGE_TAG=' "${ENV_FILE}"; then
  sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=${TAG}/" "${ENV_FILE}"
  rm -f "${ENV_FILE}.bak"
else
  printf '\nIMAGE_TAG=%s\n' "${TAG}" >> "${ENV_FILE}"
fi

ROLLBACK_ARMED=false
COMPOSE_REPLACED=false
rm -f "${COMPOSE_BACKUP}" "${ARCHIVE}" "${INCOMING_COMPOSE}"
echo "  Ready: API, PostgreSQL, Redis, all workers, and beat are healthy."
REMOTE

echo "==> Deploy complete: ${IMAGE}:${TAG}"
