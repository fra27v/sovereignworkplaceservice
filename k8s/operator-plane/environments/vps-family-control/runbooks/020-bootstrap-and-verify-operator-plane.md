# Bootstrap And Verify Operator Plane

This runbook documents the first environment-level bootstrap and verification entrypoints for `vps-family-control`.

The goal is to make the operator plane repeatable without hiding the component scripts that are still useful for focused debugging.

## Entrypoints

Use these environment-level scripts as the operator interface:

- `k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh`
- `k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh`

Component scripts remain available under `traefik/scripts`, `openbao/scripts`, and `operator-artifacts/scripts` for debugging and explicit runbook steps. The final operator interface should converge on bootstrap plus verify.

## Local Shell Syntax Checks

On Linux and on the VPS target, use normal `bash -n` syntax checks before
running shell scripts.

On Windows hosts without WSL, `bash` may resolve to the WSL stub and fail
because no WSL distribution is installed. Do not interpret that WSL-stub
failure as a script syntax failure. Use Git Bash explicitly for local syntax
checks instead:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -n <script>
```

Prefer validating deployment scripts on the Linux VPS before
execution-sensitive phases.

## Environment Entry Point

`k8s/operator-plane/environments/vps-family-control/operator-plane.env` is the
single normal operational env file for this environment. Create it from
`operator-plane.env.example`, keep it ignored by Git, and set permissions to
`0600`.

Do not create component-specific real env files for operator-plane components.
`operator-artifacts.env` is not used as an operational source. Avoid
duplicated values across variables: derive public service hostnames from the
central base domain and derive internal DNS names from service, namespace, and
cluster DNS suffix values.

`dependencies.lock.json` is the authoritative machine-readable source of truth for
environment runtime dependency intent. It records k3s-managed components,
Helm-managed releases, repository-managed runtime images, runner image
candidates, and host tooling. Changing the lock plus running the relevant
future update phase updates components; the lock itself does not mutate the
cluster.

The dependency lock is JSON and is validated with `jq`. Do not add manual YAML
parsing for dependency inventory validation.

Some scripts run with `sudo` for host filesystem writes. On Linux, `sudo`
changes `$HOME` to `/root`, but Global OpenBao init material remains under the
operator user's bootstrap directory unless explicitly configured otherwise. Set
`OPENBAO_BOOTSTRAP_INIT_FILE` in `operator-plane.env` to the existing local
bootstrap init JSON path. This variable is a path only; the file it points to
contains sensitive OpenBao init material. Do not copy init material to `/root`,
and do not paste or commit the init JSON contents.

## Current Supported Phases

The bootstrap entrypoint currently supports:

- Traefik ACME DNS-01 OVH setup
- Global OpenBao baseline verification
- Global OpenBao `operator-kv` KV v2 mount configuration
- OpenBao CA bundle projection into operator-secret-sync namespace
- operator-secret-sync foundation without running the sync Job
- operator-secret-sync runner image validation without running the sync Job
- explicit operator-secret-sync real Job phase with `--operator-secret-sync-job`
- `operator-artifacts`
- Operator PKI configure and verify
- explicit `operator-vault` runtime TLS issuance and install with `--operator-vault-tls`

Global OpenBao install, initialization, transit setup, and audit setup remain delegated to their explicit component runbooks until stable environment-level entrypoints are validated.

k3s-managed dependencies are updated through the k3s platform flow.
Helm-managed dependencies, including Global OpenBao, are updated through their
Helm release flow. Repository-managed images, including operator-artifacts and
the operator-secret-sync runner, are updated by changing the dependency
lock and the consuming manifest together. Custom images require an explicit ADR
before introduction.

The operator-artifacts nginx runtime image is digest-pinned in
`dependencies.lock.json`. The operator-artifacts renderer consumes that lock
entry and renders `tag@sha256` into the Deployment. Updating nginx requires
resolving a new trusted registry digest and committing the lockfile plus
consumer change before redeploying from Git state.

Note: the Global OpenBao transit configure entrypoint is idempotent and will
reconcile missing transit keys or policy state without overwriting an existing
tenant token JSON. The configure script will not print token material.

The `--openbao-operator-kv` phase enables the versioned `operator-kv/` KV v2
mount in Global OpenBao when it is missing. It is idempotent, uses the `bao`
CLI inside the configured Global OpenBao pod, and uses the Operator CA bundle
inside the pod for client trust. It fails if `operator-kv/` exists but is not
KV v2.

Operator PKI bootstrap configures the OpenBao PKI mount, Operator CA,
`operator-vault` issuance role, and public CA bundle export. The separate
`--operator-vault-tls` phase issues the `operator-vault` TLS leaf certificate,
installs `tls.key`, `tls.crt`, and `operator-ca-bundle.pem` under
`OPENBAO_TLS_DIR`, and restarts only `openbao-global-0`.

The OpenBao CA bundle projection phase (`--operator-secret-sync-ca-bundle`) projects
the public Operator CA bundle from `OPERATOR_PKI_PUBLIC_DIR/operator-ca-bundle.pem`
into the `operator-secret-sync` namespace as a ConfigMap (`openbao-ca-bundle`). This
ConfigMap is public trust material that operator-secret-sync pods will mount to verify
OpenBao TLS during secret sync operations. The CA bundle projection is separate from
operator-vault leaf certificate rotation: operator-vault runtime TLS rotation replaces
the leaf certificate only, while CA bundle projection is needed whenever the Operator
CA changes (not on every leaf rotation). The projection phase is idempotent, non-destructive,
and included in `--all` because it is a required foundation for operator-secret-sync
without introducing secrets or exposing operator-vault.

Important: the Operator CA bundle is public trust material and must be readable by
unprivileged verification processes. The bootstrap scripts ensure the published
public bundle path is traversable and the bundle/checksum files are world-readable
while keeping private OpenBao runtime material protected.

The leaf private key is generated by the OpenBao issue endpoint. The issuance
JSON is not saved, and the CA private key remains inside OpenBao. This does not
expose `operator-vault` publicly. Traefik TCP passthrough and Tenant OpenBao
remain later phases. The `--operator-vault-tls` phase is intentionally explicit
and is not included in `--all` yet because it rotates OpenBao runtime TLS and
restarts only `openbao-global-0`.

Before runtime TLS rotation, bootstrap TLS may use `/openbao/tls/tls.crt` as
the in-pod OpenBao client trust anchor. After rotation, `tls.crt` is the leaf
certificate and `/openbao/tls/operator-ca-bundle.pem` is the correct trust
anchor. Scripts that run OpenBao clients inside the pod must prefer the
Operator CA bundle when it is present and fall back to `tls.crt` only for the
bootstrap self-signed phase. This trust-path fix is required before running
`--operator-vault-tls`.

The operator-secret-sync namespace also receives the Operator CA bundle as a
mounted ConfigMap (`openbao-ca-bundle`). The sync Job can verify OpenBao TLS
using either the in-pod path (`/openbao/tls/operator-ca-bundle.pem`) or the
mounted ConfigMap path. The ConfigMap ensures the CA bundle is available for
verification even if the sync Job runs on a different node and cannot access
the host TLS directory. The CA bundle projection phase makes this ConfigMap
available without requiring runtime TLS rotation to have completed first.

The `--operator-secret-sync-foundation` phase is target operator-plane state.
It ensures the public CA bundle projection, ServiceAccount, least-privilege
RBAC, script ConfigMap, and Global OpenBao Kubernetes auth role/policy for
`operator-secret-sync/operator-plane-secret-sync`. It does not create or run
the `operator-secret-sync/operator-plane-secret-sync` Job, does not select a
runner image, and does not mutate target runtime Secrets with synced values.

The `--operator-secret-sync-runner-image` phase reads
`operator-secret-sync-runner-candidate` from `dependencies.lock.json` and
validates the candidate with a temporary Kubernetes Job in the
`operator-secret-sync` namespace. The validation uses k3s/Kubernetes/containerd
execution, not Docker. It does not use the real
`operator-plane-secret-sync` ServiceAccount, does not mount Kubernetes Secrets,
does not call OpenBao, does not run the real sync Job, and deletes the
temporary validation workload on success or failure.

The validation workload is unprivileged, disables ServiceAccount token
automount, drops Linux capabilities, and uses a read-only root filesystem. It
does not force `runAsNonRoot` for v1 because the standard candidate image may
not declare a non-root user.

The validation-only phase can run before the candidate digest is known. The
selected runner image is digest-pinned in `dependencies.lock.json`. The real
sync Job is enabled only by the explicit `--operator-secret-sync-job` phase,
and execution uses the validated tag plus digest in the Job image reference.

The real Job preflight checks the digest-pinned runner image, foundation
resources, RBAC for target Secrets, OpenBao Kubernetes auth metadata, and the
required OpenBao KV paths and keys. It prints only safe metadata and never
prints Secret data, OpenBao tokens, PEM contents, htpasswd contents, generated
hashes, plaintext, ciphertext, or issuance JSON.

## Current TODO Phases

Future work:

- `operator-vault` TCP passthrough through Traefik
- final destructive reinstall test

Do not run destructive wipe behavior or destructive reinstall tests until Operator PKI, operator-vault TLS, artifact publication, and final debug points are complete.

## Safe Examples

Preview the Traefik phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --traefik --dry-run
```

