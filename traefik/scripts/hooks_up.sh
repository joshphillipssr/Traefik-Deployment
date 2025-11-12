#!/usr/bin/env bash
# hooks_up.sh — Provision and start a webhook listener behind Traefik
# This sets up /opt/traefik/hooks with:
#   - docker-compose.yml  (webhook service)
#   - hooks.json          (hook rules; includes a starter for jpsr)
#   - scripts/deploy-site.sh  (runs update_site.sh as deploy)
#
# Run as:  sudo /opt/traefik/traefik/scripts/hooks_up.sh
# Re-run safe (idempotent).

set -euo pipefail

# --- config (can override via env) ---
HOOKS_DIR="${HOOKS_DIR:-/opt/traefik/hooks}"
TRAEFIK_DIR="${TRAEFIK_DIR:-/opt/traefik}"
NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"
HOOKS_HOST="${HOOKS_HOST:-hooks.joshphillipssr.com}"   # DNS host routed via Traefik
DEPLOY_USER="${DEPLOY_USER:-deploy}"
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/webhook-deploy}"

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Re-executing with sudo..."
    exec sudo --preserve-env=HOOKS_DIR,TRAEFIK_DIR,NETWORK_NAME,HOOKS_HOST,DEPLOY_USER,SUDOERS_FILE "$0" "$@"
  fi
}
need_root

log() { printf "\n==> %s\n" "$*"; }

assert() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

log "Checking prerequisites"
assert docker
assert bash

# --- create directories ---
log "Ensuring directories exist under ${HOOKS_DIR}"
mkdir -p "${HOOKS_DIR}/scripts"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${HOOKS_DIR}" || true

# --- write docker-compose.yml for the webhook listener ---
log "Writing ${HOOKS_DIR}/docker-compose.yml"
cat > "${HOOKS_DIR}/docker-compose.yml" <<"YML"
services:
  hooks:
    image: ghcr.io/adnanh/webhook:2.8.1
    container_name: webhook
    restart: unless-stopped
    networks:
      - traefik_proxy
    command: ["-verbose", "-hotreload", "-hooks=/hooks/hooks.json"]
    volumes:
      - /opt/traefik/hooks/hooks.json:/hooks/hooks.json:ro
      - /opt/traefik/hooks/scripts:/hooks/scripts:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.hooks.rule=Host(`__HOOKS_HOST__`)"
      - "traefik.http.routers.hooks.entrypoints=websecure"
      - "traefik.http.routers.hooks.tls=true"
      - "traefik.http.routers.hooks.tls.certresolver=cf"
    read_only: true
    tmpfs:
      - /tmp

networks:
  traefik_proxy:
    external: true
YML

# inject runtime host into labels
sed -i "s/__HOOKS_HOST__/${HOOKS_HOST//\//\\/}/g" "${HOOKS_DIR}/docker-compose.yml"

# --- write a starter hooks.json if not present ---
if [[ ! -f "${HOOKS_DIR}/hooks.json" ]]; then
  log "Creating starter ${HOOKS_DIR}/hooks.json (includes 'deploy-jpsr')"
  cat > "${HOOKS_DIR}/hooks.json" <<"JSON"
[
  {
    "id": "deploy-jpsr",
    "execute-command": "/hooks/scripts/deploy-site.sh",
    "command-working-directory": "/",
    "pass-arguments-to-command": [
      { "source": "string", "name": "jpsr" }
    ],
    "trigger-rule": {
      "and": [
        { "match": { "type": "value", "value": "workflow_run", "parameter": { "source": "header", "name": "X-GitHub-Event" } } },
        { "match": { "type": "payload-hash-sha256", "secret": "REPLACE_WITH_LONG_RANDOM_SECRET" } },
        { "match": { "type": "value", "value": "success", "parameter": { "source": "payload", "name": "workflow_run.conclusion" } } },
        { "match": { "type": "value", "value": "Build and Push Docker Image", "parameter": { "source": "payload", "name": "workflow_run.name" } } }
      ]
    }
  }
]
JSON
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "${HOOKS_DIR}/hooks.json"
fi

# --- write deploy-site.sh (always ensure latest content) ---
log "Writing ${HOOKS_DIR}/scripts/deploy-site.sh"
cat > "${HOOKS_DIR}/scripts/deploy-site.sh" <<"SH"
#!/usr/bin/env bash
set -euo pipefail
SITE_NAME="${1:?site name required}"
exec sudo -u deploy SITE_NAME="$SITE_NAME" /opt/traefik/traefik/scripts/update_site.sh
SH
chmod +x "${HOOKS_DIR}/scripts/deploy-site.sh"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${HOOKS_DIR}/scripts/deploy-site.sh"

# --- sudoers rule (narrow) ---
if [[ ! -f "${SUDOERS_FILE}" ]]; then
  log "Installing sudoers rule at ${SUDOERS_FILE}"
  umask 077
  cat > "${SUDOERS_FILE}" <<SUD
# Allow webhook listener to run the site updater as ${DEPLOY_USER}
root ALL=(${DEPLOY_USER}) NOPASSWD: /opt/traefik/traefik/scripts/update_site.sh
SUD
  chmod 440 "${SUDOERS_FILE}"
fi

# --- ensure shared network exists ---
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  log "Creating shared network ${NETWORK_NAME}"
  docker network create "${NETWORK_NAME}"
else
  log "Shared network ${NETWORK_NAME} already exists"
fi

# --- bring up the webhook service ---
log "Starting webhook service via docker compose"
docker compose -f "${HOOKS_DIR}/docker-compose.yml" up -d

echo
echo "✅ Webhook listener is up at https://${HOOKS_HOST} (proxied by Traefik)."
echo "   Files:"
echo "     - ${HOOKS_DIR}/docker-compose.yml"
echo "     - ${HOOKS_DIR}/hooks.json"
echo "     - ${HOOKS_DIR}/scripts/deploy-site.sh"
echo
echo "🔐 IMPORTANT:"
echo "  - Edit ${HOOKS_DIR}/hooks.json and replace REPLACE_WITH_LONG_RANDOM_SECRET with a strong secret."
echo "  - In GitHub → Settings → Webhooks, add a webhook:"
echo "      URL: https://${HOOKS_HOST}/hooks/deploy-jpsr"
echo "      Content type: application/json"
echo "      Secret: (the same secret you set in hooks.json)"
echo "      Events: Workflow runs"
echo
echo "🧪 Test:"
echo "  - Push to main so your build-and-push workflow completes."
echo "  - Check 'docker logs webhook' and your site container status."
