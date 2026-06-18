# Traefik

Reusable platform component for Traefik ingress routing.

This component contains shared chart defaults and install/verify scripts only.
Environment-specific runtime decisions live under `k8s/environments/<name>`.

The `family-infra` instance is a runtime Traefik for a single-node k3s
environment. It directly owns host ports `80` and `443` through hostPort. It is
not the future global/front edge Traefik, which will live on separate
infrastructure.

## Files

- `component.env` defines the Helm repository, chart, and chart version.
- `values/base.values.yaml` defines shared Traefik defaults.
- `scripts/install.sh` installs or upgrades a Traefik release from an
  environment file.
- `scripts/verify.sh` checks the deployed release, discovers configured
  hostPorts from the Deployment, and verifies those ports are listening.

## Usage

Install a runtime instance with an environment file:

```bash
sudo ./k8s/platform/components/traefik/scripts/install.sh \
  --env-file k8s/environments/family-infra/components/traefik-runtime.env
```

Verify it:

```bash
sudo ./k8s/platform/components/traefik/scripts/verify.sh \
  --env-file k8s/environments/family-infra/components/traefik-runtime.env
```

Do not commit secrets, certificates, tokens, credentials, kubeconfig files, or
generated local cluster state.
