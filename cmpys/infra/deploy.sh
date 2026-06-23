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

# Clean up old images
docker image prune -f

echo "Deploy complete: $ECR_URL:$IMAGE_TAG"
