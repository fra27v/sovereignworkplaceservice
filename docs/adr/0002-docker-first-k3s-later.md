# ADR 0002 - Docker First, k3s Later

## Status

Accepted.

## Context

The current repository uses Docker Compose for Traefik, Vault, and application services. Migration to k3s is indicated as the target direction, but Kubernetes manifests are not present.

## Decision

The lab remains Docker-first. k3s is treated as a documented future migration, not as the current runtime.

## Consequences

- Operational work must continue to use Compose and the existing scripts.
- k3s documentation must be marked as target/future.
- The migration must preserve already validated patterns: reverse proxy, secrets, internal TLS, and identity governance.
