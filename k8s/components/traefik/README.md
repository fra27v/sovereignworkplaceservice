# Traefik Component

Reusable component assets for an independently managed Traefik ingress
controller.

The current common k3s baseline uses the k3s-packaged Traefik and k3s ServiceLB
instead. Do not install this component as a second ingress controller for
`family-infra` without an explicit future architecture decision.

This component contains shared chart defaults and install/verify scripts for a
separate Traefik deployment path. Tenant-specific runtime decisions live under
`k8s/tenants/<tenant>`.

## Files

- `component.env` defines the Helm repository, chart, and chart version.
- `values/base.values.yaml` defines shared Traefik defaults.
- `scripts/install.sh` installs or upgrades a Traefik release from an
  environment file.
- `scripts/verify.sh` checks the deployed release, discovers configured
  hostPorts from the Deployment, and verifies those ports are listening.

## Current Posture

This directory is retained for future explicit independent-Traefik work. It is
not part of the current `family-infra` default installation flow.

Do not commit secrets, certificates, tokens, credentials, kubeconfig files, or
generated local cluster state.
