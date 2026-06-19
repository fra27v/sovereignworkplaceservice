# OpenBao vps-family-control Environment

Environment-specific OpenBao material for `vps-family-control` belongs here.

Commit sanitized examples, values files, and scripts only. Do not commit real tokens, unseal keys, root tokens, recovery keys, or tenant secrets.

The `.env.example` files in this directory are examples for the Global OpenBao operator-plane. Copy them to local, ignored files before use and keep real values outside Git.

Global OpenBao chart and application versions for this environment are pinned in `openbao-global.versions.env`. Render and install scripts should read that file instead of relying on caller-exported version variables.
