# family-infra Host Baseline

This directory contains the Ubuntu host baseline for the local VM
`family-infra-01`.

The baseline is intentionally separate from k3s installation. It prepares the
host OS with required packages, SSH key-only access, fail2ban, unattended Ubuntu
updates, time synchronization checks, and read-only verification checks. It does
not configure static networking, Synology VMM networking, Kubernetes
networking, firewall rules, k3s, Traefik, OpenBao, IAM services, Nextcloud, or
secrets.

## Supported Operating System

This host baseline is designed and optimized for Ubuntu Server 26.04 LTS on
x86_64/amd64.

Other Ubuntu releases may work on a best-effort basis, but they are not the
primary validated target and may differ in package versions, service behavior,
time synchronization, OpenSSH integration, or other operating-system details.
`verify-host-baseline.sh` emits a `WARN` when the detected Ubuntu version does
not match 26.04.

Non-Ubuntu distributions are unsupported because the baseline relies on APT,
unattended-upgrades, Ubuntu package and service conventions, AppArmor, and
Ubuntu OpenSSH integration.

## Defaults

- hostname: `family-infra-01`
- SSH port: `50022`
- fail2ban: enabled for the configured SSH port
- Ubuntu update policy: `automatic`
- automatic reboot: disabled
- UFW: disabled when installed and active

## Scripts

- `scripts/apply-host-baseline.sh` applies the idempotent host baseline.
- `scripts/verify-host-baseline.sh` performs read-only verification after apply
  and after reboot.

## Normal Flow

Run the host baseline before k3s:

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

Use the runbooks in `../runbooks/`:

- `001-bootstrap-host.md`
- `002-apply-host-baseline.md`
- `003-verify-host-baseline.md`
- `004-install-k3s.md`
