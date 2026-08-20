# Apply the family-infra host baseline

This runbook applies the idempotent Ubuntu host baseline after the repository
has been cloned on `family-infra-01`.

It does not install k3s, Traefik, OpenBao, IAM components, Nextcloud, or
application workloads.

## Supported Operating System

The host baseline scripts are optimized for Ubuntu Server 26.04 LTS on
x86_64/amd64. Running them on another Ubuntu release is supported on a
best-effort basis and emits a visible warning. Non-Ubuntu distributions fail
before significant changes because this baseline depends on Ubuntu APT,
unattended-upgrades, AppArmor, and OpenSSH conventions.

## Preconditions

- The host is expected to run Ubuntu Server 26.04 LTS.
- The repository is cloned at `~/src/sovereignworkplaceservice`.
- The admin user exists and has a working SSH public key in
  `~/.ssh/authorized_keys`.
- A second SSH session can be opened with the current SSH settings.
- The server is not expected to keep UFW active for this k3s host profile.

## Refresh the Repository

```bash
cd ~/src/sovereignworkplaceservice
git pull --ff-only
```

## Dry Run

Replace `<admin-user>` and `<server-address>` with the real values.

```bash
sudo ./k8s/environments/family-infra/host/scripts/apply-host-baseline.sh \
  --hostname family-infra-01 \
  --admin-user <admin-user> \
  --ssh-port 50022 \
  --update-policy automatic \
  --dry-run
```

Review the planned changes. The dry run must not install packages, modify SSH,
change the hostname, restart services, or disable UFW.

## Apply

```bash
sudo ./k8s/environments/family-infra/host/scripts/apply-host-baseline.sh \
  --hostname family-infra-01 \
  --admin-user <admin-user> \
  --ssh-port 50022 \
  --update-policy automatic
```

The script performs a normal package upgrade but does not reboot the host and
does not enable automatic reboots.

## SSH Lockout Check

After the script changes SSH settings, keep the existing session open. Open a
second terminal and verify the new SSH port:

```bash
ssh -p 50022 <admin-user>@<server-address>
```

Only close the original session after the second session works.

## Next Step

Run the read-only verification:

```bash
sudo ./k8s/environments/family-infra/host/scripts/verify-host-baseline.sh \
  --hostname family-infra-01 \
  --ssh-port 50022 \
  --update-policy automatic
```

Do not continue to k3s if verification reports any `FAIL`.
