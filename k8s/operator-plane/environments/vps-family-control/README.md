# VPS Family Control Operator Environment

This environment is the family infrastructure control plane on a VPS target.

The files in this directory are examples and placeholders. They do not install
k3s or deploy platform services.

Host baseline tooling is documented in `runbooks/001-host-baseline-tools.md`.
Use `scripts/check-host-baseline-tools.sh` to verify required commands and
`scripts/install-host-baseline-apt-tools.sh` to install only apt-managed
baseline tools.
