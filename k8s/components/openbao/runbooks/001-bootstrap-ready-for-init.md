# Tenant OpenBao Bootstrap To Ready For Init

This runbook prepares Tenant OpenBao for explicit initialization and then stops.

Do not run:

```bash
bao operator init
```

This phase does not create tenant PKI, runtime TLS material, a Kubernetes
Service, Ingress, IngressRoute, or Traefik route.

## Preconditions

- Global OpenBao is initialized and unsealed.
- Global OpenBao Transit is configured for `family-infra-01`.
- The Transit key is `family-infra-01-autounseal`.
- The Transit policy is `family-infra-01-transit-autounseal`.
- The Transit token has been placed in protected custody outside Git.
- The public Operator CA bundle has been published for `family-infra-01`.
- k3s secret encryption is enabled.

## Validate Configuration

From the repository root:

```bash
k8s/components/openbao/scripts/validate-tenant-config.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml
```

This validates tenant schema, tenant name, selected release, image digest,
storage policy, PKI TTL policy, recovery configuration, canonical DNS, and
Transit projection references without reading or printing secrets.

## Validate Selected Release

Review:

```text
k8s/components/openbao/releases/1/release.yaml
```

Release `1` must point to upstream OpenBao `2.5.5` and the approved immutable
image digest.

## Validate Global Transit Prerequisites

Use the existing operator-plane verification from the operator-plane runbooks.
Do not edit operator-plane files from this Tenant OpenBao procedure.

The required contract is:

```text
Transit mount: transit/
Transit key: family-infra-01-autounseal
Transit policy: family-infra-01-transit-autounseal
```

## Project Transit Runtime Credential

Create or update the runtime Kubernetes Secret out of band from the protected
Transit token custody source. Do not paste the token into shell history, chat,
runbooks, commits, or logs.

Expected runtime projection:

```text
namespace: openbao-family-infra
secret: openbao-transit-autounseal
key: token
```

The Kubernetes Secret is a runtime projection only. OpenBao or another
protected custody mechanism remains the long-term authoritative source.

## Project Operator CA Trust Material

Project the public Operator CA bundle into:

```text
namespace: openbao-family-infra
configmap: operator-ca-bundle
key: ca.crt
mount path: /openbao/tls/operator-ca-bundle.pem
```

The Operator CA bundle is public trust material for verifying Global OpenBao
Transit TLS. It is not a tenant CA and is not part of the family-infra trust
chain.

## Render Bootstrap Manifest

```bash
k8s/components/openbao/scripts/render-bootstrap.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml \
  --output /tmp/family-infra-openbao-bootstrap.yaml
```

Inspect the rendered manifest locally. It must not contain Secret data values.

## Reconcile Bootstrap StatefulSet

First run a server-side dry run:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml \
  --dry-run
```

After review:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml \
  --apply
```

The reconcile script renders and applies only the bootstrap foundation. It does
not run `bao operator init`.

## Verify Ready For Init

Static verification:

```bash
k8s/components/openbao/scripts/verify-ready-for-init.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml
```

Live verification after reconcile:

```bash
k8s/components/openbao/scripts/verify-ready-for-init.sh \
  --tenant-file k8s/tenants/family-infra/tenant.yaml \
  --live
```

The live check verifies the expected StatefulSet/PVC/projections and checks
OpenBao through:

```text
kubectl exec -> http://127.0.0.1:8200
```

## Required Bootstrap Properties

- The OpenBao pod is created by a `StatefulSet`.
- Replica count is `1`.
- Raft storage is backed by a PVC.
- Storage class is `local-path`.
- Requested storage is `1Gi`.
- Transit seal configuration is present.
- Transit TLS verification is enabled.
- `tls_skip_verify` is absent.
- Operator CA trust material is projected.
- Transit token is projected by Secret reference only.
- Audit is declared in server configuration.
- Audit target is stdout.
- Bootstrap API listener is exactly `127.0.0.1:8200`.
- Bootstrap HTTP is local-only.
- No bootstrap API listener uses `0.0.0.0:8200`.
- No OpenBao Service exists.
- No Ingress exists.
- No IngressRoute exists.
- No Traefik route exists.
- OpenBao remains uninitialized.

## Stop

Stop at:

```text
BOOTSTRAP_DEPLOYED / READY_FOR_INIT
```

Obtain explicit approval before any initialization command is prepared or run.