Preview the `operator-artifacts` phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-artifacts --dry-run
```

Run the `operator-artifacts` reconcile phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-artifacts
```

Then run the environment verifier:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh
```

Preview the operator-secret-sync phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-foundation --dry-run
```

Preview the operator KV mount phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --openbao-operator-kv --dry-run
```

Run the operator KV mount phase before importing bootstrap secrets:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --openbao-operator-kv
```

Preview the runner image validation phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image --dry-run
```

Run the validation phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image
```

Resolve the candidate digest through k3s/containerd tooling:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/resolve-image-digest.sh --image 'docker.io/alpine/k8s:1.35.4'
```

After review, manually copy the selected `sha256` digest into
`dependencies.lock.json`. The helper does not edit repository files.

Preview the explicit real sync Job phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-job --dry-run
```

Run the explicit real sync Job phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-job
```

Preview the Operator PKI phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-pki --dry-run
```

Preview the explicit `operator-vault` TLS rotation phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-vault-tls --dry-run
```

Run read-only verification:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh
```

## Safety Rules

- Do not paste secrets.
- Do not commit real domains, emails, public IPs, tokens, certificates, keys, htpasswd contents, OpenBao init material, or audit log contents.
- Do not print Kubernetes Secret `.data` or `stringData`.
- Do not run destructive wipe behavior until the final phase.
- Do not touch `trading`.
- Do not introduce component-specific real env files.
- Do not store static OpenBao tokens in Kubernetes Secrets.

