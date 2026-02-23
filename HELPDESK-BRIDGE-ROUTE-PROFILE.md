# Helpdesk Bridge Route Profile

Host-based route profile for deploying Helpdesk Bridge behind Traefik.

## Operational Hostname

```text
cfhidta-helpdesk-bridge.joshphillipssr.com
```

Reason:

- `cfhidta.org` is currently Wix-managed with nameserver constraints.
- Bridge DNS and DNS-01 certificate issuance must remain under `joshphillipssr.com`.

## Routing Model

- Host-based routing only
- Cloudflare proxy only
- TLS via Traefik resolver `cf`
- Bridge app handles endpoint paths directly

Expected endpoint paths on the same host:

- `/health`
- `/webhooks`

## Deployment Example

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

## Future Re-Hostname (Optional)

If DNS authority for `cfhidta.org` changes in the future, reassess cutover to:

```text
helpdesk-bridge.cfhidta.org
```
