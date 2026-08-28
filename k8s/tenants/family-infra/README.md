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

The Transit token is secret material. It must not be committed, printed, or
stored in `tenant.yaml`.

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