## Executable Scripts in Git

- Operational scripts included in this repository must be executable via Git mode,
  not manually `chmod`'d on the VPS. Set executable mode in the repository so
  the permissions are preserved when cloning or pulling to the target host:

```bash
git update-index --chmod=+x k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-openbao-ca-bundle-configmap.sh
git update-index --chmod=+x k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/verify-openbao-ca-bundle-configmap.sh
git update-index --chmod=+x k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync-foundation.sh
git update-index --chmod=+x k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/verify-operator-secret-sync-foundation.sh
```

This ensures the bootstrap and verify orchestrators can run target-ready
phases without false WARN statuses due to missing executable bits.

## Secret Authority

Global OpenBao KV is the operator-plane source of truth for secrets and sensitive runtime configuration.

The bootstrap sequence for operator-plane secret projection is:

1. Install and initialize Global OpenBao.
2. Configure Operator PKI and install the Operator CA bundle in the OpenBao pod.
3. Enable the Global OpenBao `operator-kv/` KV v2 mount with `--openbao-operator-kv`.
4. Import bootstrap secrets into `operator-kv/`.
5. Run operator-secret-sync preflight.
6. Run the explicit operator-secret-sync Job phase.

Global OpenBao also hosts the Operator PKI/CA as OpenBao-managed PKI state, not
KV data. The CA private key remains inside OpenBao. The first Operator PKI
foundation exports only the public CA bundle and checksum for future trust
distribution.

