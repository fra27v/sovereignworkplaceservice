# Install k3s for family-infra

This runbook installs and verifies the k3s baseline for the active
`family-infra` operational environment.

## Scope

This runbook covers only the k3s baseline.

Out of scope:

- Traefik installation.
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
- DNS is ready: `family-infra.internal` points to the node.
- Required ports have been checked, including `80`, `443`, and `6443`.

## Install

Run these commands on the target node:

```bash
cd ~/src/sovereignworkplaceservice
git pull --ff-only
sudo ./k8s/environments/family-infra/host/scripts/verify-host-baseline.sh \
  --hostname family-infra-01 \
  --ssh-port 50022 \
  --update-policy automatic
./k8s/environments/family-infra/scripts/setup-family-infra.sh prepare
./k8s/environments/family-infra/scripts/setup-family-infra.sh install
./k8s/environments/family-infra/scripts/setup-family-infra.sh verify
```

## Verify

The verification command checks:

- node Ready
- kube-system pods
- embedded k3s Traefik is absent from `kube-system`
- secrets encryption is enabled
- kubeconfig mode is `0600`
- key listening ports

It does not fail when the valid runtime Traefik exists in
`ingress-family-infra`.

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
