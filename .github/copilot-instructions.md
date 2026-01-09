# Copilot Instructions — Traefik-Deployment

## Project Overview

Production-grade **Traefik v3** reverse proxy infrastructure for hosting multiple containerized sites on a single Linux host. Uses Cloudflare DNS-01 for automatic TLS certificates and systemd webhooks for zero-downtime deployments.

**Key principle**: One Traefik instance, many site containers sharing the `traefik_proxy` Docker network.

## Architecture

```
Client → Cloudflare → Traefik (port 80/443) → Site Containers (Docker)
                          ↓
                    Webhook Service (systemd)
```

- **Traefik**: Listens on container ports 8080/8443, published as host 80/443
- **Sites**: Run as separate containers, routed via Traefik labels
- **Webhooks**: systemd service (NOT Docker) triggers deployments via GitHub Actions

## Directory Structure (on host)

```
/opt/
  traefik/
    docker/docker-compose.yml    # Traefik static config
    scripts/                     # All lifecycle scripts
    hooks/hooks.json             # Webhook definitions
  sites/
    <SITE_NAME>/
      docker-compose.yml         # Generated per-site
      scripts/                   # Site-specific scripts
```

**Critical**: All configuration comes from `~deploy/traefik.env` (mode 0600).

## Environment Variables (traefik.env)

```bash
CF_API_TOKEN=          # Cloudflare DNS-01 API token (Zone.DNS:Edit + Zone.Zone:Read)
EMAIL=                 # Let's Encrypt registration email
USE_STAGING=false      # true for LE staging (testing/rate limits)
WH_SECRET=             # Webhook HMAC signature secret
HOSTNAME=              # Primary Traefik hostname (e.g., traefik.example.com)
DEFAULT_SITE_REPO=     # Optional default site template repo
DEFAULT_SITE_TEMPLATE= # Optional template identifier
```

## Script Patterns

### Standard Header
```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Path Resolution
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

### Environment Sourcing
```bash
ENV_FILE="${TRAEFIK_ENV_FILE:-/home/deploy/traefik.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi
```

### Sudo Re-exec Pattern
```bash
need_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=VAR1,VAR2 "${BASH_SOURCE[0]}" "$@"
  fi
}
```

### Required Variable Validation
```bash
: "${SITE_NAME:?SITE_NAME required}"
: "${SITE_HOSTS:?SITE_HOSTS required}"
```

## Two-Phase Provisioning

**Phase 1** (`host_prep_root.sh` — as root):
- Installs Docker Engine + Compose plugin
- Creates `deploy` user with restricted sudoers
- Creates `/opt/traefik` and `/opt/sites` owned by `deploy`
- Copies `traefik.env.sample` to `~deploy/traefik.env`

**Phase 2** (`host_prep_deploy.sh` — as deploy):
- Sources `~deploy/traefik.env`
- Clones Traefik-Deployment repo into `/opt/traefik`
- Creates `traefik_proxy` network via `create_network.sh`
- Starts Traefik via `traefik_up.sh`

**Critical**: Never run Phase 2 as root—must switch to `deploy` user.

## Site Deployment

**Bootstrap** (once per site):
```bash
sudo SITE_REPO="https://github.com/user/site.git" \
     SITE_DIR="/opt/mysite" \
     /opt/traefik/scripts/bootstrap_site_on_host.sh
```

**Deploy** (first time):
```bash
sudo SITE_NAME="mysite" \
     SITE_HOSTS="example.com www.example.com" \
     SITE_IMAGE="ghcr.io/user/site:latest" \
     /opt/sites/mysite/scripts/deploy_to_host.sh
```

**Update** (automated or manual):
```bash
sudo -u deploy /opt/traefik/scripts/update_site.sh mysite
```

## Traefik Labels Pattern

Generated in `deploy_to_host.sh`:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<site>.entrypoints=websecure"
  - "traefik.http.routers.<site>.tls.certresolver=cf"
  - "traefik.http.routers.<site>.rule=Host(`example.com`) || Host(`www.example.com`)"
  - "traefik.http.services.<site>.loadbalancer.server.port=80"
```

## Webhook System

**Why systemd not Docker?**: Webhooks need sudo to restart containers, which containers cannot safely have.

**Service**: `/etc/systemd/system/webhook.service`  
**Config**: `/opt/traefik/hooks/hooks.json`  
**Listener**: `127.0.0.1:9000` (proxied by Traefik)

**Provisioning**:
```bash
sudo /opt/traefik/scripts/hooks_provision.sh
```

**Validation rules**:
- Event type: `workflow_run` ONLY
- Action: `completed`
- Conclusion: `success`
- Valid HMAC-SHA256 signature (matches `$WH_SECRET`)

## Security Model

- Docker daemon runs as root (standard)
- `deploy` user has limited sudo via `/etc/sudoers.d/`
- Traefik container runs as UID 65532, read-only filesystem + tmpfs
- Cloudflare token has minimal scope (DNS edit + zone read only)
- **Never commit secrets**—only in `~deploy/traefik.env`

## Common Operations

View Traefik logs:
```bash
cd /opt/traefik/docker && docker compose logs -f
```

View webhook logs:
```bash
journalctl -u webhook -f
```

Nuclear cleanup:
```bash
sudo /opt/traefik/scripts/cleanup.sh
```

## AI Agent Guidelines

- Preserve script patterns: `set -euo pipefail`, path resolution, env sourcing
- Never embed secrets—always reference `~deploy/traefik.env`
- Respect two-phase privilege separation (root prep → deploy operations)
- Generate Traefik labels following exact pattern in `deploy_to_host.sh`
- Test webhook changes against `hooks.json` schema and systemd requirements
- When editing, validate against **Quick-Start.md** and **README.md** workflows
- All scripts must be clone-and-deploy ready (no hardcoded values)

## Known Issues & Patterns

1. **Script naming**: Repository uses `host_prep_root.sh` and `host_prep_deploy.sh` (not `host_prep1.sh`/`host_prep2.sh` mentioned in some docs)
2. **Network creation**: Must happen before any site deployment
3. **Cloudflare SSL**: Must be "Full (strict)", not "Flexible"
4. **GHCR packages**: Default to private—must set to Public for unauthenticated pulls
5. **Event types**: Webhooks ONLY work with `workflow_run`, not `push` or `release`
