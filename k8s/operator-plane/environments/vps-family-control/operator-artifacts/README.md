# Operator Artifacts vps-family-control Environment

Environment-specific operator artifact repository material for `vps-family-control` belongs here.

Commit sanitized examples, manifests, scripts, and documentation only. Do not commit real artifacts, tenant tokens, certificates, private keys, or real domains.

## Validated state

Validated behavior for this environment:

- Traefik ACME DNS-01 OVH issues TLS for `operator-artifacts.<domain>`.
- The endpoint runs on Traefik `websecure`.
- IPAllowList is evaluated before BasicAuth.
- Allowed home IP with valid BasicAuth can download artifacts.
- Allowed home IP without credentials returns HTTP `401`.
- Non-allowed public path returns HTTP `403`.
- Normal curl from the VPS to the public FQDN is not a localhost test.
- Backend image is `nginxinc/nginx-unprivileged:stable-alpine`.
- Container listens on `8080`; Service exposes port `80`.
- Public artifacts are mounted read-only.
- The private artifact directory is not mounted.
- `.sha256` files use relative filenames.
- Temporary rendered manifests are cleaned up.

## Operator CA Bundle Artifact

The public Operator CA bundle is safe to publish through operator-artifacts.
The private Operator CA key remains inside OpenBao, and the `operator-vault`
leaf private key remains only in the OpenBao runtime TLS directory.

Publish and verify the public bundle with:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/publish-operator-ca-bundle.sh
./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/verify-operator-ca-bundle-artifact.sh
```

Artifact paths:

```text
/tenants/family-infra-01/trust/operator-ca-bundle.pem
/tenants/family-infra-01/trust/operator-ca-bundle.pem.sha256
```

Do not paste BasicAuth tokens in logs or docs. Publishing the CA bundle does
not expose `operator-vault`.

If the home public IP changes, update the IPAllowList and redeploy. If the token is rotated, regenerate htpasswd and reapply the deployment. Let's Encrypt renewals depend on OVH DNS-01 credentials.

Do not paste tokens, htpasswd contents, Kubernetes Secret data, or rendered manifests.
