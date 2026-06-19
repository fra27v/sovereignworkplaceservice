# Run family-infra regression tests

This runbook executes the regression test suite for the `family-infra`
environment.

## Scope

The regression suite verifies the installed k3s baseline, the installed runtime
Traefik instance, and the versioned whoami routing smoke test.

Out of scope:

- Application service tests.
- Secrets, certificates, tokens, or credentials.
- Backup and restore validation.
- Security posture validation.

## Preconditions

- The k3s baseline is installed and verified.
- Runtime Traefik is installed and verified.
- The repository is cloned on the target node.

## Run

Run the suite:

```bash
sudo ./k8s/environments/family-infra/tests/regression/run.sh
```

Run the suite and remove the whoami routing smoke test afterward:

```bash
sudo ./k8s/environments/family-infra/tests/regression/run.sh --cleanup
```

## Expected Result

Successful output ends with:

```text
family-infra regression test suite passed
```

On failure, the runner prints the failed step and, when the whoami smoke test
was already applied, a cleanup command.

Do not commit generated local files, kubeconfig files, certificates, tokens,
credentials, or secrets.
