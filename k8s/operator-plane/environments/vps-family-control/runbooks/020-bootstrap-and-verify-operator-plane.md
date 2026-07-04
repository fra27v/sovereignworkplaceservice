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

Do not create component-specific real env files for Operator PKI.
Component-specific `.env.example` files are reference-only. Avoid duplicated
values across variables: derive public service hostnames from the central base
domain and derive internal DNS names from service, namespace, and cluster DNS
suffix values.

## Current Supported Phases

The bootstrap entrypoint currently supports:

- Traefik ACME DNS-01 OVH setup
- Global OpenBao baseline verification
- operator-plane secret import, Kubernetes auth configuration, and one-shot sync Job apply
- `operator-artifacts`
- Operator PKI configure and verify

Global OpenBao install, initialization, transit setup, and audit setup remain delegated to their explicit component runbooks until stable environment-level entrypoints are validated.

Operator PKI bootstrap configures only the OpenBao PKI mount, Operator CA,
`operator-vault` issuance role, and public CA bundle export. It does not issue
leaf certificates, rotate existing OpenBao TLS, or expose `operator-vault`.

## Current TODO Phases

Future work:

- Issue and install `operator-vault` runtime TLS from Operator PKI
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

Preview the operator-secret-sync phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync --dry-run
```

Preview the Operator PKI phase:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-pki --dry-run
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

## Secret Authority

Global OpenBao KV is the operator-plane source of truth for secrets and sensitive runtime configuration.

Global OpenBao also hosts the Operator PKI/CA as OpenBao-managed PKI state, not
KV data. The CA private key remains inside OpenBao. The first Operator PKI
foundation exports only the public CA bundle and checksum for future trust
distribution.

Kubernetes Secrets are runtime projections or bootstrap imports. Local env files
are bootstrap, import, recovery, or central non-secret/sensitive operational
configuration only. `operator-plane.env` is the single normal operational env
file.

The in-cluster sync Job authenticates to OpenBao with Kubernetes auth through the `operator-plane-secret-sync` ServiceAccount and role. It does not use a static OpenBao token.

The sync script remains a normal versioned repository file. The install script generates and applies the runtime ConfigMap from that script, so changing sync logic does not require rebuilding an image.

No custom sync image is created at this stage and no registry is introduced at this stage. The Job must use a pinned standard runner image satisfying `operator-secret-sync/image-contract.md`. The runner image is not selected yet, and real install fails before applying the Job until one is selected.

Validate a candidate runner image with:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/check-runner-image-contract.sh --image '<pinned-image-ref>' --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/check-runner-image-contract.sh --image '<pinned-image-ref>'
```

The runner image must provide `bash`, `curl`, `jq`, `kubectl`, `openssl`, `openssl passwd -apr1` support, and CA certificates. Future vulnerability management means updating the pinned image reference and rerunning the contract check; changing sync logic updates the script and generated ConfigMap, not the image.

The bootstrap env parser is strict and does not execute shell from `operator-plane.bootstrap-secrets.env`.

Operator PKI is the future source for OpenBao CA bundle trust for in-cluster clients. Until that public CA bundle is safely projected into the sync namespace, the OpenBao CA bundle projection is required and fail-closed: install and verify check only ConfigMap metadata and key presence, and the sync script exits before OpenBao login if the mounted CA bundle is missing, empty, or unreadable.
