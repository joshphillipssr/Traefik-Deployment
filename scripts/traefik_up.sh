#!/usr/bin/env bash
set -euo pipefail

# Resolve repo paths relative to this script so it works from any CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRAEFIK_DIR="${REPO_ROOT}/docker"

# Default env file location for Traefik configuration
# This is intended to live outside the repo, e.g. /home/deploy/traefik.env
DEFAULT_ENV_FILE="/home/deploy/traefik.env"
ENV_FILE="${TRAEFIK_ENV_FILE:-$DEFAULT_ENV_FILE}"

# Load env file if it exists (makes variables available to this shell)
if [[ -f "$ENV_FILE" ]]; then
  # Export variables defined in the env file into the environment
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

# Allow explicit overrides from the current environment, but require that
# the values are available from either env or the env file.
CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN required (set in environment or $ENV_FILE)}"
EMAIL="${EMAIL:?EMAIL required (set in environment or $ENV_FILE)}"
USE_STAGING="${USE_STAGING:-false}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:?WEBHOOK_SECRET required (set in environment or $ENV_FILE)}"

# Ensure Docker available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot talk to the Docker daemon. Ensure your user is in the 'docker' group and Docker is running." >&2
  exit 1
fi

# Ensure Traefik directory exists (holds docker-compose and any override)
mkdir -p "${TRAEFIK_DIR}"

# Ensure shared Docker network exists
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
docker network create "$NETWORK_NAME" >/dev/null 2>&1 || true

# Handle staging vs production ACME config
if [[ "$USE_STAGING" == "true" ]]; then
  cat > "${TRAEFIK_DIR}/docker-compose.override.yml" <<EOF
services:
  traefik:
    command:
      - --certificatesresolvers.cf.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
EOF
else
  if [[ -f "${TRAEFIK_DIR}/docker-compose.override.yml" ]]; then
    rm -f "${TRAEFIK_DIR}/docker-compose.override.yml"
  fi
fi

# Export variables so docker compose picks them up for substitution
export CF_API_TOKEN EMAIL USE_STAGING NETWORK_NAME

# Bring up Traefik using the compose stack in the docker/ directory
(
  cd "${TRAEFIK_DIR}"
  docker compose -f docker-compose.yml up -d
)

echo "Traefik is up (host 80→8080, 443→8443; staging=${USE_STAGING})."