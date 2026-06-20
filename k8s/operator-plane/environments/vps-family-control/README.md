# VPS Family Control Operator Environment

This environment is the family infrastructure control plane on a VPS target.

The files in this directory are examples and placeholders. They do not install
k3s or deploy platform services.

Host baseline tooling is documented in `runbooks/001-host-baseline-tools.md`.
Use `scripts/check-host-baseline-tools.sh` to verify required commands and
`scripts/install-host-baseline-apt-tools.sh` to install only apt-managed
baseline tools.

## Operator Plane Bootstrap

The environment-level operator entrypoints are:

- `scripts/bootstrap-operator-plane.sh`
- `scripts/verify-operator-plane.sh`

Manual component scripts remain available under `traefik/scripts`,
`openbao/scripts`, and `operator-artifacts/scripts` for debugging. The target
operator interface is the environment bootstrap script plus the environment
verification script.

Global OpenBao KV is the operator-plane source of truth for secrets and
sensitive runtime configuration. Kubernetes Secrets are runtime projections or
bootstrap imports, not the long-term source of truth. Local `.env` files are
bootstrap, import, and recovery material only.

In-cluster operator-plane sync uses OpenBao Kubernetes auth. Do not store static
OpenBao tokens in Kubernetes Secrets.

Operator PKI is the next phase. This environment does not yet create an
Operator CA or expose `operator-vault`. Operator PKI will cleanly solve OpenBao
CA bundle trust for in-cluster clients.

Do not run a destructive reinstall test until all debug points and Operator PKI
are complete.
