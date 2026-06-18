# whoami Traefik smoke test

This directory contains a versioned routing smoke test for the `family-infra`
runtime Traefik instance.

It deploys a single `traefik/whoami:v1.10.3` pod in the `smoke-whoami`
namespace and exposes it through the `traefik-family-infra` IngressClass at
`http://whoami.internal/`.

This is only a smoke test. It is not an application service and does not use
secrets, TLS certificates, tokens, or credentials.

## Commands

Apply the smoke test:

```bash
sudo ./k8s/environments/family-infra/scripts/apply-whoami-smoke-test.sh
```

Verify routing:

```bash
sudo ./k8s/environments/family-infra/scripts/verify-whoami-smoke-test.sh
```

Delete the smoke test:

```bash
sudo ./k8s/environments/family-infra/scripts/delete-whoami-smoke-test.sh
```
