# Common k3s Baseline

This directory contains the reusable single-node k3s baseline.

The baseline configuration in `config.yaml` is real, non-secret repository
configuration. It intentionally does not set `node-name` or `tls-san`; k3s uses
the host OS hostname as the node name, and tenant-specific API server SANs must
be added only as explicit instance overrides when required.

The pinned k3s version is recorded once in `dependencies.lock.json`.

## Flow

```bash
sudo ./k8s/common/k3s/scripts/setup-k3s.sh prepare
sudo ./k8s/common/k3s/scripts/setup-k3s.sh install
sudo ./k8s/common/k3s/scripts/setup-k3s.sh verify
```
