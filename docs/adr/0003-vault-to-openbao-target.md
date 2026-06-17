# ADR 0003 - Vault to OpenBao Target

## Status

Proposed as a future target.

## Context

The repository uses HashiCorp Vault 1.19 as the secret manager and Vault Agent runtime. The certificate scripts assume Vault PKI is available, but the complete PKI bootstrap is not codified in the repository. OpenBao is the desired target, but it is not implemented in the repository.

## Decision

OpenBao is documented as a future target. The current runtime remains Vault until a tested migration exists in the repository.

## Consequences

- Docker images or runtime configuration are not changed in this phase.
- Every new use of Vault should avoid dependencies that cannot be verified in OpenBao, where possible.
- The migration must test AppRole, agent templates, KV v2, and the PKI issue endpoint.

TODO: create a follow-up ADR when the migration is implemented or rejected after testing.
