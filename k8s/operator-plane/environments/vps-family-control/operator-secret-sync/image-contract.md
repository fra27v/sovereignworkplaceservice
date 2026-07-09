# operator-secret-sync Runner Image Contract

No custom image is built at this stage. No image registry is introduced at this stage.

The `operator-secret-sync` Job must use a pinned standard runner image. The `latest` tag is forbidden. Digest pinning is required before the real sync Job can run.

The runner image must not install packages or download binaries at pod startup. Updating the runner image is a separate operational step from changing sync logic.

Changing sync logic should not require rebuilding an image. The sync script remains a normal versioned repository file and the install script creates the runtime ConfigMap from that file.

A custom image may be reconsidered later only if no acceptable standard runner image satisfies this contract.

## Required Tools

The runner image must provide:

- `bash`
- `curl`
- `jq`
- `kubectl`
- CA certificates

The runner does not require the `openssl` CLI and must not generate BasicAuth
hashes at runtime.

## Secret Value Model

OpenBao KV stores final Kubernetes Secret data values. The sync Job copies
authorized fields into Kubernetes Secrets without generating, hashing,
encrypting, decrypting, or otherwise transforming secret material except for
the JSON and base64 handling required by APIs.

For operator-artifacts BasicAuth, the OpenBao KV field `users` must already
contain the final htpasswd content. Host/bootstrap/import tooling may prepare
that value outside the runner, but the sync Job copies `users` verbatim into
the Kubernetes Secret key `users`.

## Selection State

The runner image is not selected yet. `job.yaml` intentionally contains an invalid placeholder image reference so install preflight fails before execution.

The candidate is read from:

```text
../dependencies.lock.json
```

Before running the sync Job, validate the candidate, copy the reviewed
`sha256` digest into `dependencies.lock.json`, and update `job.yaml` to use the
reviewed digest.

Validate the candidate without secrets:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/validate-runner-image-contract.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image
```

The validation creates only a temporary Kubernetes Job in
`operator-secret-sync`, with no Secret mounts and no real sync ServiceAccount.
It uses the k3s/Kubernetes/containerd runtime path, not Docker. It does not
call OpenBao, does not run the real sync Job, and does not mutate target
runtime Secrets.

The deprecated `check-runner-image-contract.sh` Docker path is
non-authoritative and intentionally disabled.
