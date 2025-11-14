#!/usr/bin/env bash
# hooks_provision.sh — Provision a host-level webhook listener for Traefik site deploys
#
# This script sets up:
#   - /opt/traefik/hooks/hooks.json          (hook rules; includes a starter for jpsr)
#   - systemd service: traefik-webhook.service (runs the webhook binary on the host)
#
# The webhook will listen on 127.0.0.1:9000 by default. Traefik (running in Docker)
# can be configured to proxy hooks.joshphillipssr.com to this listener, e.g. via
# a file provider (documented in the Traefik README).
#
# Run as:
#   sudo /opt/traefik/scripts/hooks_provision.sh
#
# Re-runs are safe (idempotent).

set -euo pipefail

ENV_FILE="/opt/traefik/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

HOOKS_DIR="${HOOKS_DIR:-${TRAEFIK_HOOKS_DIR:-/opt/traefik/hooks}}"
TRAEFIK_DIR="${TRAEFIK_DIR:-${TRAEFIK_DIR:-/opt/traefik}}"
WEBHOOK_PORT="${WEBHOOK_PORT:-${WEBHOOK_PORT:-9000}}"
WEBHOOK_HOST="${WEBHOOK_HOST:-${WEBHOOK_HOST:-127.0.0.1}}"
SERVICE_NAME="${SERVICE_NAME:-${WEBHOOK_SERVICE_NAME:-traefik-webhook}}"
DEPLOY_USER="${DEPLOY_USER:-${DEPLOY_USER:-deploy}}"
WEBHOOK_BIN="${WEBHOOK_BIN:-${WEBHOOK_BIN:-/usr/bin/webhook}}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-${WEBHOOK_SECRET:-ChangeThisSecretNow}}"

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Re-executing with sudo..."
    exec sudo \
      HOOKS_DIR="${HOOKS_DIR}" \
      TRAEFIK_DIR="${TRAEFIK_DIR}" \
      WEBHOOK_PORT="${WEBHOOK_PORT}" \
      WEBHOOK_HOST="${WEBHOOK_HOST}" \
      SERVICE_NAME="${SERVICE_NAME}" \
      DEPLOY_USER="${DEPLOY_USER}" \
      WEBHOOK_BIN="${WEBHOOK_BIN}" \
      "$0" "$@"
  fi
}
need_root

log() { printf "\n==> %s\n" "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

log "Checking prerequisites (webhook service will run on the host)"
require_cmd systemctl

# Install webhook binary if not present (Debian-based host)
if [[ ! -x "${WEBHOOK_BIN}" ]] && ! command -v webhook >/dev/null 2>&1; then
  log "Webhook binary not found; attempting to install via apt (Debian assumed)"
  require_cmd apt-get
  apt-get update -y
  apt-get install -y webhook
fi

# Resolve the final path to the webhook binary
if [[ -x "${WEBHOOK_BIN}" ]]; then
  WEBHOOK_BIN_RESOLVED="${WEBHOOK_BIN}"
elif command -v webhook >/dev/null 2>&1; then
  WEBHOOK_BIN_RESOLVED="$(command -v webhook)"
else
  echo "Unable to locate the webhook binary even after install attempt."
  exit 1
fi

log "Using webhook binary at: ${WEBHOOK_BIN_RESOLVED}"

# --- create directories ---
log "Ensuring hooks directory exists at ${HOOKS_DIR}"
mkdir -p "${HOOKS_DIR}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${HOOKS_DIR}" || true

# --- write a starter hooks.json if not present ---
HOOKS_JSON="${HOOKS_DIR}/hooks.json"

if [[ ! -f "${HOOKS_JSON}" ]]; then
  log "Creating starter ${HOOKS_JSON} (includes 'deploy-jpsr')"
  cat > "${HOOKS_JSON}" <<"JSON"
[
  {
    "id": "deploy-jpsr",
    "execute-command": "/opt/traefik/scripts/update_site.sh",
    "command-working-directory": "/",
    "pass-arguments-to-command": [
      { "source": "string", "name": "jpsr" }
    ],
    "trigger-rule": {
      "and": [
        {
          "match": {
            "type": "value",
            "value": "workflow_run",
            "parameter": {
              "source": "header",
              "name": "X-GitHub-Event"
            }
          }
        },
        {
          "match": {
            "type": "payload-hash-sha256",
            "secret": "'${WEBHOOK_SECRET}'"
          }
        },
        {
          "match": {
            "type": "value",
            "value": "completed",
            "parameter": {
              "source": "payload",
              "name": "action"
            }
          }
        },
        {
          "match": {
            "type": "value",
            "value": "success",
            "parameter": {
              "source": "payload",
              "name": "workflow_run.conclusion"
            }
          }
        },
        {
          "match": {
            "type": "value",
            "value": "Build and Push Docker Image",
            "parameter": {
              "source": "payload",
              "name": "workflow_run.name"
            }
          }
        }
      ]
    }
  }
]
JSON
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "${HOOKS_JSON}" || true
else
  log "Existing hooks.json found at ${HOOKS_JSON} (leaving in place)"
fi

# --- write systemd unit file ---
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

log "Writing systemd unit at ${SERVICE_FILE}"
cat > "${SERVICE_FILE}" <<UNIT
[Unit]
Description=Traefik webhook listener for site deployments
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${WEBHOOK_BIN_RESOLVED} -verbose -hooks=${HOOKS_JSON} -hotreload -port ${WEBHOOK_PORT} -ip ${WEBHOOK_HOST}
WorkingDirectory=${HOOKS_DIR}
# Run as root so it can call update_site.sh, which in turn manages Docker.
# update_site.sh is responsible for any user switching (e.g. to 'deploy').
User=root
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT

log "Reloading systemd daemon and enabling ${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo
echo "✅ Webhook service '${SERVICE_NAME}' is provisioned and started."
echo "   Listening on http://${WEBHOOK_HOST}:${WEBHOOK_PORT}"
echo "   Files:"
echo "     - ${HOOKS_JSON}"
echo "     - ${SERVICE_FILE}"
echo
echo "🔐 IMPORTANT:"
echo "  - Webhook secret is loaded from ${ENV_FILE} (WEBHOOK_SECRET=${WEBHOOK_SECRET})."
echo "  - In GitHub → Settings → Webhooks, add a webhook:"
echo "      URL: https://hooks.your-domain.com/hooks/deploy-jpsr"
echo "      Content type: application/json"
echo "      Secret: (the same secret you set in hooks.json)"
echo "      Events: Workflow runs"
echo
echo "🧪 Test:"
echo "  - Push to main so your 'Build and Push Docker Image' workflow completes."
echo "  - Check 'journalctl -u ${SERVICE_NAME} -f' for incoming webhook logs."
echo
echo "📌 NOTE:"
echo "  - Traefik (running in Docker) must be configured to proxy your public"
echo "    hooks host (e.g. hooks.your-domain.com) to http://${WEBHOOK_HOST}:${WEBHOOK_PORT}."
echo "  - See the Traefik README for the suggested file-provider configuration."
