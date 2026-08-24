# Install k3s for family-infra

This runbook installs and verifies the k3s baseline for the active
`family-infra` operational environment.

## Scope

This runbook covers only the k3s baseline.

Out of scope:

- Independent Traefik chart installation.
- Application migration.
- OpenBao deployment.
- Keycloak, midPoint, Nextcloud, HR, Vaultwarden, and Collabora deployment.

## Preconditions

- Ubuntu Server is installed on the target node.
- The expected OS is Ubuntu Server 26.04 LTS on x86_64/amd64.
- SSH key login is working.
- SSH password login is disabled.
- The host baseline verification has completed with no `FAIL` entries.
- The repository is cloned on the target node.
- Required ports have been checked, including `80`, `443`, and `6443`.

## Install

Run these commands on the target node:

```bash
cd ~/src/sovereignworkplaceservice
git pull --ff-only
sudo ./k8s/common/host/scripts/verify-host-baseline.sh \
  --hostname family-infra-01 \
  --ssh-port 50022 \
  --update-policy automatic
sudo ./k8s/common/k3s/scripts/setup-k3s.sh prepare
sudo ./k8s/common/k3s/scripts/setup-k3s.sh install
sudo ./k8s/common/k3s/scripts/setup-k3s.sh verify
```

## Verify

The verification command checks:

- node Ready
- kube-system pods
- k3s packaged Traefik HelmChart, Deployment, and LoadBalancer Service
- k3s ServiceLB daemonset and pod readiness for Traefik
- Traefik Service ports `80/TCP` and `443/TCP`
- secrets encryption is enabled
- kubeconfig mode is `0600`
- k3s API listener state

Traefik is reconciled by k3s as a packaged component in `kube-system`.
Do not install an independent Traefik controller unless a future architecture
decision explicitly requires it.

## Recovery Notes

The k3s config file is:

```text
/etc/rancher/k3s/config.yaml
```

The kubeconfig file is:

```text
/etc/rancher/k3s/k3s.yaml
```

Follow k3s logs with:

```bash
sudo journalctl -u k3s -f
```

Do not commit generated local files, kubeconfig files, local node state, tokens,
or secrets.
