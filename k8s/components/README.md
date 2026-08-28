# Components

This directory contains reusable Kubernetes workload and component
implementations shared across tenant deployments.

A component defines how a workload is deployed in a reusable and supported way.
Future components may include workloads such as OpenBao, Keycloak, midPoint,
Nextcloud, or Matrix, but component directories are added only when a reusable
component is actually implemented. No placeholder component directories are
maintained.

Reusable components must not contain tenant-specific runtime values such as:

- tenant names
- customer names
- tenant DNS names
- tenant IP addresses
- tenant-specific storage choices
- credentials
- tokens
- secrets

Tenant-specific values and deployment composition belong under `k8s/tenants/`.

Current reusable components:

- `openbao/`: Tenant OpenBao component implementation.

## Release Catalog

Each component will eventually contain an immutable catalog of supported
releases.

Conceptual future structure:

```text
k8s/components/openbao/
|-- README.md
`-- releases/
    |-- 1/
    |-- 2/
    `-- 3/
```

This structure is documentation-only until real component implementation exists.
Do not create component directories, release directories, or release metadata by
convention alone.

The key principle is:

```text
A component release is a complete, immutable deployment definition.
```

A release may contain component metadata, approved upstream software version,
approved immutable image digest, manifests, configuration defaults,
configuration schema, reconciliation logic, upgrade logic, validation logic,
verify logic, operational runbooks, and migrations required by that release.

Once a release is published and referenced by a tenant, it must not be modified
in place. If anything relevant changes, create a new component release.

## Component Releases

A Sovereign component release and the upstream software version are different
concepts.

For example:

```text
Sovereign OpenBao component release: 3
OpenBao upstream version: X.Y.Z
```

`component release != upstream software version`.

A new component release may exist even when the upstream software version does
not change. Component releases may change because of manifest changes, security
hardening, storage layout changes, configuration schema changes, reconciliation
logic changes, upgrade logic changes, verification logic changes, policy
changes, or operational runbook changes.

`k8s/components/<component>/` is the authoritative place defining which
implementation releases are supported for that component. A component owns:

- the supported upstream version
- the approved image digest
- manifests
- reusable configuration
- configuration schema
- defaults
- reconciliation behavior
- upgrade path
- validation and verification logic

Conceptually, a future component may declare metadata similar to:

```yaml
component:
  name: openbao
  release: 3

runtime:
  image:
    repository: example/openbao
    version: X.Y.Z
    digest: sha256:...
```

This is a documentation example only. It does not define an actual OpenBao
release, upstream version, image repository, or digest.

## Upstream Version Pinning

A component release owns the approved upstream runtime dependency. Tenant
configuration must not independently select arbitrary upstream versions.

Conceptually:

```text
tenant
    |
    v
component release 3
    |
    +--> upstream software version X.Y.Z
    +--> approved image digest
    +--> manifests
    +--> configuration schema
    +--> reconcile logic
    +--> verify logic
```

The human-readable upstream version or tag documents what is deployed. The
digest identifies the exact immutable container image.

Project policy:

- no `latest`
- no uncontrolled floating tags
- digest pinning where the project controls the runtime
- dependency updates through Git
- upgrades must be explicit and reviewable

## Configuration Schema Versioning

Configuration versioning is separate from component release versioning and from
the upstream software version.

```text
component release
    = version of our deployment implementation

upstream software version
    = version of the packaged application

config schemaVersion
    = format/version of the YAML configuration contract
```

Example:

```text
component release: 7
upstream OpenBao: X.Y.Z
config schemaVersion: 3
```

A future component release may keep the same upstream version but require a new
configuration schema. If a component release requires a new configuration
schema, the release upgrade path must include the required migration logic or
documentation.

Conceptually:

```text
component release 3
config schema 2

        upgrade

component release 4
config schema 3
```

## Release Management

Component releases provide the supported implementation boundary. Tenants move
between supported component releases in a controlled way instead of directly
choosing unrelated upstream software versions.

A normal upgrade should conceptually be:

1. Prepare a new component release.
2. Validate the upstream upgrade path.
3. Update the approved image version and digest.
4. Update manifests or configuration when required.
5. Update migration and reconciliation logic.
6. Update verification and regression logic.
7. Validate on an internal tenant.
8. Update the selected tenant release.
9. Reconcile that tenant.
10. Verify the tenant.
11. Continue rollout to other tenants.

## Supported Release Retention

All component releases referenced by an active tenant must remain deployable
from the current repository state.

A component release cannot be removed from the current operational repository
while any active tenant references it. For example:

```text
family-infra -> OpenBao release 3
customer-a   -> OpenBao release 2
customer-b   -> OpenBao release 2
```

Both releases must remain available:

```text
openbao/releases/2/
openbao/releases/3/
```

Once no active tenant references a release, it becomes eligible for retirement
according to a future retention and rollback policy. This document does not
define a retention duration.
