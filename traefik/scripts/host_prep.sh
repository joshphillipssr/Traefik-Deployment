#!/usr/bin/env bash
set -euo pipefail
#
# host_prep.sh — one-time bootstrap for a fresh Debian host.
# - Installs Docker & Compose plugin if missing
# - Creates non-root 'deploy' user and adds to 'docker' group
# - Creates /opt/traefik and /opt/sites owned by deploy
# - Clones/updates Traefik-Deployment into /opt/traefik
#
# Usage (run as root):
#   bash traefik/scripts/host_prep.sh
#
# After this finishes, switch to 'deploy' and run:
#   CF_API_TOKEN="..." EMAIL="you@example.com" USE_STAGING=false \
#     /opt/traefik/traefik/scripts/traefik_up.sh

REPO_URL="${REPO_URL:-https://github.com/joshphillipssr/Traefik-Deployment.git}"
TRAefik_DIR="/opt/traefik"
SITES_DIR="/opt/sites"
DEPLOY_USER="${DEPLOY_USER:-deploy}"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root. Try: sudo bash $0" >&2
    exit 1
  fi
}

log() { printf "\n==> %s\n" "$*"; }

ensure_user() {
  if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    log "User '$DEPLOY_USER' already exists"
  else
    log "Creating user '$DEPLOY_USER'"
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
  fi

  if id -nG "$DEPLOY_USER" | tr ' ' '\n' | grep -qx docker; then
    log "User '$DEPLOY_USER' already in 'docker' group"
  else
    log "Adding '$DEPLOY_USER' to 'docker' group"
    usermod -aG docker "$DEPLOY_USER" || true
  fi
}

ensure_dirs() {
  log "Ensuring directories exist and are owned by '$DEPLOY_USER'"
  mkdir -p "$TRAefik_DIR" "$SITES_DIR"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAefik_DIR" "$SITES_DIR"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log "Docker already installed and running"
    return
  fi
  log "Installing Docker Engine & Compose plugin (Debian)"
  apt-get update
  apt-get -y install ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
> /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

clone_or_update_repo() {
  if [[ -d "$TRAefik_DIR/.git" ]]; then
    log "Updating Traefik-Deployment in $TRAefik_DIR"
    git -C "$TRAefik_DIR" fetch --all --prune
    git -C "$TRAefik_DIR" switch -q main || true
    git -C "$TRAefik_DIR" pull --ff-only
  else
    log "Cloning Traefik-Deployment to $TRAefik_DIR"
    git clone "$REPO_URL" "$TRAefik_DIR"
  fi
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAefik_DIR"
  chmod +x "$TRAefik_DIR"/traefik/scripts/*.sh
}

next_steps() {
  cat <<EONEXT

✅ Host prep complete.

Now switch to the '$DEPLOY_USER' user (or SSH in as that user) and start Traefik:

  su - ${DEPLOY_USER}

  CF_API_TOKEN="YOUR_CF_TOKEN" EMAIL="you@example.com" USE_STAGING=false \\
    /opt/traefik/traefik/scripts/traefik_up.sh

After Traefik is up, deploy your site container from your site repo’s script.
EONEXT
}

main() {
  need_root
  ensure_docker
  ensure_user
  ensure_dirs
  clone_or_update_repo
  next_steps
}

main "$@"