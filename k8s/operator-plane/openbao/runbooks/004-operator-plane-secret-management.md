# Operator Plane Secret Management

This runbook documents the target operator-plane secret model for `vps-family-control`.

Do not paste or commit secrets. Do not commit real domains, emails, public IPs, tokens, certificates, keys, htpasswd contents, OpenBao init material, or audit log contents.

## Target Model

Global OpenBao KV is the operator-plane source of truth for secrets and sensitive runtime configuration. Kubernetes Secrets are runtime projections generated from OpenBao or temporary bootstrap imports. Local `.env` files are bootstrap, import, and recovery material only.

Kubernetes workloads authenticate to OpenBao through Kubernetes auth. Do not store static OpenBao tokens in Kubernetes Secrets.

OpenBao transit keys and future PKI CA keys are OpenBao-managed state. They are not KV secrets and must not be exported into Git or local runbooks.

## OpenBao KV Paths

Initial operator-plane KV paths use the `operator-kv` KV v2 mount with explicit service and purpose boundaries:

- `operator-kv/operator-plane/traefik/ovh-dns01`
- `operator-kv/operator-plane/operator-artifacts/family-infra-01`
- `operator-kv/operator-plane/operator-artifacts/family-infra-01-config`

The registry is versioned at `k8s/operator-plane/openbao/secret-registry/operator-plane-secrets.yaml`. It contains paths, schemas, expected key names, and projections only. It must not contain values.

## Runtime Kubernetes Secrets

These Kubernetes Secrets are runtime projections:

- `kube-system/traefik-ovh-dns-credentials`
- `operator-artifacts/operator-artifacts-basicauth`

Verification may check Secret existence, type, and expected key names. It must not print `.data`, decoded values, `stringData`, htpasswd contents, tokens, or rendered Secret manifests containing live values.

The first sync implementation is the one-shot Job in `k8s/operator-plane/environments/vps-family-control/operator-secret-sync/`. It authenticates to OpenBao with the `operator-plane-secret-sync` Kubernetes auth role and the mounted ServiceAccount token.

## Local Bootstrap Material

The following local files are bootstrap, import, and recovery material only:

- `traefik-ovh-credentials.env`
- `operator-artifacts.env`
- `operator-plane.bootstrap-secrets.env`
- local artifact token files
- local htpasswd files

They must stay ignored by Git. The real `operator-plane.bootstrap-secrets.env` file should be copied from `operator-plane.bootstrap-secrets.env.example`, kept at `0600`, imported once, and retained only as bootstrap/import/recovery material. After import, OpenBao KV is the source of truth.

## Kubernetes Auth

The sync Job must use OpenBao Kubernetes auth:

- auth path: `kubernetes`
- role: `operator-plane-secret-sync`
- bound ServiceAccount: `operator-plane-secret-sync`
- bound namespace: `operator-secret-sync`
- policy: `operator-plane-secret-sync`
- TTL: `15m`

The policy is read-only for the required KV data paths and minimal metadata access. It does not allow transit, pki, sys, auth, audit, unrelated KV paths, or write operations.

The OpenBao server ServiceAccount needs TokenReview permission through `system:auth-delegator`. Use the explicit configuration script rather than creating long-lived reviewer tokens.

## TLS Trust

In-cluster clients must verify OpenBao TLS. The secret sync Job includes a placeholder CA bundle mount for `openbao-ca-bundle`.

Until Operator PKI is implemented, the current bootstrap CA or certificate authority bundle must be projected by an explicit safe procedure. Operator PKI will cleanly solve OpenBao CA bundle trust for in-cluster clients.

## Import And Sync TODO

Future work:

- Retire or archive local bootstrap files safely after OpenBao-backed sync is verified.
- Keep OpenBao transit keys as OpenBao-managed state.
- Implement the Operator PKI/CA as OpenBao-managed PKI state, not KV data.
- Do not run a destructive reinstall test until all debug points and Operator PKI are complete.
