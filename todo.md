

# Traefik-Deployment — TODO

This file tracks follow-up items, refinements, and hardening tasks identified during development and testing. Items are not necessarily blockers unless explicitly marked.

---
## High Priority (Post-Initial Validation)

- [ ] Decide and document the final policy for script executability:
  - Option A: Ensure all scripts are committed with executable bit set; remove `chmod +x` from `host_prep_deploy.sh`.
  - Option B: Keep `chmod +x` and explicitly document that the repo will appear dirty after first run.

- [ ] Resolve `traefik.env` creation order:
  - Either clone the repo before `load_env` in `host_prep_deploy.sh`, or
  - Automatically create `~/traefik.env` from `traefik.env.sample` if missing after clone.

- [ ] Review and tighten sudoers model:
  - Decide between docker group access vs `sudo docker` (avoid doing both).
  - Expand sudoers only as required for site lifecycle and webhook execution.

---
## Medium Priority (Hardening & Consistency)

- [ ] Ensure required packages are installed explicitly (e.g., `git`) before first use.

- [ ] Final consistency pass between:
  - Quick-Start.md
  - README.md
  - `host_prep_root.sh`
  - `host_prep_deploy.sh`

- [ ] Validate behavior on a truly minimal Debian/Ubuntu VPS image.

- [ ] Decide whether `TRAEFIK_DIR`, `SITES_DIR`, and `DEPLOY_USER` should be:
  - Fully script-authoritative, or
  - Fully driven by `traefik.env`.

---
## Automation & Webhooks

- [ ] Review `hooks_provision.sh` against the latest env strategy.

- [ ] Verify webhook sudoers rules are minimal and correct.

- [ ] Add explicit validation and error messaging for missing `WH_SECRET` and `HOOKS_HOST`.

---
## Documentation Enhancements

- [ ] Add a small "Common Mistakes" section to Quick-Start.md.

- [ ] Consider adding a short privilege-flow diagram (user → root → deploy).

- [ ] Decide whether to include a brief explanation of the two-phase host prep philosophy.

---
## Testing & Validation

- [ ] End-to-end test: clean host → Traefik up → first site deployed.

- [ ] Test idempotence of:
  - `host_prep_root.sh`
  - `host_prep_deploy.sh`
  - `create_network.sh`
  - `traefik_up.sh`

- [ ] Confirm cleanup scripts fully revert host to a reusable baseline.

---
## Future / Nice-to-Have

- [ ] Optional helper script for full host reset (for lab/testing environments).

- [ ] Optional linting or shellcheck CI for scripts.

- [ ] Evaluate making site template repo fully generic and renamed.