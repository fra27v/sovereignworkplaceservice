# OpenBao vps-family-control Environment

Environment-specific OpenBao material for `vps-family-control` belongs here.

Commit sanitized examples, values files, and scripts only. Do not commit real tokens, unseal keys, root tokens, recovery keys, or tenant secrets.

The `.env.example` files in this directory are examples for the Global OpenBao operator-plane. Copy them to local, ignored files before use and keep real values outside Git.

Global OpenBao chart and application versions for this environment are pinned in `openbao-global.versions.env`. Render and install scripts should read that file instead of relying on caller-exported version variables.

Operators should prepare, render, and install Global OpenBao in this order:

1. `scripts/prepare-local-openbao-files.sh`
2. `scripts/render-openbao-global.sh`
3. `scripts/install-openbao-global.sh`

Do not initialize OpenBao from the install script.

After Global OpenBao is initialized and Operator PKI has installed the Operator
CA bundle in the OpenBao pod, enable the operator-plane source-of-truth KV v2
mount with:

```bash
scripts/configure-openbao-global-operator-kv.sh --env-file ../operator-plane.env
```

The script is idempotent. It creates `operator-kv/` only when missing, verifies
an existing mount is KV v2, uses the in-pod `bao` CLI, and does not require
host-side `bao`.

Expose the public operator-vault endpoint only through:

```bash
scripts/install-operator-vault-public-endpoint.sh --env-file ../operator-plane.env --dry-run
scripts/install-operator-vault-public-endpoint.sh --env-file ../operator-plane.env
scripts/verify-operator-vault-public-endpoint.sh --env-file ../operator-plane.env
```

The endpoint uses Traefik `IngressRouteTCP` with TLS passthrough to
`openbao-global:8200`. OpenBao terminates TLS with the Operator CA-issued
runtime certificate. Clients must verify the server with
`OPERATOR_PKI_PUBLIC_DIR/operator-ca-bundle.pem`. The CA bundle is trust
material, not an access restriction; Traefik MiddlewareTCP `ipAllowList` is the
network restriction, and OpenBao auth remains required.
