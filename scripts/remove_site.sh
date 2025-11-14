#!/usr/bin/env bash
set -euo pipefail

# Remove a deployed site stack and its compose directory.
#
# Required:
#   SITE_NAME="shortname"
# Optional:
#   TARGET_DIR="/opt/sites" (default)
#
# Example:
#   SITE_NAME="jpsr" ./traefik/scripts/remove_site.sh

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

# Check if the site exists
if [[ ! -f "${BASE}/docker-compose.yml" ]]; then
  echo "No docker-compose.yml found for site '${SITE_NAME}' in ${BASE}."
  exit 0
fi

echo "Stopping and removing ${SITE_NAME}..."

docker compose -f "${BASE}/docker-compose.yml" down --remove-orphans
rm -rf "${BASE}"
echo "✅ Removed ${SITE_NAME}."