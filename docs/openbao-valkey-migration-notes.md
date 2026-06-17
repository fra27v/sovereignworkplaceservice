# OpenBao and Valkey Migration Notes

## OpenBao

State: future target.

The repository currently uses `hashicorp/vault:1.19` for:

- core Vault server.
- Vault Agent in services.
- AppRole.
- Vault Agent template rendering.
- KV v2 is described in the Vault README as a manual setup step.
- PKI certificate issuance is assumed by the certificate scripts, but complete PKI bootstrap is not codified in the repository.

Before migrating to OpenBao, verify:

- HCL compatibility of `core/vault/config/vault.hcl`.
- Vault Agent compatibility or OpenBao replacement for templates and auto-auth.
- AppRole support.
- KV v2 compatibility.
- PKI issue endpoint compatibility used by scripts.
- impact on Docker images in all Compose files.

TODO: create a parallel OpenBao environment and test certificate issuance and service templates.

## Valkey

State: future target.

The repository currently uses `redis:7-alpine` only in `services/nextcloud/docker-compose.yml` as the cache and locking backend for Nextcloud.

Before migrating to Valkey, verify:

- protocol compatibility with the existing Nextcloud configuration.
- compatibility with the current password file.
- data paths and append-only persistence.
- target Valkey image and tag.
- any official Nextcloud notes on Valkey support.

TODO: test replacing `redis:7-alpine` with a Valkey image in a non-production environment.
