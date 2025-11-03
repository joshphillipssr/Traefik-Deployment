#!/usr/bin/env bash
set -euo pipefail

# Deploy a site behind Traefik.
#
# Required ENV:
#   SITE_NAME="shortname"
#   SITE_HOSTS="example.com www.example.com"
#   SITE_IMAGE="ghcr.io/you/your-site:latest"
#
# Optional ENV:
#   TARGET_DIR="/opt/sites"          # where site stacks live
#   NETWORK_NAME="traefik_proxy"     # shared docker network

: "${SITE_NAME:?SITE_NAME required}"
: "${SITE_HOSTS:?SITE_HOSTS required}"
: "${SITE_IMAGE:?SITE_IMAGE required}"

TARGET_DIR="${TARGET_DIR:-/opt/sites}"
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
BASE="${TARGET_DIR}/${SITE_NAME}"

# Ensure Docker available (no sudo; assumes user in 'docker' group)
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot talk to the Docker daemon. Ensure your user is in the 'docker' group." >&2
  exit 1
fi

echo "Ensuring directories exist: ${TARGET_DIR} and ${BASE}"
mkdir -p "${TARGET_DIR}" "${BASE}"

echo "Ensuring shared network exists: ${NETWORK_NAME}"
docker network create "${NETWORK_NAME}" >/dev/null 2>&1 || true

# Build the Host() rule for Traefik (space-separated to comma-separated)
HOST_RULE=$(printf "%s" "${SITE_HOSTS}" | awk '{for (i=1;i<=NF;i++) printf("`%s`%s", $i, (i<NF?",":""));}')
# Example -> Host(`a.com`,`www.a.com`)

COMPOSE_FILE="${BASE}/docker-compose.yml"
echo "Writing ${COMPOSE_FILE} ..."
cat > "${COMPOSE_FILE}" <<YML
version: "3.9"

services:
  ${SITE_NAME}:
    image: ${SITE_IMAGE}
    container_name: ${SITE_NAME}
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SITE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${SITE_NAME}.rule=Host(${HOST_RULE})"
      - "traefik.http.routers.${SITE_NAME}.tls.certresolver=cf"
      - "traefik.http.services.${SITE_NAME}.loadbalancer.server.port=80"

networks:
  ${NETWORK_NAME}:
    external: true
YML

echo "Bringing up ${SITE_NAME} ..."
docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d

echo "✅ Deployed ${SITE_NAME} for hosts: ${SITE_HOSTS}"