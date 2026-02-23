# Cloudflare Setup Baseline

Canonical Cloudflare prerequisites for services deployed behind this Traefik platform.

Use this checklist before onboarding any site (including VitePress-derived sites and webhook endpoints).

## 1. Zone Activation

- Ensure the target domain is an active Cloudflare zone.
- Confirm registrar nameservers are delegated to Cloudflare.

## 2. DNS Records

Create DNS records for hostnames you will route through Traefik:

- Root host (example `@` -> server public IP)
- `www` host (example `www` -> root host or same IP)
- Optional webhook host (example `hooks` -> server public IP)

Set each routed record to **Proxied** (orange cloud).

## 3. SSL/TLS Mode

Set Cloudflare SSL/TLS mode to:

```text
Full (strict)
```

This requires a valid certificate at the origin (Traefik will obtain certificates through ACME DNS-01 when configured correctly).

## 4. API Token For DNS-01

Create a Cloudflare API token scoped to the target zone with:

- `Zone.Zone:Read`
- `Zone.DNS:Edit`

Store token value in Traefik environment as:

```text
CF_API_TOKEN
```

## 5. Optional CAA Check

If CAA records are enforced for the zone, ensure Let's Encrypt issuance is allowed.

## 6. Verification

After deployment:

```bash
curl -I https://<hostname>
```

Expected:

- HTTPS handshake succeeds
- Valid certificate is presented
- App responds with expected status (`200/301/302` depending on app behavior)
