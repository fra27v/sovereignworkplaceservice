# Repository Governance

This document defines general repository governance for folder usage, versioning rules, naming conventions, and script conventions.

Treat this repository as public or potentially public. Avoid exposing unnecessary operational metadata.

## Language

Repository files, directory names, scripts, comments, runbooks, ADRs, manifests, and configuration templates must be in English.

## Naming

DNS names and logical service names use service names.

Examples:

- `operator-vault.<domain>`
- `operator-artifacts.<domain>`

Repository folders use implementation or component names when files are technology-specific.

Example:

- `operator-vault` is the logical service.
- `openbao/` is the implementation folder because the files are OpenBao-specific.

## Folder Model

Use these folder responsibilities:

- `k8s/operator-plane/`: global and operator services.
- `k8s/operator-plane/environments/<environment>/`: environment-specific operator-plane configuration.
- `k8s/components/`: reusable components without real environment values; no placeholder component directories are maintained.
- `k8s/common/`: reusable host and Kubernetes operational baselines.
- `k8s/tenants/`: tenant-specific configuration, values, runbooks, and deployment composition; no placeholder tenant directories are maintained.
- `legacy/`: historical or deprecated material only.

Do not mix global/operator service configuration with tenant runtime configuration unless the file explicitly documents the boundary.

## What Belongs In Git

Commit versioned, non-secret operating intent:

- Scripts.
- Runbooks.
- ADRs.
- Policy files.
- Helm values without secrets.
- Manifest templates.
- `.env.example` files.
- Expected directory layouts.
- Verification logic.
- Non-secret examples and placeholders.

Use placeholders for domains, IP addresses, certificates, tenant-specific values, and generated access material.

## What Must Not Be Committed

Never commit:

- Real tokens.
- Root tokens.
- Init JSON files.
- Recovery material.
- Private keys.
- Static seal keys.
- Real `.env` files.
- Real certificates or CA bundles if they expose sensitive operational metadata.
- Generated artifacts containing real domains, owner names, serials, or operational metadata.
- Audit logs.

Do not commit checksums of real secrets if the checksum would become an identifier for sensitive material.

## Environment Files

Commit `.env.example` files.

Do not commit real `.env` files.

Each environment folder must have a `.gitignore` excluding real environment files and generated sensitive artifacts.

Environment examples must use placeholders, not real domains, tokens, certificates, keys, or IP addresses.

## Policies And Desired State

Security policies must be versioned as files where possible.

Runtime scripts should apply versioned policy files.

Avoid inline production policy definitions inside scripts.

Inline policy heredocs are allowed only for explicitly documented temporary diagnostics.

Runtime state should be verifiable against versioned desired state.

## Script Conventions

Shell scripts should use:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Scripts must:

- Fail fast when required files or environment variables are missing.
- Never print secrets.
- Never print token values.
- Never print private key contents.
- Never print audit logs.
- Print safe metadata and follow-up commands only.
- Refuse to overwrite critical material unless a documented explicit force flag is used.
- Prefer idempotent behavior where safe.
- Require explicit manual confirmation for destructive actions.

Sensitive values should be passed through stdin or protected files where practical, not visible command arguments.

## Operational Model

Manual commands are acceptable for diagnostics.

Repeatable or non-trivial operations should become versioned scripts plus runbooks.

Runbooks should explain:

- Prerequisites.
- Execution steps.
- Verification.
- Rollback notes where applicable.
- What not to paste into chat, tickets, logs, or Git.

Documentation should separate implemented behavior from target or future behavior.

## Public Git Posture

Treat the repository as public or potentially public.

Avoid exposing unnecessary operational metadata.

Use placeholders for domains, IP addresses, certificates, and tenant-specific material.

Generated files with real operational metadata belong outside Git unless they are explicitly sanitized.
