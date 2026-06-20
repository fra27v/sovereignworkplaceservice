# Bootstrap And Verify Operator Plane

This runbook documents the first environment-level bootstrap and verification entrypoints for `vps-family-control`.

The goal is to make the operator plane repeatable without hiding the component scripts that are still useful for focused debugging.

## Entrypoints

Use these environment-level scripts as the operator interface:

- `k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh`
- `k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh`

Component scripts remain available under `traefik/scripts`, `openbao/scripts`, and `operator-artifacts/scripts` for debugging and explicit runbook steps. The final operator interface should converge on bootstrap plus verify.

## Current Supported Phases

The bootstrap entrypoint currently supports:

- Traefik ACME DNS-01 OVH setup
- Global OpenBao baseline verification
- `operator-artifacts`

Global OpenBao install, initialization, transit setup, and audit setup remain delegated to their explicit component runbooks until stable environment-level entrypoints are validated.

## Current TODO Phases

Future work:

- OpenBao KV secret import and synchronization into Kubernetes Secrets
- Operator PKI
- `operator-vault` TCP passthrough through Traefik
- final destructive reinstall test

Do not run destructive wipe behavior until the final phase is explicitly designed and reviewed.

## Safe Examples

Preview the Traefik phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --traefik --dry-run
```

Preview the `operator-artifacts` phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-artifacts --dry-run
```

Run read-only verification:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh
```

## Safety Rules

- Do not paste secrets.
- Do not commit real domains, emails, public IPs, tokens, certificates, keys, htpasswd contents, OpenBao init material, or audit log contents.
- Do not print Kubernetes Secret `.data` or `stringData`.
- Do not run destructive wipe behavior until the final phase.
- Do not touch `trading`.
- Do not treat local `.env` files as the final source of truth.

## Secret Authority

Global OpenBao is the operator-plane secret manager. It will also host the Operator PKI/CA in the next phase.

Kubernetes Secrets are runtime projections or bootstrap imports. Local `.env` files are bootstrap, import, and recovery material only.
