# Operator Artifacts

Operator-plane artifact repository configuration and runbooks belong here.

The logical service endpoint is `operator-artifacts.<domain>`. It is separate from `operator-vault.<domain>` and is used for tenant outbound HTTPS artifact pulls.

Real artifacts, tenant tokens, certificates, signatures, and private keys must stay outside Git unless they are explicitly sanitized placeholders.

Runbooks:

- `runbooks/001-operator-artifacts-architecture.md`
- `runbooks/002-prepare-local-artifact-storage-and-token.md`
- `runbooks/003-deploy-operator-artifacts.md`
