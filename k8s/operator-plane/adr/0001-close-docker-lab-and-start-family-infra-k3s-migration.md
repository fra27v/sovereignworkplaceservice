# ADR-0001: Close Docker Lab and Start Family Infrastructure k3s Migration

## Status

Accepted

## Date

2026-06-18

## Context

The Docker lab is complete and tagged `DockerLabEnd`.

The next phase is the migration to k3s. This migration starts now and will be
incremental, one service at a time.

The k3s platform must start from a production-grade baseline for the family
infrastructure instead of growing from a temporary development cluster. That
means `--secrets-encryption`, TLS from the start, certificate rotation, and
service-to-service TLS where applicable.

## Decision

Do not use the embedded k3s Traefik. Traefik is repository-managed.

Introduce OpenBao directly in k3s.

Run Global OpenBao in `operator-plane` on the VPS.

Run Tenant OpenBao in `family-infra`.

Tenant OpenBao uses transit autounseal against Global OpenBao.

Applications use Tenant OpenBao, not Global OpenBao.

## Consequences

The Kubernetes migration has a stronger operational baseline from the first
service.

The operator plane becomes a required platform layer because it hosts Global
OpenBao and shared platform controls.

Tenant environments remain separated from operator-plane secrets. Applications
consume tenant-level OpenBao services and do not depend directly on Global
OpenBao.

## Family infra compromises

`family-infra` may use a static seal key on the protected VPS filesystem,
mounted read-only.

The static seal key must not be committed to Git. It also should not be stored
in a Kubernetes Secret if this can be avoided.

This compromise is accepted only for `family-infra`. It is operational
production for the family infrastructure, but it is not commercial production.

If VPS root is compromised, Global OpenBao unseal is compromised. This risk is
accepted only for `family-infra`.

## Commercial production target

Commercial production should use KMS, KMIP, HSM, PKCS#11, TPM, vTPM, or an
equivalent managed or hardware-backed mechanism for seal key protection.

The `family-infra` static-key compromise must not be treated as the commercial
production pattern.

## Follow-up ADRs

Follow-up ADRs should define:

- Global OpenBao bootstrap and recovery model.
- Tenant OpenBao bootstrap and transit autounseal flow.
- Traefik deployment and certificate management.
- k3s hardening baseline and certificate rotation policy.
- Service migration order and acceptance criteria.
