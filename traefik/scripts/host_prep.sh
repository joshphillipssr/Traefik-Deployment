#!/usr/bin/env bash
set -euo pipefail

# Default values (override by exporting these vars before running)
REPO_URL="${REPO_URL:-https://github.com/joshphillipssr/Traefik-Deployment.git}"
TRAEFIK_DIR="/opt/traefik"
SITES_DIR="/opt/sites"
DEPLOY_USER="${DEPLOY_USER:-deploy}"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Try: sudo bash $0" >&2
    exit 1
  fi
}

log() { printf "\n==> %s\n" "$*"; }

ensure_user() {
  if ! id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    log "Creating user '$DEPLOY_USER'"
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
  fi
  if ! id -nG "$DEPLOY_USER" | grep -qw docker; then
    log "Adding '$DEPLOY_USER' to 'docker' group"
    usermod -aG docker "$DEPLOY_USER" || true
  fi
}

ensure_dirs() {
  log "Ensuring directories exist and are owned by '$DEPLOY_USER'"
  mkdir -p "$TRAEFIK_DIR" "$SITES_DIR"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAEFIK_DIR" "$SITES_DIR"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log "Docker already installed and running"
    return
  fi
  log "Installing Docker Engine & Compose (Debian)"
  apt-get update
  apt-get -y install ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

clone_or_update_repo() {
  if [[ -d "$TRAEFIK_DIR/.git" ]]; then
    log "Updating Traefik-Deployment in $TRAEFIK_DIR"
    # Run git commands as the deploy user
    sudo -u "$DEPLOY_USER" git -C "$TRAEFIK_DIR" fetch --all --prune
    sudo -u "$DEPLOY_USER" git -C "$TRAEFIK_DIR" switch -q main || true
    sudo -u "$DEPLOY_USER" git -C "$TRAEFIK_DIR" pull --ff-only
  else
    log "Cloning Traefik-Deployment to $TRAEFIK_DIR"
    sudo -u "$DEPLOY_USER" git clone "$REPO_URL" "$TRAEFIK_DIR"
  fi
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAEFIK_DIR"
  chmod +x "$TRAEFIK_DIR"/traefik/scripts/*.sh
}

next_steps() {
  cat <<EOF

✅ Host prep complete.

Now switch to the '$DEPLOY_USER' user (or SSH in as that user) and start Traefik:

  sudo -iu ${DEPLOY_USER}

  CF_API_TOKEN="YOUR_CF_TOKEN" EMAIL="you@example.com" USE_STAGING=false \\
    $TRAEFIK_DIR/traefik/scripts/traefik_up.sh

Reference the readme for further instructions:
https://github.com/joshphillipssr/joshphillipssr.com
https://github.com/joshphillipssr/Traefik-Deployment

EOF
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
