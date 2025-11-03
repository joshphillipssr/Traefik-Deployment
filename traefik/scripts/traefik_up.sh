#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   CF_API_TOKEN=xxx EMAIL=you@example.com USE_STAGING=false ./traefik/scripts/traefik_up.sh

CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN required}"
EMAIL="${EMAIL:?EMAIL required}"
USE_STAGING="${USE_STAGING:-false}"

# Ensure Docker available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot talk to the Docker daemon. Try running with sudo or ensure your user is in the 'docker' group." >&2
  exit 1
fi

# ACME storage is handled by a named volume (no host file needed)

# Ensure network
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
docker network create "$NETWORK_NAME" >/dev/null 2>&1 || true

if [ "$USE_STAGING" = "true" ]; then
  cat > traefik/docker-compose.override.yml <<EOF
services:
  traefik:
    command:
      - --certificatesresolvers.cf.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
EOF
else
  if [ -f traefik/docker-compose.override.yml ]; then
    rm traefik/docker-compose.override.yml
  fi
fi

# Build a throwaway env file (not committed)
cat > traefik/.env <<EOF
CF_API_TOKEN=${CF_API_TOKEN}
EMAIL=${EMAIL}
USE_STAGING=${USE_STAGING}
EOF
chmod 600 traefik/.env

docker compose -f traefik/docker-compose.yml --env-file traefik/.env up -d
echo "Traefik is up (host 80→8080, 443→8443; staging=${USE_STAGING})."