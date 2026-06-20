# Operator Plane Secret Management

This runbook documents the target operator-plane secret model for `vps-family-control`.

Do not paste or commit secrets. Do not commit real domains, emails, public IPs, tokens, certificates, keys, htpasswd contents, OpenBao init material, or audit log contents.

## Target Model

Global OpenBao is the operator-plane authority for secrets. Kubernetes Secrets are runtime projections from OpenBao or temporary bootstrap imports. Local `.env` files are bootstrap, import, and recovery material only.

OpenBao transit keys and future PKI CA keys are OpenBao-managed state. They are not KV secrets and must not be exported into Git or local runbooks.

## OpenBao KV Paths

Initial operator-plane KV paths should use explicit service and purpose boundaries:

- `kv/operator-plane/traefik/ovh-dns01`
- `kv/operator-plane/operator-artifacts/family-infra-01`

The exact field names should be documented with sanitized examples only. Values must be imported from local bootstrap material by an operator and then synchronized to runtime targets without printing secret contents.

## Runtime Kubernetes Secrets

These Kubernetes Secrets are runtime projections or bootstrap imports:

- `kube-system/traefik-ovh-dns-credentials`
- `operator-artifacts/operator-artifacts-basicauth`

Verification may check Secret existence, type, and expected key names. It must not print `.data`, decoded values, `stringData`, htpasswd contents, tokens, or rendered Secret manifests containing live values.

## Local Bootstrap Material

The following local files are bootstrap, import, and recovery material only:

- `traefik-ovh-credentials.env`
- `operator-artifacts.env`
- local artifact token files
- local htpasswd files

They must stay ignored by Git. They are not the steady-state source of truth once OpenBao KV import and synchronization exist.

## Import And Sync TODO

Future work:

- Import current operator-plane secrets into OpenBao KV.
- Add sync scripts from OpenBao KV to Kubernetes Secrets.
- Retire or archive local bootstrap files safely after OpenBao-backed sync is verified.
- Keep OpenBao transit keys as OpenBao-managed state.
- Implement the Operator PKI/CA as OpenBao-managed PKI state, not KV data.
