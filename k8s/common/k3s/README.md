# Common k3s Baseline

This directory contains the reusable single-node k3s baseline.

The baseline configuration in `config.yaml` is real, non-secret repository
configuration. It intentionally does not set `node-name` or `tls-san`; k3s uses
the host OS hostname as the node name, and tenant-specific API server SANs must
be added only as explicit instance overrides when required.

The common baseline intentionally uses k3s packaged Traefik and k3s ServiceLB.
For the current single-node baseline, Traefik is reconciled by k3s in
`kube-system`, its Service is `LoadBalancer`, and ServiceLB exposes the
Traefik ports on the node.

Environment-specific Traefik customization must stay separate from the common
k3s bootstrap. The operator VPS has its own `HelmChartConfig` and is not part
of this baseline refactor. The `family-infra` tenant currently follows the
default packaged Traefik and packaged ServiceLB path, with no OVH DNS,
public ACME DNS-01, or VPS-specific HelmChartConfig.

The pinned k3s version is recorded once in `dependencies.lock.json`.

No environment file is required for k3s bootstrap.

## Flow

```bash
sudo ./k8s/common/k3s/scripts/setup-k3s.sh prepare
sudo ./k8s/common/k3s/scripts/setup-k3s.sh install
sudo ./k8s/common/k3s/scripts/setup-k3s.sh verify
```

When an existing `/etc/rancher/k3s/config.yaml` differs from the repository
config, review with `prepare --dry-run`, apply with `prepare --force`, then
restart `k3s` explicitly before running `verify`. The `all` command does not
restart an already installed k3s service after a config-only change.
