# operator-secret-sync Runner Image Contract

No custom image is built at this stage. No image registry is introduced at this stage.

The `operator-secret-sync` Job must use a pinned standard runner image. The `latest` tag is forbidden. Digest pinning is preferred when the selected image is finalized.

The runner image must not install packages or download binaries at pod startup. Updating the runner image is a separate operational step from changing sync logic.

Changing sync logic should not require rebuilding an image. The sync script remains a normal versioned repository file and the install script creates the runtime ConfigMap from that file.

A custom image may be reconsidered later only if no acceptable standard runner image satisfies this contract.

## Required Tools

The runner image must provide:

- `bash`
- `curl`
- `jq`
- `kubectl`
- `openssl`
- `openssl passwd -apr1` support
- CA certificates

The current sync script uses `openssl passwd -apr1 -stdin` for htpasswd-compatible BasicAuth hash generation.

## Optional Tools

The runner image may also provide:

- `htpasswd`

`htpasswd` is optional when `openssl passwd -apr1` is available and verified.

## Selection State

The runner image is not selected yet. `job.yaml` intentionally contains an invalid placeholder image reference so install preflight fails before execution.

Before running the sync Job, select a pinned standard runner image that satisfies this contract and update `job.yaml`.

Validate the candidate without secrets:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/check-runner-image-contract.sh --image '<pinned-image-ref>' --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/check-runner-image-contract.sh --image '<pinned-image-ref>'
```

The first command checks only the reference shape and prints safe metadata. The second command uses the local container runtime to verify the required tools. Do not use `latest`.
