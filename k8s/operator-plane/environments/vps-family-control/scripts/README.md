# vps-family-control Scripts

This directory contains environment-level operator entrypoints for `vps-family-control`.

## Entrypoints

- `bootstrap-operator-plane.sh` orchestrates supported component bootstrap phases.
- `verify-operator-plane.sh` runs read-only operator-plane verification.

Component scripts under `traefik/scripts`, `openbao/scripts`, and `operator-artifacts/scripts` remain available for focused debugging.

## Secret Model

Global OpenBao is the operator-plane secret manager. Kubernetes Secrets are runtime projections or bootstrap imports, not the long-term source of truth.

Local `.env` files are bootstrap, import, and recovery material only. Do not commit them and do not paste their contents into issues, logs, or documentation.

Operator PKI is the next phase. The current scripts do not create an Operator CA and do not expose `operator-vault`.
