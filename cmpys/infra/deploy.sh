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

# Authenticate Docker with ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_URL"

# Pull the new image
docker pull "$ECR_URL:$IMAGE_TAG"
docker tag "$ECR_URL:$IMAGE_TAG" "$ECR_URL:latest"

# Run migration first (one-off container)
docker compose -f "$COMPOSE" --env-file "$ENV_FILE" \
  run --rm migrate

# Roll web + worker to the new image
docker compose -f "$COMPOSE" --env-file "$ENV_FILE" \
  up -d --no-deps web worker

# Gate success on web actually becoming healthy. `up -d` returns the moment the
# container *starts*, not when it serves traffic — without this a crash-looping
# image still reports a green deploy. Poll the in-container health endpoint and
# fail loudly (non-zero exit) if it never comes up, so the caller can roll back.
echo "Waiting for web to become healthy..."
for i in $(seq 1 30); do
  if docker compose -f "$COMPOSE" --env-file "$ENV_FILE" \
       exec -T web curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    echo "web is healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: web did not become healthy within 60s" >&2
    docker compose -f "$COMPOSE" --env-file "$ENV_FILE" logs --tail=40 web >&2
    exit 1
  fi
  sleep 2
done

# Clean up old images (dangling only) once the new one is confirmed good.
docker image prune -f

echo "Deploy complete: $ECR_URL:$IMAGE_TAG"
