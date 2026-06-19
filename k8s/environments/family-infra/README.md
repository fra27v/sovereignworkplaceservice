# Family Infrastructure Environment

`family-infra` is the active k3s operational environment for the family
infrastructure.

## Current Scope

The current scope includes the verified k3s baseline, the runtime Traefik
instance, and environment tests:

- example k3s server configuration
- config preparation script
- k3s installation wrapper
- baseline verification script
- reusable runtime Traefik installation and verification
- versioned whoami routing smoke test
- regression test entrypoint

Application migration remains out of scope for now.

## DNS Assumption

`family-infra.internal` must point to the k3s node. It is included in the k3s
TLS SAN list so the node certificate can be used with that internal name.

## Scripts

The operational scripts are in `scripts/`:

- `prepare-k3s-config.sh` copies the example config to
  `/etc/rancher/k3s/config.yaml`.
- `install-k3s.sh` installs k3s if it is not already installed.
- `verify-k3s.sh` checks the baseline node state, secrets encryption,
  kubeconfig permissions, disabled embedded Traefik, and key ports.
- `setup-family-infra.sh` is the command wrapper for `prepare`, `install`,
  `verify`, and `all`.

Traefik runtime scripts live under
`k8s/platform/components/traefik/scripts/`.

## Tests

Environment tests are in `tests/`:

- `tests/smoke/whoami-routing/` verifies HTTP routing through the runtime
  Traefik instance.
- `tests/regression/run.sh` runs the k3s baseline verification, Traefik
  verification, and whoami routing smoke test in order.
- `tests/e2e/`, `tests/security/`, and `tests/backup-restore/` are placeholders
  for future test categories.

## Runbooks

- `runbooks/004-install-k3s.md`
- `runbooks/005-install-traefik.md`
- `runbooks/006-run-regression-tests.md`

## Current Status

- k3s baseline OK
- Traefik runtime OK
- whoami routing OK
- regression suite OK

Do not commit generated local files such as `/etc/rancher/k3s/config.yaml` or
`/etc/rancher/k3s/k3s.yaml`.
