
# Traefik-Deployment Quick Start

A concise, opinionated walkthrough for bringing up a hardened Traefik v3 reverse proxy on a fresh Linux host and getting ready to serve containerized sites.

This guide is focused on **first-time setup**. For deeper details about scripts and behavior, see the main `README.md` in this repository.

---

## 1. Before You Start

You will need:

- A Linux host (VPS or bare metal) with:
  - Public IP address
  - SSH access as **root**
- A domain managed by **Cloudflare**
- A GitHub account (for hosting site repos and Docker images)
- Basic familiarity with SSH, Docker, and Git

### 1.1 Cloudflare DNS & SSL prerequisites

In Cloudflare for your domain:

1. Create an **A** (or AAAA) record for the Traefik host, e.g.:
   - `@` → your server IP (for `example.com`)
   - `hooks` → your server IP (for `hooks.example.com`, used by webhooks)
   - Any site hostnames you plan to use, e.g. `docs.example.com`
2. Set SSL/TLS mode to **Full (strict)**.
3. Create a **Cloudflare API token** with permissions suitable for DNS-01 challenge (e.g. edit DNS for your zone).

You will paste this API token into `~deploy/traefik.env` later.

---

## 2. Get the Host Prep Scripts

On your **workstation**, clone this repository:

```bash
git clone https://github.com/joshphillipssr/Traefik-Deployment.git
cd Traefik-Deployment/scripts
```

You will use:

- `host_prep1.sh` — runs as **root**, does base OS + Docker + user setup
- `host_prep2.sh` — runs as **deploy**, provisions Traefik itself

Copy these two scripts to your target server (e.g. with `scp`):

```bash
scp host_prep1.sh host_prep2.sh root@your-server:/root/
```

---

## 3. Step One — Prepare the Host (root)

SSH into the server as **root**:

```bash
ssh root@your-server
```

Make the first script executable and run it:

```bash
cd /root
chmod +x host_prep1.sh
./host_prep1.sh
```

`host_prep1.sh` is responsible for:

- Installing Docker Engine and Docker Compose
- Creating the `deploy` user with restricted sudo rights
- Creating `/opt/traefik` and `/opt/sites`
- Fetching `traefik.env.sample` and copying it to:
  - `~deploy/traefik.env`
- Printing a message telling you to log in as `deploy`

When it finishes, do **not** run Traefik yet. First, you must configure the environment file.

---

## 4. Configure `~deploy/traefik.env`

Still on the server, switch to the `deploy` user:

```bash
su - deploy
```

Open the environment file created by `host_prep1.sh`:

```bash
nano ~/traefik.env
```

Fill in at least the following values:

```bash
CF_API_TOKEN="your-cloudflare-api-token"
EMAIL="you@example.com"
USE_STAGING=false
WH_SECRET="ChangeThisSecretNow"
HOSTNAME="your-traefik-hostname"        # e.g. traefik.example.com or your main site
DEFAULT_SITE_REPO="<optional-default-site-template-repo>"
DEFAULT_SITE_TEMPLATE="<optional-template-id-or-path>"
```

Guidance:

- `CF_API_TOKEN` — Cloudflare token with DNS edit rights
- `EMAIL` — email used for Let’s Encrypt registration
- `USE_STAGING` — set to `true` when testing; `false` for production
- `WH_SECRET` — shared secret used to verify GitHub webhooks
- `HOSTNAME` — hostname that will terminate TLS on this Traefik instance
- `DEFAULT_SITE_*` — optional defaults for your site template workflow

Save the file and exit.

> **Important:** All other scripts rely on this file. If it is missing or incomplete, provisioning will fail.

---

## 5. Step Two — Provision Traefik (deploy)

From the `deploy` shell, make the second script executable and run it:

```bash
cd ~
chmod +x ~/host_prep2.sh
./host_prep2.sh
```

`host_prep2.sh` will:

