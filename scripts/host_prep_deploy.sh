#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
TRAEFIK_DIR="/opt/traefik"
SITES_DIR="/opt/sites"
DEPLOY_HOME="/home/${DEPLOY_USER}"
DEPLOY_ENV="${DEPLOY_HOME}/traefik.env"

log() { printf "\n==> %s\n" "$*"; }

need_deploy() {
  if [[ "$(id -un)" != "$DEPLOY_USER" ]]; then
    echo "This script must be run as ${DEPLOY_USER}. Try: sudo -iu ${DEPLOY_USER}" >&2
    exit 1
  fi
}

load_env() {
  if [[ ! -f "$DEPLOY_ENV" ]]; then
    echo "Missing ${DEPLOY_ENV}. Create it (from traefik.env.sample) before running this script." >&2
    exit 1
  fi

  log "Loading ${DEPLOY_ENV}"
  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
  set +a
}

ensure_dirs() {
  log "Ensuring Traefik directories exist and are owned by ${DEPLOY_USER}"
  mkdir -p "$TRAEFIK_DIR" "$SITES_DIR"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAEFIK_DIR" "$SITES_DIR"
}

update_repo() {
  if [[ -d "$TRAEFIK_DIR/.git" ]]; then
    log "Updating Traefik-Deployment repo at $TRAEFIK_DIR"
    git -C "$TRAEFIK_DIR" fetch --all --prune
    git -C "$TRAEFIK_DIR" switch -q main || true
    git -C "$TRAEFIK_DIR" pull --ff-only
    chmod +x "$TRAEFIK_DIR"/scripts/*.sh || true
  else
    echo "ERROR: $TRAEFIK_DIR does not look like a git repo. Run host_prep_root.sh first." >&2
    exit 1
  fi
}

next_steps() {
  cat <<EOF

✅ Deploy-side host prep complete.

You can now start Traefik using your environment file:

  /opt/traefik/scripts/traefik_up.sh

If you're also using webhook tooling, run:

  /opt/traefik/scripts/hooks_provision.sh

EOF
}

main() {
  need_deploy
  load_env
  ensure_dirs
  update_repo
  next_steps
}

main "$@"