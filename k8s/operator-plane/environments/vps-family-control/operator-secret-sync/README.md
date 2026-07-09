# Operator Secret Sync

This directory contains the first one-shot Kubernetes Job for projecting operator-plane secrets from Global OpenBao KV into runtime Kubernetes Secrets.

OpenBao KV is the source of truth. Kubernetes Secrets are runtime projections. Local `.env` files are bootstrap, import, and recovery material only.

## OpenBao CA Bundle Projection

Before the operator-secret-sync Job can verify OpenBao TLS, the public Operator CA bundle must be available. The `scripts/install-openbao-ca-bundle-configmap.sh` script projects the public Operator CA bundle from `OPERATOR_PKI_PUBLIC_DIR/operator-ca-bundle.pem` into the `operator-secret-sync` namespace as a ConfigMap with key `ca.crt`.

This is public trust material only; it does not contain secrets. The ConfigMap is created with `kubectl apply` and is idempotent. The projection is a separate phase from operator-vault TLS rotation because:

- The CA bundle is needed to verify OpenBao TLS during secret sync
- The CA bundle only changes when the Operator CA rotates, not on every leaf certificate rotation
- The projection can run at any time and should be included in `--all` bootstrap

The verification script `scripts/verify-openbao-ca-bundle-configmap.sh` confirms that the ConfigMap exists and matches the source file's SHA256 checksum.

## Foundation Phase

The target foundation phase prepares the resources the future one-shot Job will
need without creating or running that Job:

- Namespace: `operator-secret-sync`
- ServiceAccount: `operator-secret-sync/operator-plane-secret-sync`
- Least-privilege RBAC in `kube-system` for `traefik-ovh-dns-credentials`
- Least-privilege RBAC in `operator-artifacts` for `operator-artifacts-basicauth`
- ConfigMap: `operator-secret-sync/operator-plane-secret-sync-script`
- ConfigMap: `operator-secret-sync/openbao-ca-bundle`
- Global OpenBao Kubernetes auth method, policy, and role for the ServiceAccount

The foundation installer uses the normal repository script file
`scripts/sync-operator-plane-secrets.sh` to build the script ConfigMap. It does
not hand-copy the script into YAML, does not select a runner image, and does not
run the sync Job.

The foundation RBAC grants `get`, `update`, and `patch` only for the expected
Secret names. It intentionally does not grant `create` because Kubernetes RBAC
cannot safely restrict `create` by `resourceNames`. The future Job/run phase
must either pre-create the target Secrets or deliberately revise that RBAC with
a documented create tradeoff.

## Why A Job

The sync runs in Kubernetes so the workload can authenticate to OpenBao with Kubernetes auth and its mounted ServiceAccount token. This avoids storing static OpenBao tokens in Kubernetes Secrets.

The Job is one-shot rather than a CronJob because the first version is meant to be explicit and reviewable during bootstrap. A reconciler or scheduled sync can be added later after the trust and PKI model is complete.

## Authentication

The Job uses:

- Namespace: `operator-secret-sync`
- ServiceAccount: `operator-plane-secret-sync`
- OpenBao auth path: `kubernetes`
- OpenBao role: `operator-plane-secret-sync`
- OpenBao policy: `operator-plane-secret-sync`

The future Job uses the same ServiceAccount. In the foundation stage, that
ServiceAccount is bound only to namespace-scoped Roles that can get, update,
and patch the expected Secret names in:

- `kube-system`
- `operator-artifacts`

The sync namespace manifest also ensures the `operator-artifacts` namespace exists because the `--all` bootstrap order configures secret sync before the operator-artifacts workload is installed. It has no access to unrelated namespaces and does not touch `trading`.

The full Job stage must remain explicit until the runner image and Secret
creation/update behavior are finalized.

## Secret Projections

The sync script reads:

- `operator-kv/operator-plane/traefik/ovh-dns01`
- `operator-kv/operator-plane/operator-artifacts/family-infra-01`

It creates or updates:

- `kube-system/traefik-ovh-dns-credentials`
- `operator-artifacts/operator-artifacts-basicauth`

For `operator-artifacts`, the script derives the `users` htpasswd line inside the pod from `username` and `token`. The chosen implementation uses `openssl passwd -apr1 -stdin` because it avoids passing the token as a command-line argument and keeps the required image small. The generated htpasswd line is never echoed.

## Runner Image Contract

No custom image is created at this stage and no image registry is introduced at this stage.

The environment dependency lock is the source of truth for runtime image
intent:

```text
../dependencies.lock.json
```

The Job must use a pinned standard runner image that satisfies
`image-contract.md`. The `latest` tag is forbidden, and digest pinning is
required before the real sync Job can run.

