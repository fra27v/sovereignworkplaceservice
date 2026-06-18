# Family Infrastructure Environment

`family-infra` is the active k3s operational environment for the family
infrastructure.

## Current Scope

The current scope is the k3s baseline only:

- example k3s server configuration
- config preparation script
- k3s installation wrapper
- baseline verification script

Traefik installation and application migration are out of scope for now.

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

## Runbooks

- `runbooks/004-install-k3s.md`

Do not commit generated local files such as `/etc/rancher/k3s/config.yaml` or
`/etc/rancher/k3s/k3s.yaml`.
