# VPS Family Control Operator Environment

This environment is the family infrastructure control plane on a VPS target.

The files in this directory are examples and placeholders. They do not install
k3s or deploy platform services.

Host baseline tooling is documented in `runbooks/001-host-baseline-tools.md`.
Use `scripts/check-host-baseline-tools.sh` to verify required commands and
`scripts/install-host-baseline-apt-tools.sh` to install only apt-managed
baseline tools.

## Operator Plane Bootstrap

The environment-level operator entrypoints are:

- `scripts/bootstrap-operator-plane.sh`
- `scripts/verify-operator-plane.sh`

On Linux and on the VPS target, use normal `bash -n` syntax checks before
running shell scripts. On Windows hosts without WSL, `bash` may resolve to the
WSL stub and fail because no WSL distribution is installed. Do not interpret
that WSL-stub failure as a script syntax failure. Use Git Bash explicitly for
local syntax checks instead:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -n <script>
```

Prefer validating deployment scripts on the Linux VPS before
execution-sensitive phases.

`operator-plane.env` is the single normal operational env file for this
environment. Copy `operator-plane.env.example` to `operator-plane.env`, keep it
out of Git, and set permissions to `0600`. Component-specific `.env.example`
files are reference-only and must not become separate operational env files.

Some operator scripts may run with `sudo` when they need host filesystem
writes. On Linux, `sudo` changes `$HOME` to `/root`, but Global OpenBao init
material remains under the operator user's bootstrap directory unless
explicitly configured otherwise. Set `OPENBAO_BOOTSTRAP_INIT_FILE` in
`operator-plane.env` to the existing local bootstrap init JSON path. This value
is only a path; the file it points to contains sensitive OpenBao init material.
Do not copy init material to `/root`, and do not paste or commit the init JSON
contents.

Do not duplicate the same real-world value under multiple variable names.
Public service names such as `operator-vault.<domain>` and internal OpenBao
service DNS names are derived from the central base domain, service name,
namespace, and cluster DNS suffix where possible.

Manual component scripts remain available under `traefik/scripts`,
`openbao/scripts`, and `operator-artifacts/scripts` for debugging. The target
operator interface is the environment bootstrap script plus the environment
verification script.

Global OpenBao KV is the operator-plane source of truth for secrets and
sensitive runtime configuration. Kubernetes Secrets are runtime projections or
bootstrap imports, not the long-term source of truth. Local `.env` files are
bootstrap, import, recovery, or central non-secret/sensitive operational
configuration only.

In-cluster operator-plane sync uses OpenBao Kubernetes auth. Do not store static
OpenBao tokens in Kubernetes Secrets.

Operator PKI foundation files are present under `operator-pki/` and are wired
into the bootstrap and verify entrypoints. They configure an OpenBao-managed
Operator CA, configure the `operator-vault` issuance role, and export only the
public CA bundle. They do not yet issue or install the final `operator-vault`
runtime TLS certificate, do not rotate existing OpenBao TLS, and do not expose
`operator-vault`.

The exported Operator CA bundle is the future trust source for in-cluster
clients such as `operator-secret-sync`. The sync runner image is still not
selected, and the sync Job remains blocked by install preflight until a pinned
standard runner image is validated.

Do not run a destructive reinstall test until Operator PKI, operator-vault TLS,
artifact publication, and final debug points are complete.
