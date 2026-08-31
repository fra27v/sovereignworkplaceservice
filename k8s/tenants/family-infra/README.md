# family-infra Tenant

Tenant identity:

```text
tenant: family-infra
node: family-infra-01
OpenBao component release: 1
storageClass: local-path
storage request: 1Gi
canonical DNS: vault.internal
recovery shares: 3
recovery threshold: 2
Global OpenBao Transit endpoint: https://operator-vault.varrese.com
Operator artifacts endpoint: https://operator-artifacts.varrese.com
```

The authoritative current desired configuration is:

```text
k8s/tenants/family-infra/tenant.yaml
```

Do not maintain historical copies such as `tenant-v1.yaml`. Git history
preserves previous desired states.

## Current Phase

The current phase prepares Tenant OpenBao bootstrap and stops before
initialization:

```text
BOOTSTRAP_DEPLOYED / READY_FOR_INIT
```

Do not run:

```bash
bao operator init
```

The next gate is explicit initialization approval.

## Tenant OpenBao

Tenant OpenBao is the tenant security authority for `family-infra`. It is
separate from Global OpenBao and will eventually host tenant secrets, tenant
policies, tenant authentication, tenant PKI, and certificate issuance.

Global OpenBao is used only for Transit auto-unseal.

## Bootstrap Mode

Bootstrap mode uses:

```text
OpenBao listener: 127.0.0.1:8200
protocol: HTTP
access path: kubectl exec -> localhost
```

There is no OpenBao Service, Ingress, IngressRoute, or Traefik route during
bootstrap.

## Storage

OpenBao runs as a single-replica StatefulSet with Integrated Storage / Raft.
The tenant configuration selects:

```text
storageClass: local-path
size: 1Gi
```

Audit logs are written to stdout, not to the Raft PVC.

## Transit Dependency

Tenant OpenBao uses the existing Global OpenBao Transit contract for
`family-infra-01`:

```text
Transit key: family-infra-01-autounseal
Transit policy: family-infra-01-transit-autounseal
Transit mount: transit/
```

Transit communication uses HTTPS with certificate verification. The public
Operator CA bundle is projected only to verify the Global OpenBao Transit
endpoint. It is not part of the tenant trust chain.

The external Transit endpoint is:

```text
https://operator-vault.varrese.com
```

This is the operator-plane `operator-vault.varrese.com` endpoint exposed
through Traefik TCP passthrough, with TLS terminated by Global OpenBao using an
Operator PKI certificate. Tenant OpenBao must not use an operator-plane
`.svc.cluster.local` name.

The Transit token is secret material. It must not be committed, printed, or
stored in `tenant.yaml`.

## Operator Trust Retrieval

The Operator CA bundle used by tenant bootstrap is retrieved through a
tenant-specific flow:

```text
tenant.yaml -> fetch-operator-trust.sh -> interactive BasicAuth -> operator-artifacts -> operator-ca-bundle.pem + .sha256 -> checksum/cert validation -> verified public trust material
```

The endpoint is configured explicitly and separately from the Transit endpoint:

```text
operatorPlane.artifacts.address: https://operator-artifacts.varrese.com
```

Run:

```bash
k8s/tenants/family-infra/scripts/fetch-operator-trust.sh --output-dir <path>
```

The script reads `tenant.node` and `operatorPlane.artifacts.address` from
`tenant.yaml`. For `family-infra`, the BasicAuth username is derived as:

```text
family-infra-01
```

The BasicAuth credential is requested interactively by `curl`. It must not be
stored in Git, `tenant.yaml`, shell history, Kubernetes Secret manifests, or
ConfigMaps.

The script downloads:

```text
https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem
https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem.sha256
```

Files are downloaded to a restrictive temporary directory first. The bundle is
published only after the SHA256 checksum succeeds and the PEM parses as a CA
certificate. The CA bundle is public trust material, not a Kubernetes Secret.

Future behavior, not implemented in this phase:

```text
if Tenant OpenBao is available and contains the operator-artifacts credential:
  use that credential
else:
  prompt interactively
```

## Tenant PKI

The tenant PKI is independent:

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

No shared Sovereign Root CA exists. Operator PKI is not part of the tenant
trust chain.

The initial PKI TTL policy in `tenant.yaml` is:

```text
Root CA:      87600h
Issuing CA:   26280h
default leaf: 2160h
```

## Recovery

The configured recovery policy is:

```text
shares: 3
threshold: 2
```

Recovery share values are not stored in Git. They do not replace Transit
auto-unseal and cannot locally unseal OpenBao when Transit is unavailable. They
authorize privileged recovery procedures such as emergency root-token recovery.

Future custody:

```text
share 1 -> external vault A
share 2 -> external vault B
share 3 -> external vault C

any 2 -> authorized recovery
```

This repository does not implement that external custody process in this phase.

## Secrets

Do not commit Transit credentials, Transit tokens, initial root tokens, recovery
share values, administrative tokens, passwords, private keys, TLS private keys,
or Kubernetes Secret values.

```text
Git = source of truth for repeatable non-secret configuration

OpenBao = source of truth for tenant runtime secrets
```
