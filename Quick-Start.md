# Traefik-Deployment Quick Start

A concise, opinionated walkthrough for bringing up a hardened Traefik v3 reverse proxy on a fresh Linux host and getting ready to serve containerized sites.

This guide is focused on **first-time setup**. For deeper details about scripts and behavior, see the main `README.md` in this repository.

---

## 1. Before You Start

You will need:

- A Linux host (VPS or bare metal) with:
  - Public IP address
  - SSH access as a non-root user with sudo privileges
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

On your home directory on the **host server** (or from your personal workstation if you prefer), clone this repository to obtain the host preparation scripts. These scripts may be copied to the server via `scp`, or you may clone the repository directly on the server as your normal user.

```bash
git clone https://github.com/joshphillipssr/Traefik-Deployment.git
cd Traefik-Deployment/scripts
```

You will use:

- `host_prep_root.sh` — runs as **root**, does base OS + Docker + user setup
- `host_prep_deploy.sh` — runs as **deploy**, provisions Traefik itself

If you cloned the repository on your workstation, copy the two host prep scripts to the server (for example, into your home directory):

```bash
scp host_prep_root.sh host_prep_deploy.sh youruser@your-server:~
```

> **Why this matters:**
> At this stage, Traefik is *not* installed yet. The authoritative clone of this repository will later be created automatically by `host_prep_deploy.sh` inside:
>
> ```text
> /opt/traefik
> ```
>
> You should **not** manually clone the repository into `/opt/traefik`. Let the provisioning script handle this to ensure permissions and layout are correct.

---

## 3. Step One — Prepare the Host (root)

SSH into the server as your normal user (if not there already):

```bash
ssh youruser@your-server
```

Then escalate to root:

```bash
sudo -i
```

> **Note:** Direct SSH access as `root` is intentionally discouraged. If your system allows it, consider disabling it once provisioning is complete.

Make the first script executable and run it:

```bash
chmod +x host_prep_root.sh
./host_prep_root.sh
```

`host_prep_root.sh` is responsible for:

- Installing Docker Engine and Docker Compose
- Creating the `deploy` user with restricted sudo rights
- Creating `/opt/traefik` and `/opt/sites`
- Printing next steps for the deploy-side prep script

When it finishes, switch to `deploy` and run `host_prep_deploy.sh` once to bootstrap the repo and env file.

---

## 4. Bootstrap And Configure `~deploy/traefik.env`

Exit the root shell and switch to the `deploy` user:

```bash
su - deploy
```

Run deploy-side prep once to clone `/opt/traefik` and auto-create `~/traefik.env` if missing:

```bash
cd ~
chmod +x ~/host_prep_deploy.sh
./host_prep_deploy.sh
```

Then open the environment file:

```bash
nano ~/traefik.env
```

Fill in at least the following values:

```bash
CF_API_TOKEN="your-cloudflare-api-token"
EMAIL="you@example.com"
USE_STAGING=false
WEBHOOK_SECRET="ChangeThisSecretNow"
HOOKS_HOST="hooks.example.com"
```

Guidance:

- `CF_API_TOKEN` — Cloudflare token with DNS edit rights
- `EMAIL` — email used for Let’s Encrypt registration
- `USE_STAGING` — set to `true` when testing; `false` for production
- `WEBHOOK_SECRET` — shared secret used to verify GitHub webhooks
- `HOOKS_HOST` — hostname used when exposing webhook routes through Traefik

Save the file and exit.

> **Important:** `host_prep_deploy.sh` validates required values and exits with clear errors until placeholders are replaced.

---

## 5. Step Two — Provision Traefik (deploy)

From the `deploy` shell, make the second script executable and run it:

```bash
cd ~
chmod +x ~/host_prep_deploy.sh
./host_prep_deploy.sh
```

`host_prep_deploy.sh` will:

- Clone the Traefik-Deployment repo into `/opt/traefik`
- Ensure correct ownership and permissions on `/opt/traefik` and `/opt/sites`
- Create `~/traefik.env` from `traefik.env.sample` if needed
- Source and validate `~/traefik.env`
- Print follow-up commands for Traefik startup and optional webhook provisioning

After `host_prep_deploy.sh` succeeds, start Traefik:

```bash
/opt/traefik/scripts/traefik_up.sh
```

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

## 6. First App (Manual-First Deploy)

Once Traefik is up, onboard any app container with a dedicated hostname route.

From the `deploy` shell:

```bash
SITE_NAME=hello-app \
SITE_HOST=hello.example.com \
IMAGE=nginxdemos/hello:plain-text \
APP_PORT=80 \
/opt/traefik/scripts/onboard_generic_app.sh
```

This creates:

- `/opt/sites/hello-app/docker-compose.yml`
- Host-based Traefik labels bound to `hello.example.com`
- `traefik_proxy` network attachment

Manual deploy commands:

```bash
docker compose -f /opt/sites/hello-app/docker-compose.yml pull
docker compose -f /opt/sites/hello-app/docker-compose.yml up -d
```

Required label pattern for any app onboarding:

```text
traefik.enable=true
traefik.http.routers.<SITE_NAME>.rule=Host(`<SITE_HOST>`)
traefik.http.routers.<SITE_NAME>.entrypoints=websecure
traefik.http.routers.<SITE_NAME>.tls=true
traefik.http.routers.<SITE_NAME>.tls.certresolver=cf
traefik.http.services.<SITE_NAME>.loadbalancer.server.port=<APP_PORT>
```

After first deployment, updates can be handled with:

```bash
/opt/traefik/scripts/update_site.sh hello-app
```

---

## 7. Optional — Enable Automatic Deployments

To have GitHub automatically redeploy a site when a workflow completes:

### 7.1 Provision the webhook on the host

On the Traefik host, run the webhook provisioning script as root:

```bash
/opt/traefik/scripts/hooks_provision.sh
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
   - **Secret:** must match `WEBHOOK_SECRET` in `~deploy/traefik.env`
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

- Build out one or more app repos and publish images to GHCR
- Add GitHub Actions workflows that build and push Docker images to GHCR
- Wire additional sites to Traefik using unique hostnames and containers
- Harden host security, monitoring, and backups around this baseline

Once this Quick Start is complete, you have a repeatable pattern:

> **One host, one Traefik instance, many containerized sites, all behind Cloudflare, with automated TLS and optional CI/CD.**
