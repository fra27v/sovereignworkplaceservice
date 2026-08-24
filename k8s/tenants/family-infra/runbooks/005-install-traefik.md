# Verify packaged Traefik for family-infra

This runbook verifies the k3s-packaged Traefik and ServiceLB path for the
`family-infra` environment.

## Scope

Traefik is installed and reconciled by k3s as a packaged component in
`kube-system`. ServiceLB is also managed by k3s and exposes the Traefik
LoadBalancer Service on the node.

Out of scope:

- Installing an independent Traefik Helm release.
- OVH DNS credentials.
- Public ACME DNS-01 configuration.
- VPS-specific HelmChartConfig.
- Application services.
- Secrets, certificates, tokens, or credentials.

## Preconditions

- The k3s baseline is installed.
- The common k3s config has been prepared from `k8s/common/k3s/config.yaml`.
- k3s has been restarted after any config change.
- The repository is cloned on the target node.

## Verify

Run this command on the target node:

```bash
sudo ./k8s/common/k3s/scripts/setup-k3s.sh verify
```

The verification checks packaged Traefik, the Traefik LoadBalancer Service,
Service ports `80/TCP` and `443/TCP`, and ServiceLB readiness for the Traefik
Service.

## Optional Smoke Test

Apply the versioned whoami routing smoke test:

```bash
sudo ./k8s/tenants/family-infra/tests/smoke/whoami-routing/apply.sh
```

Verify that Traefik routes `whoami.internal` through the HTTP `web`
entrypoint:

```bash
sudo ./k8s/tenants/family-infra/tests/smoke/whoami-routing/verify.sh
```

Delete the smoke test when finished:

```bash
sudo ./k8s/tenants/family-infra/tests/smoke/whoami-routing/delete.sh
```

## Regression

Run the regression suite when you want to verify the k3s baseline and whoami
routing together:

```bash
sudo ./k8s/tenants/family-infra/tests/regression/run.sh
```

Do not install `k8s/components/traefik` as a second ingress controller without
an explicit future architecture decision.

Do not commit generated local files, kubeconfig files, certificates, tokens,
credentials, or secrets.
