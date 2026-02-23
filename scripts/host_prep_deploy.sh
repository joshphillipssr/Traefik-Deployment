#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
TRAEFIK_DIR="/opt/traefik"
SITES_DIR="/opt/sites"
DEPLOY_HOME="/home/${DEPLOY_USER}"
DEPLOY_ENV="${DEPLOY_HOME}/traefik.env"
TRAEFIK_REPO_URL="${TRAEFIK_REPO_URL:-https://github.com/joshphillipssr/Traefik-Deployment.git}"

log() { printf "\n==> %s\n" "$*"; }

need_deploy() {
  if [[ "$(id -un)" != "$DEPLOY_USER" ]]; then
    echo "This script must be run as ${DEPLOY_USER}. Try: sudo -iu ${DEPLOY_USER}" >&2
    exit 1
  fi
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
  else
    log "Cloning Traefik-Deployment repo into $TRAEFIK_DIR"
    git clone "$TRAEFIK_REPO_URL" "$TRAEFIK_DIR"
  fi

  chmod +x "$TRAEFIK_DIR"/scripts/*.sh || true
}

ensure_env_file() {
  local sample_env="${TRAEFIK_DIR}/traefik.env.sample"

  if [[ ! -f "$sample_env" ]]; then
    echo "Missing ${sample_env} after cloning ${TRAEFIK_REPO_URL}. Cannot bootstrap ${DEPLOY_ENV}." >&2
    exit 1
  fi

  if [[ ! -f "$DEPLOY_ENV" ]]; then
    log "Creating ${DEPLOY_ENV} from ${sample_env}"
    cp "$sample_env" "$DEPLOY_ENV"
  else
    log "${DEPLOY_ENV} already exists, leaving in place"
  fi

  chmod 600 "$DEPLOY_ENV"
}

load_env() {
  if [[ ! -f "$DEPLOY_ENV" ]]; then
    echo "Missing ${DEPLOY_ENV}. This file should have been bootstrapped automatically." >&2
    exit 1
  fi

  log "Loading ${DEPLOY_ENV}"
  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
  set +a
}

validate_env() {
  local missing=()
  local placeholders=()
  local required=(CF_API_TOKEN EMAIL WEBHOOK_SECRET)
  local var val

  for var in "${required[@]}"; do
    val="${!var:-}"
    if [[ -z "${val// }" ]]; then
      missing+=("$var")
    fi
  done

  [[ "${CF_API_TOKEN:-}" == "CHANGE_ME_CLOUDFLARE_DNS_EDIT_TOKEN" ]] && placeholders+=("CF_API_TOKEN")
  [[ "${EMAIL:-}" == "you@example.com" ]] && placeholders+=("EMAIL")
  [[ "${WEBHOOK_SECRET:-}" == "ChangeThisSecretNow" ]] && placeholders+=("WEBHOOK_SECRET")

  if [[ ${#missing[@]} -gt 0 || ${#placeholders[@]} -gt 0 ]]; then
    echo "Environment validation failed for ${DEPLOY_ENV}." >&2
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "Missing required values: ${missing[*]}" >&2
    fi
    if [[ ${#placeholders[@]} -gt 0 ]]; then
      echo "Replace placeholder values for: ${placeholders[*]}" >&2
    fi
    echo "Edit ${DEPLOY_ENV}, then rerun: $0" >&2
    exit 1
  fi

  if [[ -z "${HOOKS_HOST:-}" || "${HOOKS_HOST}" == "hooks.your-domain.com" ]]; then
    log "NOTE: HOOKS_HOST is unset/default; set it before enabling webhook routing."
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
  ensure_dirs
  update_repo
  ensure_env_file
  load_env
  validate_env
  next_steps
}

main "$@"