- Source `~/traefik.env`
- Clone the Traefik-Deployment repo into `/opt/traefik`
- Ensure correct ownership and permissions on `/opt/traefik` and `/opt/sites`
- Create the shared Docker network `traefik_proxy`
- Bring Traefik online via `traefik_up.sh`

If everything succeeds, you should have:

- A running Traefik container
- A persistent volume for ACME certificates
- A stable `/opt/traefik` layout ready for sites

### 5.1 Verifying Traefik

As `deploy`, check containers:

```bash
docker ps
```

You should see a `traefik` container listening on ports 80 and 443 on the host.

You can also view logs:

```bash
cd /opt/traefik
docker compose logs -f
```

Look for messages indicating successful ACME configuration and that entrypoints `web` and `websecure` are ready.

---

## 6. First Site (Manual Deploy Overview)

Once Traefik is up, you can attach site containers behind it. At a high level, you will:

1. Build and push a Docker image for your site to GHCR (via a GitHub Actions workflow).
2. Provide Traefik with:
   - A **site name**
   - One or more **hostnames**
   - The **image reference** (e.g. `ghcr.io/youruser/yourimage:latest`)
3. Use the provided scripts to generate a per-site `docker-compose.yml` and start the container.

The exact steps (including `bootstrap_site_on_host.sh` and `deploy_to_host.sh`) live in your **site template repository**. That repo is responsible for:

- Cloning itself into `/opt/sites/<SITE_NAME>`
- Creating `/opt/sites/<SITE_NAME>/docker-compose.yml`
- Attaching the site container to `traefik_proxy`
- Setting Traefik labels to route `Host(...)` to the site container

After the **first** deployment of a site, future updates can be automated with webhooks.

---

## 7. Optional — Enable Automatic Deployments

To have GitHub automatically redeploy a site when a workflow completes:

### 7.1 Provision the webhook on the host

On the Traefik host (typically as `root` via sudo), run the webhook provisioning script provided by this repo:

```bash
sudo /opt/traefik/scripts/hooks_provision.sh
```

This will:

- Install a `webhook` systemd service
- Create `/opt/traefik/hooks/hooks.json`
- Configure sudoers so the webhook can call `update_site.sh` as `deploy`

### 7.2 Configure GitHub webhook

In your site’s GitHub repository:

1. Go to **Settings → Webhooks**.
2. Add a new webhook:
   - **Payload URL:**

     ```text
     https://hooks.<your-domain>/hooks/deploy-<site>
     ```

   - **Content type:** `application/json`
   - **Secret:** must match `WH_SECRET` in `~deploy/traefik.env`
   - **Which events?** Choose **Let me select individual events** and enable **Workflow runs**.

Now, whenever your GitHub Actions workflow successfully builds and pushes a new image, GitHub will:

- POST a `workflow_run` event to your webhook URL
- The webhook service will validate the signature
- On success, it will call:

```bash
sudo -u deploy /opt/traefik/scripts/update_site.sh <SITE_NAME>
```

Your site container will be refreshed with the latest image with no manual SSH required.

---

## 8. Useful Commands & Checks

A few handy commands once everything is up:

```bash
# As deploy

# Check containers
docker ps

# Check Traefik logs
cd /opt/traefik
docker compose logs -f

# Manually refresh a site
sudo /opt/traefik/scripts/update_site.sh <SITE_NAME>

# Remove a site entirely
sudo /opt/traefik/scripts/remove_site.sh <SITE_NAME>

# Full Traefik + webhook cleanup (nuclear option)
sudo /opt/traefik/scripts/cleanup.sh
```

---

## 9. Next Steps

From here you can:

- Build out one or more site repos using the VitePress template
- Add GitHub Actions workflows that build and push Docker images to GHCR
- Wire additional sites to Traefik using unique hostnames and containers
- Harden host security, monitoring, and backups around this baseline

Once this Quick Start is complete, you have a repeatable pattern:

> **One host, one Traefik instance, many containerized sites, all behind Cloudflare, with automated TLS and optional CI/CD.**