Kubernetes Secrets are runtime projections or bootstrap imports. Local env files
are bootstrap, import, recovery, or central non-secret/sensitive operational
configuration only. `operator-plane.env` is the single normal operational env
file.

operator-artifacts operational configuration is centralized in
`operator-plane.env`. `OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES` lives there,
the public hostname is derived as `operator-artifacts.${OPERATOR_DOMAIN}`, and
the BasicAuth username is derived from `OPERATOR_ARTIFACTS_TENANT_NAME`.

The in-cluster sync Job authenticates to OpenBao with Kubernetes auth through the `operator-plane-secret-sync` ServiceAccount and role. It does not use a static OpenBao token.

The foundation phase configures that Kubernetes auth binding in Global OpenBao
without creating static tokens and binds only the
`operator-secret-sync/operator-plane-secret-sync` ServiceAccount.

The sync script remains a normal versioned repository file. The install script generates and applies the runtime ConfigMap from that script, so changing sync logic does not require rebuilding an image.

No custom sync image is created at this stage and no registry is introduced at
this stage. The Job uses the pinned standard runner image from
`dependencies.lock.json` in tag plus digest form.

The foundation phase does not choose, validate, pull, or run the runner image.
The real Job phase runs the one-shot Job only as an explicit step.

The candidate `docker.io/alpine/k8s:1.35.4` is tracked in
`dependencies.lock.json` with digest
`sha256:d9aeef2665287b9918bc57c539ba95382ba4c8d52c8b1310df5666a89d9a3d04`.
The installer resolves this lock entry and renders the real Job image as tag
plus digest.

Validate a candidate runner image with:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/validate-runner-image-contract.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image
```

The runner image must provide `bash`, `curl`, `jq`, `kubectl`, and CA
certificates. It does not require the `openssl` CLI. BasicAuth hash generation
is not performed in the sync Job. The bootstrap import env may contain
operator-artifacts username/token as local import inputs only; the import
script may use host `openssl passwd -apr1 -stdin` to derive the final
htpasswd-compatible `users` line. OpenBao KV stores only the final
operator-artifacts BasicAuth `users` value for the runtime projection, and the
sync Job copies that value verbatim into Kubernetes Secret key `users`.
Username/token are not written to the operator-artifacts runtime KV path. No
generated hashes, `users` contents, or real secret values are stored in Git or
printed. No custom image is created for v1, and the
pod must not install packages at runtime. Future vulnerability management means
updating the pinned image reference and rerunning the Kubernetes contract
check; changing sync logic updates the script and generated ConfigMap, not the
image.

The same no-runtime-package-install rule applies to operator-artifacts nginx:
update the pinned image reference in Git instead of installing packages in the
running container.

Verify the dependency lock without touching live state:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/verify-dependencies-lock.sh
```

The bootstrap env parser is strict and does not execute shell from `operator-plane.bootstrap-secrets.env`.

Operator PKI is the future source for OpenBao CA bundle trust for in-cluster clients. Until that public CA bundle is safely projected into the sync namespace, the OpenBao CA bundle projection is required and fail-closed: install and verify check only ConfigMap metadata and key presence, and the sync script exits before OpenBao login if the mounted CA bundle is missing, empty, or unreadable.

The public Operator CA bundle is also published as an operator artifact for
tenant `family-infra-01`. The CA bundle is public trust material; the private
Operator CA key remains inside OpenBao, and the `operator-vault` leaf private
key remains only in the OpenBao runtime TLS directory.

Artifact paths:

```text
/tenants/family-infra-01/trust/operator-ca-bundle.pem
/tenants/family-infra-01/trust/operator-ca-bundle.pem.sha256
```

Do not paste BasicAuth tokens in logs or docs. Publishing this artifact does
not expose `operator-vault`.
