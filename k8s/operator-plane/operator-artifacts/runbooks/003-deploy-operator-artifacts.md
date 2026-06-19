# Deploy Operator Artifacts

This runbook deploys the initial `operator-artifacts` HTTPS endpoint for the
`vps-family-control` operator-plane environment.

The endpoint distributes bootstrap and configuration artifacts to tenants. It
must not serve private keys, root tokens, recovery material, static seal keys,
init JSON files, htpasswd files, or tenant token files.

## Prerequisites

- Traefik DNS-01 OVH is configured and verified.
- Local operator artifact directories have been prepared.
- The tenant token and htpasswd file have been generated.
- `operator-artifacts.<domain>` DNS points to the VPS.
- The real `operator-artifacts.env` file exists locally and is not committed to
  Git.

The local storage and token preparation step is documented in:

```bash
k8s/operator-plane/operator-artifacts/runbooks/002-prepare-local-artifact-storage-and-token.md
```

## Render

Render the manifest without applying it:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/render-operator-artifacts.sh
```

The render script reads the real local `operator-artifacts.env` file and the
local htpasswd file. It must not print token values, htpasswd contents,
Kubernetes Secret `.data`, or `stringData`.

Rendered manifests may contain BasicAuth Secret material in `stringData`.
Render and install scripts clean temporary rendered manifests by default.

Use `--keep-output` only for short manual inspection. The kept rendered manifest
uses `0600` permissions, but it still contains sensitive BasicAuth material and
must be deleted immediately after inspection.

Do not paste rendered manifests into chat, logs, tickets, or Git.

Legacy cleanup for older script runs that used a predictable output path:

```bash
sudo rm -f /tmp/operator-artifacts.yaml
```

## Install

Install the rendered resources:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/install-operator-artifacts.sh
```

The install script renders to a temporary file, applies the manifest with
`kubectl apply -f`, verifies resource metadata, and checks that only the public
artifact directory is mounted into the Deployment.

The private artifact directory must never be mounted into the artifact server
pod. The temporary rendered manifest is created with `0600` permissions and is
deleted after install.

## Nginx Read-Only Root Filesystem

The `operator-artifacts` Deployment keeps `readOnlyRootFilesystem: true`.
Artifact content remains mounted read-only from the public artifact hostPath at
`/usr/share/nginx/html`, and the private artifact directory remains unmounted.

If the nginx pod enters `CrashLoopBackOff` after enabling the read-only root
filesystem, check whether nginx is missing writable runtime directories. The
manifest provides writable `emptyDir` mounts for:

- `/var/cache/nginx`
- `/var/run`
- `/tmp`
- `/var/log/nginx`

These writable mounts are runtime scratch space only. They do not contain
artifact content, tenant tokens, htpasswd files, or private artifact material.

## Verify

Run the verification script:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/verify-operator-artifacts.sh
```

The verification script checks:

- the pod is `Running`
- the Service is `ClusterIP`
- the IngressRoute exists
- the BasicAuth Secret exists without printing Secret data
- the private artifact directory is not mounted
- the public artifact hostPath is mounted read-only
- nginx writable runtime paths are backed by `emptyDir`

## Authenticated Dummy Artifact Test

After deployment, test the dummy artifact with a real token only in a local
terminal on the operator host or tenant host:

```bash
curl -fsS -u 'family-infra-01:<token>' https://operator-artifacts.<domain>/tenants/family-infra-01/README.txt
curl -fsS -u 'family-infra-01:<token>' https://operator-artifacts.<domain>/tenants/family-infra-01/README.txt.sha256
```

Use `<token>` as a placeholder in documentation and chat. Never paste commands
that contain real credentials.

## Sensitive Material Rules

Do not paste or commit:

- tenant tokens
- htpasswd files or htpasswd lines
- Kubernetes Secret `.data`
- Kubernetes Secret `stringData`
- rendered manifests containing BasicAuth material
- curl commands containing real credentials

Kubernetes Secret values are base64-encoded when displayed through `.data`; they
are not safe to paste into chat, tickets, logs, or Git.

The real tenant token must later be transferred to the tenant through a secure
out-of-band channel. It is not distributed through this public artifact
endpoint.

## Notes

This runbook deploys the artifact endpoint only. It does not define the final
artifact signing model, IP allowlisting, mTLS client authentication, or a
private artifact registry.
