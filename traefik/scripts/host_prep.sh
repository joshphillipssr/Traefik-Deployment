#!/usr/bin/env bash
set -euo pipefail

# Resolve repo paths relative to this script so it works from any CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRAEFIK_DIR="${REPO_ROOT}/traefik"
cd "${REPO_ROOT}"

# ACME storage is handled by a named volume (no host file needed)
mkdir -p "${TRAEFIK_DIR}"

# (rest of the script continues here, with all occurrences of traefik/.env replaced by "${TRAEFIK_DIR}/.env",
# chmod 600 traefik/.env replaced by chmod 600 "${TRAEFIK_DIR}/.env",
# traefik/scripts/create_network.sh replaced by "${SCRIPT_DIR}/create_network.sh",
# docker compose up -d replaced by ( cd "${TRAEFIK_DIR}" && docker compose up -d ),
# traefik/docker-compose.override.yml replaced by "${TRAEFIK_DIR}/docker-compose.override.yml",
# and user-facing echoes updated accordingly)