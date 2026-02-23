#!/usr/bin/env bash
set -euo pipefail

# Scaffold (and optionally deploy) a generic app container behind Traefik.
#
# Required:
#   SITE_NAME      short name used for directory/service/router IDs
#   SITE_HOST      public hostname for host-based routing
#   IMAGE          container image reference (e.g. ghcr.io/org/app:latest)
#   APP_PORT       container port Traefik should forward to
#
# Optional:
#   TARGET_DIR     base site directory (default: /opt/sites)
#   NETWORK_NAME   shared Traefik network (default: traefik_proxy)
#   ENTRYPOINTS    Traefik entrypoints (default: websecure)
#   CERT_RESOLVER  Traefik cert resolver (default: cf)
#   CONTAINER_NAME container name (default: SITE_NAME)
#   MIDDLEWARES    Traefik middleware chain (comma-separated)
#   DEPLOY_NOW     true/false; deploy immediately (default: false)
#   FORCE          true/false; overwrite existing compose file (default: false)
#
# Example:
#   SITE_NAME=helpdesk-bridge \
#   SITE_HOST=helpdesk-bridge.example.org \
#   IMAGE=ghcr.io/example/helpdesk-bridge:latest \
#   APP_PORT=8080 \
#   /opt/traefik/scripts/onboard_generic_app.sh

SITE_NAME="${SITE_NAME:-${1:-}}"
SITE_HOST="${SITE_HOST:-}"
IMAGE="${IMAGE:-}"
APP_PORT="${APP_PORT:-}"

TARGET_DIR="${TARGET_DIR:-/opt/sites}"
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
ENTRYPOINTS="${ENTRYPOINTS:-websecure}"
CERT_RESOLVER="${CERT_RESOLVER:-cf}"
CONTAINER_NAME="${CONTAINER_NAME:-$SITE_NAME}"
MIDDLEWARES="${MIDDLEWARES:-}"
DEPLOY_NOW="${DEPLOY_NOW:-false}"
FORCE="${FORCE:-false}"

BASE="${TARGET_DIR}/${SITE_NAME}"
COMPOSE_FILE="${BASE}/docker-compose.yml"

log() { printf "\n==> %s\n" "$*"; }

usage() {
  cat <<EOF
Usage:
  SITE_NAME=<name> SITE_HOST=<host> IMAGE=<image> APP_PORT=<port> $0

Required:
  SITE_NAME, SITE_HOST, IMAGE, APP_PORT

Optional:
  TARGET_DIR=${TARGET_DIR}
  NETWORK_NAME=${NETWORK_NAME}
  ENTRYPOINTS=${ENTRYPOINTS}
  CERT_RESOLVER=${CERT_RESOLVER}
  CONTAINER_NAME=${CONTAINER_NAME}
  MIDDLEWARES=<mw1,mw2>
  DEPLOY_NOW=<true|false>
  FORCE=<true|false>
EOF
}

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

validate_inputs() {
  if [[ -z "$SITE_NAME" || -z "$SITE_HOST" || -z "$IMAGE" || -z "$APP_PORT" ]]; then
    usage >&2
    exit 1
  fi

  if [[ ! "$SITE_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "SITE_NAME must match ^[a-z0-9][a-z0-9-]*$ (got: ${SITE_NAME})" >&2
    exit 1
  fi

  if [[ ! "$APP_PORT" =~ ^[0-9]+$ ]]; then
    echo "APP_PORT must be a numeric port (got: ${APP_PORT})" >&2
    exit 1
  fi
}

ensure_docker() {
  require_cmd docker
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not reachable for this user. Ensure docker is running and permissions are correct." >&2
    exit 1
  fi
}

ensure_network() {
  if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    log "Docker network '${NETWORK_NAME}' already exists"
  else
    log "Creating docker network '${NETWORK_NAME}'"
    docker network create "$NETWORK_NAME" >/dev/null
  fi
}

write_compose() {
  local middleware_label=""
  local rule

  if [[ -f "$COMPOSE_FILE" ]] && ! is_true "$FORCE"; then
    echo "Refusing to overwrite existing compose file: ${COMPOSE_FILE}" >&2
    echo "Set FORCE=true to overwrite." >&2
    exit 1
  fi

  mkdir -p "$BASE"
  rule="Host(\`${SITE_HOST}\`)"

  if [[ -n "$MIDDLEWARES" ]]; then
    middleware_label="      - traefik.http.routers.${SITE_NAME}.middlewares=${MIDDLEWARES}"
  fi

  log "Writing ${COMPOSE_FILE}"
  cat >"$COMPOSE_FILE" <<EOF
services:
  ${SITE_NAME}:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    labels:
      - traefik.enable=true
      - traefik.http.routers.${SITE_NAME}.rule=${rule}
      - traefik.http.routers.${SITE_NAME}.entrypoints=${ENTRYPOINTS}
      - traefik.http.routers.${SITE_NAME}.tls=true
      - traefik.http.routers.${SITE_NAME}.tls.certresolver=${CERT_RESOLVER}
      - traefik.http.services.${SITE_NAME}.loadbalancer.server.port=${APP_PORT}
${middleware_label}
    networks:
      - ${NETWORK_NAME}

networks:
  ${NETWORK_NAME}:
    external: true
EOF
}

deploy_if_requested() {
  if is_true "$DEPLOY_NOW"; then
    log "Deploying ${SITE_NAME} now (DEPLOY_NOW=true)"
    docker compose -f "$COMPOSE_FILE" pull
    docker compose -f "$COMPOSE_FILE" up -d
  fi
}

next_steps() {
  cat <<EOF

✅ Generic app compose scaffolded at:
  ${COMPOSE_FILE}

Manual-first deploy commands:
  docker compose -f ${COMPOSE_FILE} pull
  docker compose -f ${COMPOSE_FILE} up -d

Update/remove with existing platform scripts:
  /opt/traefik/scripts/update_site.sh ${SITE_NAME}
  SITE_NAME=${SITE_NAME} /opt/traefik/scripts/remove_site.sh
EOF
}

main() {
  validate_inputs
  ensure_docker
  ensure_network
  write_compose
  deploy_if_requested
  next_steps
}

main "$@"
