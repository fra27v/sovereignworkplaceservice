# Family Infrastructure Environment

`family-infra` is the active k3s operational environment for the family
infrastructure.

## Current Scope

The current scope includes the Ubuntu host baseline for `family-infra-01`, the
verified k3s baseline, the runtime Traefik instance, and environment tests:

- host OS bootstrap documentation
- idempotent host baseline apply and verify scripts
- common k3s server configuration
- common config preparation script
- common k3s installation wrapper
- common baseline verification script
- reusable runtime Traefik installation and verification
- versioned whoami routing smoke test
- regression test entrypoint

Application migration remains out of scope for now.

## Host Baseline

The reusable host baseline lives in `../../common/host/`.

The expected operating system for `family-infra-01` is Ubuntu Server 26.04 LTS
on x86_64/amd64. The host baseline scripts are optimized for Ubuntu Server
26.04 LTS. Other Ubuntu releases are best-effort and
`verify-host-baseline.sh` emits a `WARN` when the detected Ubuntu version does
not match the expected target. Non-Ubuntu distributions are unsupported because
the baseline relies on APT, unattended-upgrades, Ubuntu package and service
conventions, AppArmor, and Ubuntu OpenSSH integration.

It intentionally does not configure static IP addresses, Netplan, VLANs,
Synology VMM networking, k3s, Traefik, OpenBao, IAM services, Nextcloud, or
secrets.

The required order is:

```text
Synology VMM
  -> Ubuntu Server 26.04 LTS
  -> manual bootstrap
  -> host baseline apply
  -> host baseline verify
  -> k3s prepare
  -> k3s install
  -> k3s verify
```

## Scripts

The reusable operational scripts are in `../../common/`:

- `k3s/scripts/prepare-k3s-config.sh` copies the common k3s config to
  `/etc/rancher/k3s/config.yaml`.
- `k3s/scripts/install-k3s.sh` installs the pinned k3s version.
- `k3s/scripts/verify-k3s.sh` checks the baseline node state, secrets encryption,
  kubeconfig permissions, disabled embedded Traefik, and key ports.
- `k3s/scripts/setup-k3s.sh` is the command wrapper for `prepare`, `install`,
  `verify`, and `all`.

Traefik runtime scripts live under
`k8s/components/traefik/scripts/`.

## Tests

Environment tests are in `tests/`:

- `tests/smoke/whoami-routing/` verifies HTTP routing through the runtime
  Traefik instance.
- `tests/regression/run.sh` runs the k3s baseline verification, Traefik
  verification, and whoami routing smoke test in order.
- `tests/e2e/`, `tests/security/`, and `tests/backup-restore/` are placeholders
  for future test categories.

## Runbooks

- `runbooks/001-bootstrap-host.md`
- `runbooks/002-apply-host-baseline.md`
- `runbooks/003-verify-host-baseline.md`
- `runbooks/004-install-k3s.md`
- `runbooks/005-install-traefik.md`
- `runbooks/006-run-regression-tests.md`

## Current Status

- k3s baseline OK
- Traefik runtime OK
- whoami routing OK
- regression suite OK

Do not commit generated local files such as `/etc/rancher/k3s/config.yaml` or
`/etc/rancher/k3s/k3s.yaml`. Do not commit SSH keys, deploy keys, tokens,
passwords, certificates, kubeconfig files, or other secret material.
