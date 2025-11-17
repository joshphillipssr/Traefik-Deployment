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

Required variables:

```text
CF_API_TOKEN=
EMAIL=
USE_STAGING=false
WH_SECRET=
HOSTNAME=
DEFAULT_SITE_REPO=
DEFAULT_SITE_TEMPLATE=
```

All scripts source this file. No secrets appear inside `/opt`, compose files, or repositories.

---

## 🛠 Host Preparation (Two-Step)

Provisioning Traefik requires two scripts: one run as **root**, one run as **deploy**.

### **Step 1 — host_prep1.sh (run as root)**

- Installs Docker & Docker Compose
- Creates `deploy` user with restricted sudoers entries
- Creates `/opt/traefik` and `/opt/sites`
- Copies `traefik.env.sample` to `~deploy/traefik.env`
- Instructs operator to log in as deploy

### **Step 2 — host_prep2.sh (run as deploy)**

- Sources `~deploy/traefik.env`
- Clones Traefik‑Deployment repo into `/opt/traefik`
- Ensures permissions
- Runs `create_network.sh`
- Brings Traefik online using `traefik_up.sh`

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

## 🌐 Deploying a Site (First Deployment)

Sites live under:

```text
/opt/sites/<SITE_NAME>/
```

To bootstrap a site from its template repo:

```bash
/opt/sites/<SITE_NAME>/scripts/bootstrap_site_on_host.sh
```

To deploy a site to Traefik:

```bash
/opt/sites/<SITE_NAME>/scripts/deploy_to_host.sh
```

This:

- Generates a Traefik‑aware docker-compose.yml
- Connects container to `traefik_proxy`
- Applies correct Traefik labels
- Starts the container

After this one-time deployment, future deploys can be automated.

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
- Validates signature using `$WH_SECRET`
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
/opt/sites/<SITE_NAME>/scripts/cleanup.sh
```

Removes the site container and directory.

---

## 📚 Notes & Best Practices

- Configure Cloudflare SSL mode: **Full (strict)**
- Never store secrets outside `~deploy/traefik.env`
- GitHub Actions must build/push images to GHCR
- Webhooks must use **workflow_run** only
- All scripts are idempotent and safe to rerun

---

## 📜 License

MIT
**Repository**: <https://github.com/joshphillipssr/Traefik-Deployment>