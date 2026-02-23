# Traefik-Deployment — Hardened Traefik Host Toolset

A fully-opinionated, production-grade deployment model for running **Traefik v3**, **Cloudflare DNS‑01**, **multi‑site container routing**, and **secure system‑level automation** on a single Linux host.

This repository provides the authoritative scripts and configuration required to provision Traefik, manage site containers, and (optionally) enable GitHub‑driven automated deployments.

---

## 🧭 Architecture Summary

```text
Client → Cloudflare → Traefik → Site Containers (Docker)
```

All components run on one Linux VPS/host. Traefik and all sites run as Docker containers. Automation is handled by a hardened systemd webhook service.

Traefik and all sites share the Docker network:

```text
traefik_proxy
```

The host file layout is standardized and required:

```text
/opt/
  traefik/
    docker-compose.yml
    scripts/
    hooks/
    volumes/
  sites/
    <site-name>/
```

---

## 🔐 Environment Variables — Single Source of Truth

All secrets and configuration live **only** in:

```text
~deploy/traefik.env
```

Expected variables:

```text
CF_API_TOKEN=
EMAIL=
USE_STAGING=false
WEBHOOK_SECRET=
HOOKS_HOST=
TRAEFIK_REPO_URL=
TRAEFIK_DIR=/opt/traefik
SITES_DIR=/opt/sites
DEPLOY_USER=deploy
```

`host_prep_deploy.sh` enforces that `CF_API_TOKEN`, `EMAIL`, and `WEBHOOK_SECRET` are set to non-placeholder values before it completes. `HOOKS_HOST` should be set before enabling webhook routing.

All scripts source this file. No secrets appear inside `/opt`, compose files, or repositories.

---

## 🛠 Host Preparation (Two-Step)

Provisioning Traefik requires two scripts: one run as **root**, one run as **deploy**.

### **Step 1 — host_prep_root.sh (run as root)**

- Installs Docker & Docker Compose
- Creates `deploy` user with restricted sudoers entries
- Creates `/opt/traefik` and `/opt/sites`
- Instructs operator to log in as deploy and run deploy-side prep

### **Step 2 — host_prep_deploy.sh (run as deploy)**

- Clones Traefik‑Deployment repo into `/opt/traefik`
- Ensures permissions
- Creates `~deploy/traefik.env` from `traefik.env.sample` if missing
- Sources and validates `~deploy/traefik.env` with clear error messages for missing/placeholder required values
- Prints next commands to start Traefik (`traefik_up.sh`) and optional webhook provisioning

---

## 🚦 Starting Traefik

Traefik runs from the static compose file in `/opt/traefik/docker-compose.yml`.

```bash
cd /opt/traefik
./scripts/traefik_up.sh
```

This ensures:

- ACME DNS‑01 via Cloudflare
- Automatic certificate issuance & renewal
- Dashboard available via secure hostname (if configured)

---

## 🌐 Generic App Onboarding (Manual First)

Sites live under:

```text
/opt/sites/<SITE_NAME>/
```

Use the generic onboarding script to scaffold a per-app compose file:

```bash
SITE_NAME=<site-name> \
SITE_HOST=<public-hostname> \
IMAGE=<container-image> \
APP_PORT=<container-port> \
/opt/traefik/scripts/onboard_generic_app.sh
```

Example:

```bash
SITE_NAME=helpdesk-bridge \
SITE_HOST=cfhidta-helpdesk-bridge.joshphillipssr.com \
IMAGE=ghcr.io/central-florida-hidta/helpdesk-bridge:latest \
APP_PORT=8080 \
/opt/traefik/scripts/onboard_generic_app.sh
```

Bridge hostname is `cfhidta-helpdesk-bridge.joshphillipssr.com`.
This is the standing operational host due `cfhidta.org` DNS authority being constrained by Wix-managed nameservers.

The script:

- Ensures the shared `traefik_proxy` Docker network exists
- Generates `/opt/sites/<SITE_NAME>/docker-compose.yml`
- Applies host-based Traefik labels for dedicated hostname routing
- Leaves deploy as manual-first by default (`docker compose pull` + `docker compose up -d`)

Generated labels follow this pattern:

```text
traefik.enable=true
traefik.http.routers.<SITE_NAME>.rule=Host(`<SITE_HOST>`)
traefik.http.routers.<SITE_NAME>.entrypoints=websecure
traefik.http.routers.<SITE_NAME>.tls=true
traefik.http.routers.<SITE_NAME>.tls.certresolver=cf
traefik.http.services.<SITE_NAME>.loadbalancer.server.port=<APP_PORT>
```

For immediate deploy on scaffold, set `DEPLOY_NOW=true`.
After first deployment, future updates can be automated by webhook or run manually.

Helpdesk-specific route profile details are documented in `HELPDESK-BRIDGE-ROUTE-PROFILE.md`.

---

## 🔄 Updating a Site Manually

```bash
sudo /opt/traefik/scripts/update_site.sh <SITE_NAME>
```

Pulls latest GHCR image and restarts the container.

---

## 🧨 Removing a Site

```bash
sudo /opt/traefik/scripts/remove_site.sh <SITE_NAME>
```

Deletes the site directory and container.

---

## 🎛 Traefik Dashboard (Optional)

Dashboard enablement requires hostname‑based routing and a basic‑auth middleware. Example labels are included in the Traefik container’s docker‑compose.yml.

---

## 🔔 Automatic Deployments (systemd Webhook)

The webhook listener:

- Accepts **workflow_run** events from GitHub
- Validates signature using `$WEBHOOK_SECRET`
- Calls `update_site.sh <SITE_NAME>` under restricted `deploy` permissions

Provision using:

```bash
/opt/traefik/scripts/hooks_provision.sh
```

This installs:

- `webhook.service`
- `/opt/traefik/hooks/hooks.json`
- sudoers rules

Webhook URL format:

```text
https://hooks.<your-domain>/hooks/deploy-<site>
```

---

## 🧹 Cleanup Tools

### Traefik Cleanup

```bash
/opt/traefik/scripts/cleanup.sh
```

Removes Traefik, webhook, systemd units, Docker network, and all containers using it.

### Site Cleanup

```bash
/opt/traefik/scripts/remove_site.sh <SITE_NAME>
```

Removes the site container and directory.

---

## 📚 Notes & Best Practices

- Follow Cloudflare prerequisites in [CLOUDFLARE-SETUP.md](CLOUDFLARE-SETUP.md)
- Never store secrets outside `~deploy/traefik.env`
- GitHub Actions must build/push images to GHCR
- Webhooks must use **workflow_run** only
- All scripts are idempotent and safe to rerun

---

## 📜 License

MIT
**Repository**: <https://github.com/joshphillipssr/Traefik-Deployment>
