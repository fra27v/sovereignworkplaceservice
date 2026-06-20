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
- CA certificates
- a tool or method for htpasswd-compatible BasicAuth hash generation

The current sync script uses `openssl passwd -apr1 -stdin` for htpasswd-compatible BasicAuth hash generation.

## Selection State

The runner image is not selected yet. `job.yaml` intentionally contains an invalid placeholder image reference so install preflight fails before execution.

Before running the sync Job, select a pinned standard runner image that satisfies this contract and update `job.yaml`.
