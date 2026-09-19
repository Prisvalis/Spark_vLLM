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

TIKTOKEN_DIR="docker/tiktoken_encodings"
TIKTOKEN_URL="https://openaipublic.blob.core.windows.net/encodings"

# Skip if $1 already exists and is non-empty (a failed `wget -O` leaves an empty file behind).
# Download to a temp file first so an interrupted download never leaves a broken file in place.
download_if_missing() {
  local dest="$1" url="$2" tmp="$1.part"
  if [[ -s "$dest" ]]; then
    echo "  $dest already exists, skipping"
    return 0
  fi
  echo "  Downloading $url"
  if ! wget -O "$tmp" "$url"; then
    rm -f "$tmp"
    echo "Failed to download $url" >&2
    return 1
  fi
  mv "$tmp" "$dest"
}

echo "Download Harmony..."
mkdir -p "$TIKTOKEN_DIR"
download_if_missing "$TIKTOKEN_DIR/o200k_base.tiktoken" "$TIKTOKEN_URL/o200k_base.tiktoken"
download_if_missing "$TIKTOKEN_DIR/cl100k_base.tiktoken" "$TIKTOKEN_URL/cl100k_base.tiktoken"

echo "Starting Docker environment..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d