# Install Traefik runtime for family-infra

This runbook installs and verifies the `family-infra` runtime Traefik instance.

## Scope

This Traefik instance is the runtime ingress controller for the single-node
`family-infra` k3s environment. It directly owns host ports `80` and `443` via
hostPort.

Out of scope:

- Future global/front edge Traefik.
- Application services.
- Secrets, certificates, tokens, or credentials.

## Preconditions

- The k3s baseline is installed and verified.
- Embedded k3s Traefik is disabled.
- Ports `80` and `443` are available on the node.
- The repository is cloned on the target node.

## Install

Run this command on the target node:

```bash
sudo ./k8s/platform/components/traefik/scripts/install.sh \
  --env-file k8s/environments/family-infra/components/traefik-runtime.env
```

## Verify

Run this command on the target node:

```bash
sudo ./k8s/platform/components/traefik/scripts/verify.sh \
  --env-file k8s/environments/family-infra/components/traefik-runtime.env
```

The verification checks the Helm release, pods, deployment, IngressClass,
services, hostPort listeners, and absence of an unexpected LoadBalancer
Service.

## Optional Smoke Test

Apply the versioned whoami routing smoke test:

```bash
sudo ./k8s/environments/family-infra/tests/smoke/whoami-routing/apply.sh
```

Verify that Traefik routes `whoami.internal` through the HTTP `web`
entrypoint:

```bash
sudo ./k8s/environments/family-infra/tests/smoke/whoami-routing/verify.sh
```

Delete the smoke test when finished:

```bash
sudo ./k8s/environments/family-infra/tests/smoke/whoami-routing/delete.sh
```

## Regression

After installing Traefik, run the regression suite when you want to verify the
k3s baseline, runtime Traefik, and whoami routing together:

```bash
sudo ./k8s/environments/family-infra/tests/regression/run.sh
```

## Rollback

Run this command on the target node:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  helm uninstall traefik-family-infra -n ingress-family-infra
```

Do not commit generated local files, kubeconfig files, certificates, tokens,
credentials, or secrets.
