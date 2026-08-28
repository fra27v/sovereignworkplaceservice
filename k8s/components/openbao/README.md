# Tenant OpenBao Component

This component defines the reusable Tenant OpenBao deployment model.

Tenant OpenBao is the tenant security authority. It may host tenant secrets,
tenant policies, tenant authentication, tenant PKI, certificate issuance, and
other tenant secret engines. Applications use Tenant OpenBao, not Global
OpenBao.

Global OpenBao belongs to the operator plane. Its only intentional permanent
dependency for Tenant OpenBao is Transit auto-unseal.

## Release Model

Sovereign component releases are distinct from upstream OpenBao versions.
Release `1` uses upstream OpenBao `2.5.5`, pinned as:

```text
quay.io/openbao/openbao:2.5.5@sha256:6150c4a6b62067db6141c8da7a6a6b5763f4f47c315343d0c848b40fecdfd452
```

The release metadata lives in:

```text
k8s/components/openbao/releases/1/release.yaml
```

Release directories contain only release-specific metadata. Shared manifests,
configuration templates, scripts, tests, and runbooks stay at component level
while they remain compatible with all active releases.

The policy is:

```text
share by default
version only on incompatibility
```

If a future release requires incompatible shared assets, freeze the previous
compatible implementation under a versioned path and update older active
releases to reference it explicitly. Do not silently change the functional
behavior of an existing release.

Every component release referenced by an active tenant must remain deployable
from the current repository state.

## Release 1 Scope

Release `1` prepares the Tenant OpenBao bootstrap foundation and stops before
initialization.

Included:

- single-replica `StatefulSet`
- Integrated Storage / Raft PVC
- Transit auto-unseal configuration
- Operator CA trust projection for Transit TLS verification
- Transit token projection by Kubernetes Secret reference
- declarative stdout audit configuration
- bootstrap listener bound to `127.0.0.1:8200`
- validation, render, reconcile, and ready-for-init verification scripts

Not included:

- `bao operator init`
- tenant PKI creation
- OpenBao runtime TLS certificate creation
- OpenBao Kubernetes Service
- Ingress or IngressRoute
- Traefik routing
- HA replicas
- audit PVC or logging stack

## Bootstrap Isolation

Bootstrap mode uses HTTP only on loopback:

```text
127.0.0.1:8200
```

Plaintext is unreachable through the pod network by construction. The bootstrap
composition contains no OpenBao Service, headless Service, NodePort,
LoadBalancer, Ingress, IngressRoute, or Traefik route.

Administrative bootstrap access is:

```text
admin
  |
  | Kubernetes API TLS
  v
kubectl exec
  |
  v
OpenBao container
  |
  | local HTTP
  v
127.0.0.1:8200
```

Port-forwarding and temporary bootstrap pods are not the standard access path.

## StatefulSet And Raft

OpenBao runs as a `StatefulSet` with `replicas: 1` and Integrated Storage /
Raft. Release `1` does not introduce HA replicas.

The component defines how storage is mounted. Tenant configuration selects the
storage class and requested capacity. Audit logs are written to stdout, not to
the Raft PVC.

The StatefulSet has a required `serviceName` field for Kubernetes identity, but
this component does not create a Service during bootstrap. Release `1` is a
single-node Raft deployment and does not require an OpenBao API Service before
initialization.

## Transit Auto-Unseal

Tenant OpenBao uses Global OpenBao Transit auto-unseal. For `family-infra-01`,
the existing operator-plane contract is:

```text
Transit key: family-infra-01-autounseal
Policy: family-infra-01-transit-autounseal
Mount: transit/
```

Transit communication uses HTTPS with certificate verification. `tls_skip_verify`
is forbidden.

The Operator CA bundle is public trust material projected for verifying the
Global OpenBao Transit endpoint. It does not make the Operator CA part of the
tenant trust chain.

The Transit token is secret material. It is projected from a Kubernetes Secret
at runtime and must not be committed to Git or printed by scripts.

## Runtime Target

Runtime mode is a later phase. The target runtime mode will use OpenBao serving
TLS on `0.0.0.0:8200` with a certificate issued by the tenant PKI for:

```text
vault.internal
```

OpenBao itself will terminate TLS. The server certificate and private key will
require a runtime projection because OpenBao must read them before serving
HTTPS.

## Tenant PKI Target

Tenant PKI is independent from Operator PKI:

```text
family-infra Root CA
        |
        v
family-infra Issuing CA
        |
        +--> OpenBao server certificate
        +--> Traefik certificates
        +--> Keycloak certificates
        +--> Nextcloud certificates
        +--> other tenant certificates
```

No shared Sovereign Root CA exists. Operator PKI is not part of the tenant trust
chain.

## State Progression

The conceptual state progression is:

```text
ABSENT
  |
  v
BOOTSTRAP_DEPLOYED
  |
  v
INITIALIZED
  |
  v
SECURITY_BASELINED
  |
  v
PKI_READY
  |
  v
TLS_MATERIAL_READY
  |
  v
RUNTIME_READY
  |
  v
SERVICE_EXPOSED
```

Release `1` stops at:

```text
BOOTSTRAP_DEPLOYED / READY_FOR_INIT
```

Do not run `bao operator init` without explicit approval in the next phase.
