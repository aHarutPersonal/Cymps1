#!/usr/bin/env bash
set -euo pipefail

SERVER="root@54.158.122.215"
REMOTE_DIR="/opt/cmpys"
IMAGE="cmpys-backend"
TAG="$(date +%Y%m%d-%H%M%S)"

echo "==> Building Docker image ${IMAGE}:${TAG}"
cd "$(dirname "$0")/.."
docker build -f backend/Dockerfile -t "${IMAGE}:${TAG}" -t "${IMAGE}:latest" .

echo "==> Saving image"
docker save "${IMAGE}:${TAG}" | gzip > /tmp/cmpys-backend.tar.gz

echo "==> Uploading to ${SERVER}"
scp /tmp/cmpys-backend.tar.gz "${SERVER}:/tmp/cmpys-backend.tar.gz"

echo "==> Deploying on server"
ssh "${SERVER}" bash -s "${IMAGE}" "${TAG}" "${REMOTE_DIR}" <<'REMOTE'
set -euo pipefail
IMAGE="$1"; TAG="$2"; DIR="$3"

echo "  Loading image..."
docker load < /tmp/cmpys-backend.tar.gz
rm -f /tmp/cmpys-backend.tar.gz

echo "  Running migrations..."
docker run --rm --env-file "${DIR}/.env" "${IMAGE}:${TAG}" migrate

echo "  Stopping old container..."
docker stop cmpys-backend 2>/dev/null || true
docker rm cmpys-backend 2>/dev/null || true

echo "  Starting new container..."
docker run -d \
  --name cmpys-backend \
  --restart unless-stopped \
  --env-file "${DIR}/.env" \
  -p 8000:8000 \
  "${IMAGE}:${TAG}" web

echo "  Waiting for health check..."
for i in $(seq 1 15); do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "  Healthy!"
    exit 0
  fi
  sleep 2
done

echo "  ERROR: health check failed after 30s"
docker logs --tail 30 cmpys-backend
exit 1
REMOTE

rm -f /tmp/cmpys-backend.tar.gz
echo "==> Deploy complete: ${IMAGE}:${TAG}"
