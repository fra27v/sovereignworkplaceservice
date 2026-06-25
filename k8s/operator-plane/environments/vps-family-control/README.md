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

Operator PKI foundation files are present under `operator-pki/`. They configure
an OpenBao-managed Operator CA and export only the public CA bundle. They do not
yet issue or install the final `operator-vault` runtime TLS certificate and do
not expose `operator-vault`.

The exported Operator CA bundle is the future trust source for in-cluster
clients such as `operator-secret-sync`. The sync runner image is still not
selected, and the sync Job remains blocked by install preflight until a pinned
standard runner image is validated.

Do not run a destructive reinstall test until Operator PKI, operator-vault TLS,
artifact publication, and final debug points are complete.
