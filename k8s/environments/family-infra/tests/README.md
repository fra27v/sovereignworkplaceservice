# family-infra tests

This directory contains operational tests for the `family-infra` environment.

## Categories

- `smoke`: small tests that prove a core runtime path works.
- `regression`: ordered suites that combine baseline and smoke checks before
  or after infrastructure changes.
- `e2e`: future end-to-end tests across multiple platform services.
- `security`: future security validation for runtime posture and policy.
- `backup-restore`: future backup, restore, and recovery validation.

Tests must not commit secrets, certificates, tokens, credentials, kubeconfig
files, or generated local cluster state.
