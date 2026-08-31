# Tenant OpenBao Bootstrap To Ready For Init

This runbook prepares Tenant OpenBao for explicit initialization and then stops.

Do not run:

```bash
bao operator init
```

This phase does not create tenant PKI, runtime TLS material, a Kubernetes
Service, Ingress, IngressRoute, or Traefik route.

## Bootstrap Phase Model

Rendering and reconciliation have different phase sets:

| Tool | Phase | Purpose |
| --- | --- | --- |
| `render-bootstrap.sh` | `foundation` | Render Namespace only |
| `render-bootstrap.sh` | `statefulset` | Render bootstrap workload only |
| `render-bootstrap.sh` | `all` | Render complete bootstrap configuration for inspection |
| `reconcile-bootstrap.sh` | `foundation` | Apply or validate Namespace phase |
| `reconcile-bootstrap.sh` | `statefulset` | Apply or validate bootstrap workload phase |

`reconcile-bootstrap.sh` intentionally does not support `--phase all`.
Foundation and StatefulSet reconciliation are separate so the Operator CA
ConfigMap and Transit token Secret can be projected and live Transit preflight
can pass before the StatefulSet is deployed.

## Preconditions

- Global OpenBao is initialized and unsealed.
- Global OpenBao Transit is configured for the tenant node declared in
  `tenant.yaml`.
- The Transit key follows the tenant node convention:
  `${tenant.node}-autounseal`.
- The Transit policy follows the tenant node convention:
  `${tenant.node}-transit-autounseal`.
- The Transit token has been placed in protected custody outside Git.
- The public Operator CA bundle has been published for the tenant node.
- k3s secret encryption is enabled.
- The externally reachable Global OpenBao endpoint is declared in
  `openbao.transit.address`.

## Validate Configuration

From the repository root:

```bash
k8s/components/openbao/scripts/validate-tenant-config.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml
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

The required contract is resolved from tenant configuration:

```text
Transit mount: transit/
Transit key: ${tenant.node}-autounseal
Transit policy: ${tenant.node}-transit-autounseal
Transit endpoint: ${openbao.transit.address}
```

For `family-infra`, this currently resolves to:

```text
Transit mount: transit/
Transit key: family-infra-01-autounseal
Transit policy: family-infra-01-transit-autounseal
Transit endpoint: https://operator-vault.varrese.com
```

Do not use `*.svc.cluster.local` addresses for Transit. Tenant OpenBao runs in
a different Kubernetes cluster from Global OpenBao.

## Reconcile Foundation

Create the namespace first. This phase does not deploy OpenBao:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --phase foundation \
  --dry-run
```

After review:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --phase foundation \
  --apply
```

## Project Transit Runtime Credential

Create or update the runtime Kubernetes Secret out of band from the protected
Transit token custody source. Do not paste the token into shell history, chat,
runbooks, commits, or logs.

Expected runtime projection:

```text
namespace: openbao-${tenant.name}
secret: openbao-transit-autounseal
key: token
```

The Kubernetes Secret is a runtime projection only. OpenBao or another
protected custody mechanism remains the long-term authoritative source.

## Project Operator CA Trust Material

Project the public Operator CA bundle into:

```text
namespace: openbao-${tenant.name}
configmap: operator-ca-bundle
key: ca.crt
mount path: /openbao/tls/operator-ca-bundle.pem
```

The Operator CA bundle is public trust material for verifying Global OpenBao
Transit TLS. It is not a tenant CA and is not part of the tenant trust chain.

## Verify Transit Prerequisites

Static preflight:

```bash
k8s/components/openbao/scripts/verify-transit-preflight.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml
```

Live preflight after namespace, CA ConfigMap, and Transit Secret projection:

```bash
k8s/components/openbao/scripts/verify-transit-preflight.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --live
```

Live preflight verifies namespace existence, CA ConfigMap key presence, Transit
Secret key presence, DNS/TLS reachability, and a minimal Transit encrypt call
without printing token or response data.

## Render Bootstrap Manifest

```bash
k8s/components/openbao/scripts/render-bootstrap.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --phase all \
  --output /tmp/<tenant>-openbao-bootstrap.yaml
```

Inspect the rendered manifest locally. It must not contain Secret data values.

## Reconcile Bootstrap StatefulSet

First run a server-side dry run:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --phase statefulset \
  --dry-run
```

After review:

```bash
k8s/components/openbao/scripts/reconcile-bootstrap.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
  --phase statefulset \
  --apply
```

The statefulset apply phase runs live Transit preflight first. If namespace,
Operator CA ConfigMap, Transit Secret, or Transit HTTPS validation is missing,
the StatefulSet is not deployed.

The reconcile script does not run `bao operator init`.

## Verify Ready For Init

Static verification:

```bash
k8s/components/openbao/scripts/verify-ready-for-init.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml
```

Live verification after reconcile:

```bash
k8s/components/openbao/scripts/verify-ready-for-init.sh \
  --tenant-file k8s/tenants/<tenant>/tenant.yaml \
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
- `cluster_addr` is configured as `https://127.0.0.1:8201`.
- Storage class matches `storage.openbao.class`.
- Requested storage matches `storage.openbao.size`.
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
