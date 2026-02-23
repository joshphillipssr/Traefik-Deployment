#!/usr/bin/env bash
set -euo pipefail

# Root-side bootstrap: create deploy user, install Docker, and lay down base directories.

DEPLOY_USER="${DEPLOY_USER:-deploy}"
TRAEFIK_DIR="/opt/traefik"
SITES_DIR="/opt/sites"
DEPLOY_HOME="/home/${DEPLOY_USER}"

log() { printf "\n==> %s\n" "$*"; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Try: sudo bash $0" >&2
    exit 1
  fi
}

ensure_user() {
  if ! id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    log "Creating user '${DEPLOY_USER}'"
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
  else
    log "User '${DEPLOY_USER}' already exists"
  fi

  # Ensure home directory & baseline perms
  mkdir -p "$DEPLOY_HOME"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME"
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
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable
EOF

  apt-get update
  apt-get -y install \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
}

bootstrap_repo_and_env() {
  mkdir -p "$TRAEFIK_DIR" "$SITES_DIR"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$TRAEFIK_DIR" "$SITES_DIR"

  log "Traefik directories created. Repository/env bootstrap happens during deploy-side prep."
}

configure_sudo_for_deploy() {
  log "Granting '${DEPLOY_USER}' controlled sudo access and docker group membership"

  # docker group
  if ! id -nG "$DEPLOY_USER" | grep -qw docker; then
    usermod -aG docker "$DEPLOY_USER" || true
  fi

  # Minimal sudoers file for future tooling (we can tighten/expand later)
  local sudoers_file="/etc/sudoers.d/${DEPLOY_USER}-traefik"
  cat >"$sudoers_file" <<EOF
# Managed by Traefik host_prep_root.sh
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/systemctl restart docker.service
EOF
  chmod 440 "$sudoers_file"
}

next_steps() {
  cat <<EOF

✅ Phase 1 host prep complete.

You can now switch to the '${DEPLOY_USER}' user and run deploy-side prep:

  sudo -iu ${DEPLOY_USER}
  ~/host_prep_deploy.sh

On first run, host_prep_deploy.sh will create ~/traefik.env if missing and then validate required values.
If validation fails, edit the env file and rerun:

  nano ~/traefik.env
  ~/host_prep_deploy.sh

When deploy-side prep succeeds, start Traefik with:

  /opt/traefik/scripts/traefik_up.sh

EOF
}

main() {
  need_root
  ensure_user
  ensure_docker
  bootstrap_repo_and_env
  configure_sudo_for_deploy
  next_steps
}

main "$@"
