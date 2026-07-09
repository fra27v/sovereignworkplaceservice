# Dependency Policy

`dependencies.lock.json` is the authoritative machine-readable source of truth for
`vps-family-control` runtime dependency intent.

The lock records:

- k3s platform ownership and k3s-managed components
- Helm-managed OpenBao release, chart, and app versions
- repository-managed runtime images
- candidate runtime images that are not yet active
- host tools required by scripts

The previous YAML lock format is not active. Dependency validation uses `jq`
against JSON. Do not add handwritten YAML parsing in Bash and do not introduce
`yq` for this lock.

## Pinning Rules

Runtime images must not use `:latest`.

Floating tags such as `stable`, `stable-alpine`, `edge`, and `main` are allowed
in the lock only when the entry is explicitly marked `needs-pinning`. They are
technical debt and must be replaced by a pinned tag or digest in a future update
phase.

Candidate images without a digest are allowed only when marked `candidate`.
They produce verifier warnings, not failures. Selecting and running a candidate
requires a separate explicit phase.

Real Job execution requires digest pinning.

The operator-secret-sync runner candidate is read from
`dependencies.lock.json` and validated through the explicit
`--operator-secret-sync-runner-image` bootstrap phase. That validation uses a
temporary Kubernetes workload on the k3s/containerd runtime path. Docker-based
runner checks are deprecated and are not authoritative.
The selected runner candidate is digest-pinned in the lock, but the real sync
Job remains disabled until the Job manifest is updated to use the validated tag
plus digest.

Do not invent digests. Add a digest only after it is obtained from a trusted
registry or release source during an update phase.

## Update Flows

k3s-managed dependencies are updated through the k3s platform flow. The
repository records ownership and the live version check command, but does not
pretend to manage k3s binaries or bundled components.

Helm-managed dependencies are updated through the Helm release flow. For Global
OpenBao, update `openbao/openbao` chart/app versions in
`openbao/openbao-global.versions.env`, then update `dependencies.lock.json` in
the same change.

Repository-managed images are updated by changing the lock plus the manifest or
Job template that consumes the image. Future update phases apply those manifest
changes to the cluster.

Validate-then-enable-Job dependencies, such as the future operator-secret-sync
runner image, must be validated before Job execution. The validation phase does
not run the real sync Job, does not mount Secrets, and does not mutate target
runtime Secrets. It confirms only the no-secret runner image contract.

The operator-secret-sync runner contract intentionally excludes `openssl`.
BasicAuth hash generation is prepared by host/bootstrap/import tooling before
sync. OpenBao KV stores the final `users` value, and the sync Job copies that
value into Kubernetes without generating hashes at runtime.

Custom images require an explicit ADR before introduction. The ADR must explain
why a pinned standard image is insufficient, where the image is built, how it is
scanned, and how updates are tracked.

## Verification

Run:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/verify-dependencies-lock.sh
```

The verifier is static. It does not mutate Kubernetes state, pull images, run
Jobs, or read secrets.

The global verifier does not pull runner images or create validation Jobs. Run
the active runner image validation only through:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image
```
