# AGENTS Instructions: Traefik-Deployment

Scope:
- Applies only to this repository.

Routing cutover safety requirements:
- Before and after Traefik cutovers on shared hosts, list live router host rules and priorities.
- Confirm no host collisions (duplicate/overlapping host rules) remain before handoff.
- Keep deployment and cutover steps in this repository's docs/runbooks.

Placement rule:
- Keep these Traefik-specific operational instructions in this repo-level `AGENTS.md`, not in parent cross-repo instructions.
