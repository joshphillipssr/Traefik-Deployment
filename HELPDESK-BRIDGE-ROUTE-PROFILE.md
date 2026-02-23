# Helpdesk Bridge Route Profile

Host-based route profile for deploying Helpdesk Bridge behind Traefik.

## Active Hostname (Current Constraint)

```text
cfhidta-helpdesk-bridge.joshphillipssr.com
```

Reason:

- Current DNS-01 token scope is limited to `joshphillipssr.com`.
- Certificate issuance for bridge traffic must stay in that zone until `cfhidta.org` token access is available.

## Planned Cutover Hostname

```text
helpdesk-bridge.cfhidta.org
```

Use this host after a valid `cfhidta.org` DNS token is in place for Traefik ACME DNS-01.

## Routing Model

- Host-based routing only
- Cloudflare proxy only
- TLS via Traefik resolver `cf`
- Bridge app handles endpoint paths directly

Expected endpoint paths on the same host:

- `/health`
- `/webhooks`

## Deployment Example (Current Hostname)

```bash
SITE_NAME=helpdesk-bridge \
SITE_HOST=cfhidta-helpdesk-bridge.joshphillipssr.com \
IMAGE=ghcr.io/central-florida-hidta/helpdesk-bridge:latest \
APP_PORT=8080 \
/opt/traefik/scripts/onboard_generic_app.sh
```

## Verification Commands

Run after bridge container is deployed:

```bash
curl -I https://cfhidta-helpdesk-bridge.joshphillipssr.com/health
curl -I https://cfhidta-helpdesk-bridge.joshphillipssr.com/webhooks
```

Expected:

- HTTPS handshake succeeds (no Cloudflare 525/526)
- `/health` returns app-defined health status
- `/webhooks` reaches bridge handler (status may vary by method/auth)
