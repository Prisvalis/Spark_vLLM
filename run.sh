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

echo "Download Harmony..."
cd docker
mkdir -p tiktoken_encodings
wget -O tiktoken_encodings/o200k_base.tiktoken "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"
wget -O tiktoken_encodings/cl100k_base.tiktoken "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken"

echo "Starting Docker environment..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d