The current runner image candidate is recorded in the dependency lock as
`docker.io/alpine/k8s:1.35.4`. It is a candidate only; `job.yaml` intentionally
uses an invalid placeholder image reference, and the install script fails before
applying the Job until a valid pinned standard runner image is selected and the
manifest is updated through a future explicit phase.

Validate the candidate from `dependencies.lock.json` through Kubernetes before
enabling the real Job:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/validate-runner-image-contract.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image
```

The validation uses a temporary no-secret Kubernetes Job on the k3s/containerd
runtime path. It does not use Docker, does not use the real
`operator-plane-secret-sync` ServiceAccount, does not mount OpenBao trust or
Kubernetes Secrets, does not call OpenBao, does not run the real sync Job, and
does not mutate target runtime Secrets.

The validation workload keeps the pod unprivileged, disables ServiceAccount
token automount, drops Linux capabilities, and uses a read-only root
filesystem. It does not force `runAsNonRoot` for v1 because the standard
candidate image may not declare a non-root user.

That image must provide:

- `bash`
- `curl`
- `jq`
- `kubectl`
- `openssl`
- `openssl passwd -apr1` support
- CA certificates

`htpasswd` is optional because the current sync script uses `openssl passwd -apr1 -stdin` for BasicAuth hash generation.

The image must not install packages or download binaries at pod startup.
Updating the runner image is a separate operational step. No custom image is
created for v1. A custom image may be reconsidered later only if no acceptable
standard runner image satisfies the contract.

The sync logic is kept as a normal repository script at:

```text
scripts/sync-operator-plane-secrets.sh
```

The install script creates the runtime ConfigMap from that file with `kubectl create configmap --from-file ... --dry-run=client -o yaml | kubectl apply -f -`. This keeps the script easy to review and lint without requiring an image build for every sync logic change.

Resolve a digest through the target k3s/containerd tooling:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/resolve-image-digest.sh --image 'docker.io/alpine/k8s:1.35.4'
```

Review the RepoDigest candidate, then manually copy the selected `sha256`
digest into `dependencies.lock.json`. The helper does not edit repository
files. The older `check-runner-image-contract.sh` Docker path is deprecated and
non-authoritative.

Future vulnerability management means selecting an updated pinned image reference, rerunning the contract check, updating `job.yaml`, and reapplying the Job through the normal install flow. It does not require changing the sync script unless the tool contract changes.

Changing runtime images starts by changing `../dependencies.lock.json`.
Applying that change to Kubernetes is a separate future update phase. k3s
managed dependencies and Helm-managed dependencies have their own update flows;
the operator-secret-sync runner image is repository-managed through the Job
manifest. The runner image uses the validate-then-enable-Job flow and requires
Kubernetes validation plus digest pinning before real Job execution.
Introducing a custom runner image requires an explicit ADR.

## Bootstrap Env Parser

The OpenBao bootstrap import script uses a strict parser for `operator-plane.bootstrap-secrets.env`. It does not `source` the env file and does not execute shell syntax from it.

The parser accepts only blank lines, full-line comments, and `KEY=VALUE` entries for known required keys. It rejects duplicate keys, unknown keys, `export KEY=VALUE`, command substitution, backticks, multiline values, missing required keys, and empty required values.

## OpenBao TLS

The Job defaults to:

```text
https://openbao-global.openbao-operator.svc:8200
```

It does not use insecure TLS skip verification by default.

The manifest requires a ConfigMap volume named `openbao-ca-bundle` mounted at:

```text
/var/run/openbao-ca/ca.crt
```

The install script preflights that `operator-secret-sync/openbao-ca-bundle` exists and contains a non-empty `ca.crt` key before applying the Job. The verify script checks the ConfigMap and key name only. Certificate contents are never printed.

Until Operator PKI is implemented, the current bootstrap CA or certificate authority bundle must be projected into that ConfigMap by an explicit, safe procedure. Operator PKI will cleanly solve OpenBao CA bundle trust for in-cluster clients.

## Apply And Verify

Install and verify the foundation:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync-foundation.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync-foundation.sh
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/verify-operator-secret-sync-foundation.sh
```

The broad verifier distinguishes foundation from future Job/run work:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/verify-operator-secret-sync.sh
```

Use the full Job installer only after choosing a pinned standard runner image:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync.sh
```

The install script does not run destructive cleanup. It only deletes an old Job with the exact same name before reapplying the Job, because Kubernetes Job pod templates are immutable.

No real secrets are stored in Git. Scripts must not print Kubernetes Secret
data, OpenBao tokens, private keys, certificate PEM contents, ciphertext,
plaintext, or issuance JSON.
