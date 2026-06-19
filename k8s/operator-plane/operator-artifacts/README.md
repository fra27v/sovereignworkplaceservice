# Operator Artifacts

Operator-plane artifact repository configuration and runbooks belong here.

The logical service endpoint is `operator-artifacts.<domain>`. It is separate from `operator-vault.<domain>` and is used for tenant outbound HTTPS artifact pulls.

Real artifacts, tenant tokens, certificates, signatures, and private keys must stay outside Git unless they are explicitly sanitized placeholders.

## Validated state

Validated on `vps-family-control`:

- Traefik ACME DNS-01 OVH works.
- A Let's Encrypt certificate is issued for `operator-artifacts.<domain>`.
- `operator-artifacts` runs behind Traefik on `websecure`.
- Access is protected by IPAllowList first, then BasicAuth.
- Allowed home IP with valid BasicAuth can download artifacts.
- Allowed home IP without credentials returns HTTP `401`.
- Non-allowed public path returns HTTP `403`.
- Normal curl from the VPS to the public FQDN is not a localhost test.
- Backend image is `nginxinc/nginx-unprivileged:stable-alpine`.
- Container listens on `8080`; Kubernetes Service exposes port `80`.
- Public artifacts directory is mounted read-only.
- Private artifact directory is not mounted.
- `.sha256` files use relative filenames and are portable.
- Temporary rendered manifests are cleaned up.

Operational notes:

- If the home public IP changes, update the IPAllowList and redeploy.
- If the token is rotated, regenerate htpasswd and reapply the deployment.
- Let's Encrypt renewals depend on OVH DNS-01 credentials.
- Do not paste tokens, htpasswd contents, Kubernetes Secret data, or rendered manifests.

Runbooks:

- `runbooks/001-operator-artifacts-architecture.md`
- `runbooks/002-prepare-local-artifact-storage-and-token.md`
- `runbooks/003-deploy-operator-artifacts.md`
