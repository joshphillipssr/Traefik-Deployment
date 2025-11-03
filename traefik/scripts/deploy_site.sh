#!/usr/bin/env bash
set -euo pipefail
# Deploy a site behind Traefik using Docker labels.
# Required vars:
#   SITE_NAME="shortname"
#   SITE_HOSTS="example.com www.example.com"
#   SITE_IMAGE="ghcr.io/you/app:latest"
# Optional:
#   TARGET_DIR="/opt/sites" (default)
#   NETWORK_NAME="traefik_proxy" (default)

: "${SITE_NAME:?SITE_NAME is required}"
: "${SITE_HOSTS:?SITE_HOSTS is required}"
: "${SITE_IMAGE:?SITE_IMAGE is required}"

TARGET_DIR="${TARGET_DIR:-/opt/sites}"
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
BASE="${TARGET_DIR}/${SITE_NAME}"

# Ensure Docker available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found or not in PATH." >&2
  exit 1
fi

sudo mkdir -p "$TARGET_DIR" "$BASE"
sudo docker network create "$NETWORK_NAME" >/dev/null 2>&1 || true

# Build Host(`a`,`b`) rule (space-separated hosts -> backtick-wrapped list)
rule="Host(`$(echo $SITE_HOSTS | sed 's/ /`,`/g')`)"

echo "Creating docker-compose for ${SITE_NAME} in ${BASE}..."

cat <<YML | sudo tee "${BASE}/docker-compose.yml" >/dev/null
services:
  ${SITE_NAME}_site:
    image: ${SITE_IMAGE}
    container_name: ${SITE_NAME}_site
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    labels:
      - traefik.enable=true
      - traefik.http.routers.${SITE_NAME}.rule=${rule}
      - traefik.http.routers.${SITE_NAME}.entrypoints=websecure
      - traefik.http.routers.${SITE_NAME}.tls=true
      - traefik.http.routers.${SITE_NAME}.tls.certresolver=cf
      - traefik.http.services.${SITE_NAME}.loadbalancer.server.port=80
networks:
  ${NETWORK_NAME}:
    external: true
YML

sudo docker compose -f "${BASE}/docker-compose.yml" up -d
echo "✅ Deployed ${SITE_NAME} for hosts: ${SITE_HOSTS}"