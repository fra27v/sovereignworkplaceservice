# ADR 0004 - Redis to Valkey Target

## Status

Proposed as a future target.

## Context

The repository uses Redis 7 Alpine for Nextcloud cache and file locking. Valkey is the desired target, but it is not implemented.

## Decision

Valkey is documented as a future target. Redis remains the current runtime component until the replacement is tested.

## Consequences

- No runtime change in this phase.
- The migration must validate Nextcloud compatibility, password handling, persistence, and startup parameters.
- Documentation must clearly distinguish current Redis from target Valkey.
