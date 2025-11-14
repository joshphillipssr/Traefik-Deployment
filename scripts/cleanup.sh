#!/usr/bin/env bash
set -euo pipefail

# Traefik cleanup script
# This script removes Traefik-related containers, network, systemd units,
# sudoers rules, and the /opt/traefik tree.

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root (sudo)." >&2
  echo "        Try: sudo /opt/traefik/scripts/cleanup.sh" >&2
  exit 1
fi

log() {
  echo "==> $*"
}

# 1. Stop and remove Traefik and webhook containers (if present)
if command -v docker >/dev/null 2>&1; then
  log "Stopping Traefik-related containers (if any)"

  # Stop containers by name if they exist
  for name in traefik hooks; do
    cid=$(docker ps -aq --filter "name=^${name}$") || true
    if [[ -n ${cid:-} ]]; then
      docker stop "$name" >/dev/null 2>&1 || true
      docker rm "$name" >/dev/null 2>&1 || true
      log "Removed container: $name"
    fi
  done

  # Remove Traefik-related volumes
  log "Removing Traefik-related Docker volumes (if any)"
  docker volume ls -q --filter name=traefik_acme | xargs -r docker volume rm || true
  docker volume ls -q --filter name=traefik_traefik_acme | xargs -r docker volume rm || true

  # Remove the shared traefik_proxy network and any containers attached to it
  net_id=$(docker network ls -q --filter name=^traefik_proxy$) || true
  if [[ -n ${net_id:-} ]]; then
    # Find all containers attached to this network
    attached_containers=$(docker network inspect traefik_proxy -f '{{ range $id, $_ := .Containers }}{{$id}} {{ end }}' 2>/dev/null || echo "")
    if [[ -n "${attached_containers// /}" ]]; then
      log "Stopping and removing containers attached to traefik_proxy"
      for cid in ${attached_containers}; do
        # Try to resolve a friendly name for logging; fall back to ID
        cname=$(docker inspect -f '{{ .Name }}' "$cid" 2>/dev/null || echo "$cid")
        log "  - Removing container: ${cname#/}"
        docker stop "$cid" >/dev/null 2>&1 || true
        docker rm "$cid" >/dev/null 2>&1 || true
      done
    fi

    log "Removing Docker network: traefik_proxy"
    docker network rm traefik_proxy >/dev/null 2>&1 || true
  fi
else
  log "Docker not found; skipping container/network/volume cleanup."
fi

# 2. Stop and disable webhook systemd unit (if present)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^webhook.service'; then
    log "Stopping and disabling webhook.service (if running)"
    systemctl stop webhook.service 2>/dev/null || true
    systemctl disable webhook.service 2>/dev/null || true
  fi

  # Remove the unit file if it exists
  if [[ -f /etc/systemd/system/webhook.service ]]; then
    log "Removing /etc/systemd/system/webhook.service"
    rm -f /etc/systemd/system/webhook.service
    systemctl daemon-reload || true
  fi
fi

# 3. Remove sudoers rule used by webhook deploy (if present)
if [[ -f /etc/sudoers.d/webhook-deploy ]]; then
  log "Removing /etc/sudoers.d/webhook-deploy"
  rm -f /etc/sudoers.d/webhook-deploy
fi

# 4. Remove /opt/traefik tree
if [[ -d /opt/traefik ]]; then
  log "Removing /opt/traefik directory"
  rm -rf /opt/traefik
fi

log "Traefik cleanup complete. You can now re-run host_prep.sh and the rest of the README steps."