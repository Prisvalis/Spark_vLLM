#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker/docker-compose.yml"
ENV_FILE=".env"

# Load .env into this shell too, in case other parts of the script need the values directly
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

echo "Stopping any existing containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down

echo "Starting Docker environment..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d