# Prepare Local Artifact Storage And Token

This runbook prepares local VPS storage for the operator artifact repository and creates the initial tenant access token for `family-infra-01`.

This step prepares local VPS storage only. It does not deploy Kubernetes resources.

## Environment File

Create the real environment file from the example before running the scripts:

```text
k8s/operator-plane/environments/vps-family-control/operator-artifacts/operator-artifacts.env
```

The real `operator-artifacts.env` file is not committed to Git.

## Storage Separation

Public artifacts and private token material are separated:

```text
/var/lib/sovereignworkplaceservice/operator-artifacts/public
/var/lib/sovereignworkplaceservice/operator-artifacts/private
```

Only the public directory will later be mounted read-only into the artifact server pod.

Private token files must never be mounted into the artifact server pod.

## Prepare Local Directories

Run on the `vps-family-control` operator-plane VPS:

```bash
cd /path/to/sovereignworkplaceservice
sudo k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/prepare-local-operator-artifacts-files.sh
```

The script creates the public tenant directory, private token directory, a non-secret dummy artifact, and a checksum for that dummy artifact. It does not create certificates or tokens.

## Create Tenant Token

Run on the `vps-family-control` operator-plane VPS:

```bash
sudo k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/create-family-infra-01-artifact-token.sh
```

The script generates a strong random token and an htpasswd-compatible BasicAuth file for `family-infra-01`. It does not print the token value.

The generated token must be transferred to the tenant through a secure out-of-band channel. Do not paste the token into chat, tickets, logs, or Git.

Use `--force` only when intentionally rotating or replacing existing local token material:

```bash
sudo k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/create-family-infra-01-artifact-token.sh --force
```

## Safe Verification

Use metadata-only checks:

```bash
find /var/lib/sovereignworkplaceservice/operator-artifacts -maxdepth 4 -type d -ls
sudo ls -l /var/lib/sovereignworkplaceservice/operator-artifacts/public/tenants/family-infra-01
sudo ls -l /var/lib/sovereignworkplaceservice/operator-artifacts/private/tokens
```

Do not `cat` the token file. Do not print token values, htpasswd contents, or future artifact contents that expose operational metadata.

## Troubleshooting

If a script fails because `operator-artifacts.env` is missing, copy it from the example and edit the required values:

```bash
cp k8s/operator-plane/environments/vps-family-control/operator-artifacts/operator-artifacts.env.example \
  k8s/operator-plane/environments/vps-family-control/operator-artifacts/operator-artifacts.env
```

At minimum, edit or confirm:

- `OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME`
- `OPERATOR_ARTIFACTS_TENANT_NAME`
- `OPERATOR_ARTIFACTS_AUTH_USERNAME`

Do not commit the real `operator-artifacts.env` file.
