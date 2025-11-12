# Traefik-Deployment

Reusable, Docker-first reverse proxy setup with **Traefik** + **Let's Encrypt (DNS-01 via Cloudflare)** and small scripts to deploy multiple sites behind a single proxy.

## Quick start (server)

```bash
# one-time: clone repo to server
sudo git clone https://github.com/joshphillipssr/Traefik-Deployment.git /opt/traefik
cd /opt/traefik

# create the shared network (idempotent)
sudo ./traefik/scripts/create_network.sh

# bring up Traefik (HTTPS auto via Cloudflare DNS-01)
sudo CF_API_TOKEN="your_cf_token" EMAIL="you@example.com" USE_STAGING=false \
  ./traefik/scripts/traefik_up.sh

# deploy a site
sudo ./traefik/scripts/deploy_site.sh \
  SITE_NAME="jpsr" \
  SITE_HOSTS="joshphillipssr.com www.joshphillipssr.com" \
  SITE_IMAGE="ghcr.io/joshphillipssr/jpsr-site:latest"
```

## Repository Overview

This repository is organized as follows:

```
/traefik
  /configs          # Configuration files for Traefik and related services
  /scripts          # Helper scripts to manage Traefik and site deployments
  /data             # Persistent data storage for Traefik (certificates, etc.)
README.md           # This documentation file
```

- **configs/** contains Traefik static and dynamic configuration files.
- **scripts/** includes shell scripts to create networks, start Traefik, deploy, update, and remove sites.
- **data/** stores persistent Traefik data such as certificates and ACME challenge information.

## Environment Variables

The following environment variables are used to configure Traefik and the deployment scripts:

- `CF_API_TOKEN`: Your Cloudflare API token with DNS edit permissions. Required for DNS-01 challenge to issue Let's Encrypt certificates.
- `EMAIL`: Email address used for Let's Encrypt registration and expiry notifications.
- `USE_STAGING`: Set to `true` to use Let's Encrypt's staging environment for testing (avoids rate limits). Set to `false` for production usage.

Make sure to keep these values secure and do not commit them to version control.

## Included Scripts

- `create_network.sh`: Creates a Docker network shared by Traefik and site containers.
- `traefik_up.sh`: Starts or restarts the Traefik proxy with the appropriate environment variables and configurations.
- `deploy_site.sh`: Deploys a new site container behind Traefik with specified hostname(s) and image.
- `update_site.sh`: Updates an existing deployed site container to a new image or configuration.
- `remove_site.sh`: Removes a deployed site container and its associated Traefik routing.

## Webhook Deployment Automation

A lightweight webhook listener (`hooks_up.sh`) is included to enable automatic site updates triggered by GitHub Actions webhooks.

### How It Works

When your GitHub Actions workflow completes successfully (e.g., a Docker image build and push), GitHub can send a webhook to your server. The webhook listener receives the event, verifies its signature, and then calls `update_site.sh` to pull and redeploy the latest image for the site.

### Deployment Steps

1. **Run the setup script:**

   ```bash
   sudo /opt/traefik/traefik/scripts/hooks_up.sh
   ```

   This script will:
   - Create `/opt/traefik/hooks` with necessary files
   - Generate `docker-compose.yml` for the webhook listener (running behind Traefik)
   - Write a starter `hooks.json` with a deploy rule for your site (`deploy-jpsr`)
   - Add a sudoers rule allowing only the exact update command
   - Bring up the webhook container on the shared `traefik_proxy` network

2. **Configure GitHub Webhook:**

   - Go to your repository → **Settings → Webhooks → Add Webhook**
   - **Payload URL:** `https://hooks.joshphillipssr.com/hooks/deploy-jpsr`
   - **Content type:** `application/json`
   - **Secret:** use the same value as in `/opt/traefik/hooks/hooks.json`
   - **Events:** select **Workflow runs**

3. **Testing the Webhook:**

   - Push to the `main` branch so the GitHub Action builds and pushes your Docker image.
   - Check logs on your server:
     ```bash
     docker logs webhook -f
     ```
   - You should see confirmation of the event and automatic redeploy for your site container.

4. **Adding Another Site Hook:**

   - Copy the existing hook entry in `/opt/traefik/hooks/hooks.json`
   - Change:
     - `"id"` → unique name (e.g. `deploy-newsite`)
     - The `"name"` value passed to `deploy-site.sh`
     - Replace with a new random secret
   - Add the corresponding webhook in the new site’s GitHub repository.
   - No need to restart — the webhook container hot-reloads the JSON file.

### Notes

- Each site uses its own secret for verification.
- The listener runs read-only and minimal privileges.
- If you need to update the webhook config, edit `/opt/traefik/hooks/hooks.json` and Traefik will continue serving without restart.

## Updating and Removing Sites

To update an existing site, run:

```bash
sudo ./traefik/scripts/update_site.sh \
  SITE_NAME="jpsr" \
  SITE_IMAGE="ghcr.io/joshphillipssr/jpsr-site:newtag"
```

To remove a deployed site, run:

```bash
sudo ./traefik/scripts/remove_site.sh \
  SITE_NAME="jpsr"
```

## Notes and Best Practices

- **Do not commit secrets or API tokens** to your repository. Use environment variables or secret management tools.
- Configure your Cloudflare SSL/TLS mode to **Full (strict)** to ensure end-to-end encryption.
- Let's Encrypt certificates are automatically managed by Traefik using the DNS-01 challenge via Cloudflare API.
- Use the `USE_STAGING` variable to test your setup without hitting Let's Encrypt production rate limits.

## License

This project is licensed under the MIT License.
