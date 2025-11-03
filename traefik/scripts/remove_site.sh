#!/usr/bin/env bash
set -euo pipefail
: "${SITE_NAME:?SITE_NAME required}"
TARGET_DIR="${TARGET_DIR:-/opt/sites}"
BASE="${TARGET_DIR}/${SITE_NAME}"

# Ensure Docker available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi

# Check if the site exists
if [[ ! -f "${BASE}/docker-compose.yml" ]]; then
  echo "No docker-compose.yml found for site '${SITE_NAME}' in ${BASE}."
  exit 0
fi

echo "Stopping and removing ${SITE_NAME}..."

sudo docker compose -f "${BASE}/docker-compose.yml" down
sudo rm -rf "${BASE}"
echo "✅ Removed ${SITE_NAME}."