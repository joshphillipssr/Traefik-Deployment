#!/usr/bin/env bash
set -euo pipefail
# Update a deployed site by pulling the latest image and recreating the stack.
#
# Required:
#   SITE_NAME="shortname"
# Optional:
#   TARGET_DIR="/opt/sites" (default)
#
# Example:
#   SITE_NAME="jpsr" ./traefik/scripts/update_site.sh

SITE_NAME="${SITE_NAME:-${1:-}}"
: "${SITE_NAME:?SITE_NAME required}"
TARGET_DIR="${TARGET_DIR:-/opt/sites}"
BASE="${TARGET_DIR}/${SITE_NAME}"

# Ensure Docker available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot talk to the Docker daemon. Ensure your user is in the 'docker' group." >&2
  exit 1
fi

COMPOSE_FILE="${BASE}/docker-compose.yml"
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "No docker-compose.yml found for site '${SITE_NAME}' in ${BASE}."
  exit 1
fi

echo "Pulling latest image(s) for ${SITE_NAME}..."
docker compose -f "${COMPOSE_FILE}" pull

echo "Recreating ${SITE_NAME} with updated image(s)..."
docker compose -f "${COMPOSE_FILE}" up -d

echo "✅ Updated ${SITE_NAME}."
