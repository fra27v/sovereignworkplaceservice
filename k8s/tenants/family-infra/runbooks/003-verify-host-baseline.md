# Verify the family-infra host baseline

This runbook verifies the Ubuntu host baseline for `family-infra-01`.

The verification script is read-only and safe to run after every reboot.

## Supported Operating System

The expected operating system is Ubuntu Server 26.04 LTS on x86_64/amd64.
Another Ubuntu release produces a `WARN`, not a `FAIL`. A non-Ubuntu
distribution produces a `FAIL` because the baseline relies on Ubuntu-specific
APT, unattended-upgrades, AppArmor, and OpenSSH integration.

## Run

```bash
cd ~/src/sovereignworkplaceservice
git pull --ff-only
sudo ./k8s/common/host/scripts/verify-host-baseline.sh \
  --hostname family-infra-01 \
  --ssh-port 50022 \
  --update-policy automatic
```

## Expected Output

The script prints sections:

```text
== Host identity ==
== Operating system ==
== SSH ==
== Fail2ban ==
== Packages ==
== Automatic updates ==
== Network ==
== Firewall ==
== Time synchronization ==
== Security ==
== k3s host prerequisites ==
== Summary ==
```

Exit code behavior:

```text
0 = no FAIL
non-zero = at least one FAIL
```

`WARN` does not cause a non-zero exit code. A reboot-required marker is a
`WARN`, not a `FAIL`.

## Gate for k3s

Proceed only when there are no `FAIL` entries:

```text
host baseline verify
  -> k3s prepare
  -> k3s install
  -> k3s verify
```

If only `OK` and `WARN` entries are present, the gate is passed unless a warning
requires an explicit operational decision.
