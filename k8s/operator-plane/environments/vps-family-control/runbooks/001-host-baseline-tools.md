# Host Baseline Tools

This runbook documents baseline host tooling for the `vps-family-control` operator-plane VPS.

## Purpose

`check-host-baseline-tools.sh` verifies that required commands are available on the host.

`install-host-baseline-apt-tools.sh` installs only apt-managed baseline tools:

- `jq`
- `openssl`
- `curl`
- `git`
- `apache2-utils`

`apache2-utils` is required because it provides `htpasswd` for operator artifacts BasicAuth.

## Boundaries

Helm is intentionally not installed or upgraded by the apt baseline script.

`kubectl` is expected to be provided by k3s.

OS patching and broad package upgrades are not handled here.

The install script does not install or manage k3s, kubectl, Helm, OpenBao, operator artifacts, or tenant workloads.

## Recommended Usage

Check the host first:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/check-host-baseline-tools.sh
```

Install apt-managed baseline tools if needed:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/scripts/install-host-baseline-apt-tools.sh
```

Run the check again after any host changes:

```bash
./k8s/operator-plane/environments/vps-family-control/scripts/check-host-baseline-tools.sh
```

## Safe Output

The check script prints command availability and safe version output only.

It does not print secrets, tokens, certificates, keys, real domains, or IP addresses.
