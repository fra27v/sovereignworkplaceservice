# Tenants

This directory contains tenant-specific Kubernetes configuration and deployment
composition.

Reusable workload implementations belong under `k8s/components/`. This
directory defines where and how those reusable components are instantiated for a
specific tenant.

Tenant-specific configuration may include runtime values, domains, hostnames,
storage decisions, component composition, tenant runbooks, and other
configuration that is intentionally specific to that tenant.

Tenant directories are created only when actual tenant-specific configuration is
introduced. No placeholder tenant directories are maintained.

Current tenants:

- `family-infra/`: first tenant configuration, currently selecting Tenant
  OpenBao component release `1`.

## Future Tenant Structure

A tenant will typically have a structure similar to:

```text
k8s/tenants/<tenant>/
|-- README.md
|-- tenant.yaml
`-- components/
```

Directories and files are created only when actual tenant-specific
configuration exists. Do not maintain placeholder tenant directories,
placeholder component directories, or empty configuration files.

## Tenant Configuration

The future canonical tenant configuration file is `tenant.yaml`. Use YAML
instead of `.env` files for structured non-secret tenant configuration.

The configuration principle is:

```text
global when shared
local when component-specific
```

`tenant.yaml` contains values that describe the tenant as a whole or are shared
by multiple components. Examples include the tenant name, component release
selection, tenant-wide PKI policy, internal DNS domain, tenant-wide storage
defaults, and other genuinely shared non-secret settings.

Example:

```yaml
schemaVersion: 1

tenant:
  name: family-infra

components:
  openbao:
    release: 1

pki:
  root:
    ttl: 87600h
  issuing:
    ttl: 26280h
  leaf:
    default_ttl: 2160h
```

This example documents the model only. It does not create a tenant or select an
actual component release.

A value must have one authoritative location. If a value can be derived
reliably, it should generally be derived instead of duplicated.

The repository should contain only the current desired configuration for each
tenant. Do not maintain active files such as:

```text
tenant-v1.yaml
tenant-v2.yaml
tenant-v3.yaml
openbao-config-v1.yaml
openbao-config-v2.yaml
```

Git history preserves previous desired states. The current working tree contains
the desired current state.

## Component-Specific Configuration

Do not put every application parameter into `tenant.yaml`. Avoid turning the
tenant file into a monolithic configuration database containing all settings for
OpenBao, Keycloak, Nextcloud, Matrix, midPoint, or other workloads.

Component-specific values belong under that component's tenant instantiation
only when they are actually necessary:

```text
k8s/tenants/<tenant>/
`-- components/
    `-- <component>/
        `-- config.yaml
```

Such a component-specific configuration file should exist only when there are
actual component-specific values to store.

The desired configuration precedence is:

```text
component release defaults
        +
tenant-wide configuration
        +
optional component-specific configuration
        |
        v
effective desired configuration
```

Overrides should be exceptions, not the normal mechanism for tenant divergence.

## Component Release Selection

A tenant selects a supported Sovereign component release, not an arbitrary
upstream software version.

Example:

```yaml
schemaVersion: 1

tenant:
  name: customer-a

components:
  openbao:
    release: 2
  matrix:
    release: 4
  nextcloud:
    release: 1
```

This means:

```text
openbao.release = 2
    -> k8s/components/openbao/releases/2/

matrix.release = 4
    -> k8s/components/matrix/releases/4/

nextcloud.release = 1
    -> k8s/components/nextcloud/releases/1/
```

The tenant does not directly control independent upstream versions. This model
is intentionally different from:

```text
tenant A -> OpenBao X.Y.Z
tenant B -> OpenBao X.Y+1
tenant C -> arbitrary version
```

Tenants declare their selected component release so upgrades can be staged
without uncontrolled customer divergence. For example:

```text
family-infra -> component release 4
internal validation tenant -> component release 4
customer-a -> component release 3
customer-b -> component release 3
```

This is controlled rollout, not uncontrolled tenant divergence.

## Configuration Schema Versioning

The tenant YAML contract has its own `schemaVersion`. Configuration versioning
is separate from both component release versioning and upstream software
versioning.

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
configuration schema. If an upgrade requires a new schema, the upgrade path must
include the necessary migration logic or documentation. Tenant configuration is
migrated in place; old copies are not kept as active files in the current tree.

Conceptually:

```text
component release 3
config schema 2

        upgrade

component release 4
config schema 3
```

## PKI Policy

Security policy values such as certificate TTLs belong in configuration and
must not be hardcoded into operational scripts.

The initial tenant PKI model is:

```yaml
pki:
  root:
    ttl: 87600h
  issuing:
    ttl: 26280h
  leaf:
    default_ttl: 2160h
```

Meaning:

```text
Root CA      = 10 years
Issuing CA   = 3 years
default leaf = 90 days
```

These are configuration values because scripts need them for creation and
reconciliation, certificate renewal logic needs a known policy, changes must be
explicit and reviewable in Git, and the same policy may be used by multiple
tenant components.

## Secret Handling

Neither tenant configuration nor component configuration may contain secret
material.

Forbidden Git content includes:

- passwords
- OpenBao tokens
- root tokens
- recovery shares
- Transit credentials
- API keys
- private keys
- Kubernetes Secret data values

The architectural principle is:

```text
Git = source of truth for repeatable non-secret configuration

OpenBao = source of truth for runtime secrets
```

Runtime Kubernetes Secrets may be projections when required by a workload, but
they are not the authoritative configuration source.

Bootstrap and recovery material may have a separate protected custody
mechanism.

## Current Rebuild

All component releases referenced by an active tenant must remain deployable
from the current repository state. A tenant rebuild must not depend on manually
checking out historical Git commits.

For example, if the current tenant configuration says:

```yaml
components:
  openbao:
    release: 2
  matrix:
    release: 4
  nextcloud:
    release: 1
```

then the current repository must still contain the implementation assets
required for:

```text
openbao release 2
matrix release 4
nextcloud release 1
```

A normal rebuild conceptually becomes:

1. Read current `tenant.yaml`.
2. Validate referenced component releases.
3. Load each immutable component release.
4. Combine release defaults with tenant configuration.
5. Restore required secrets and data from their authoritative recovery sources.
6. Deploy.
7. Reconcile.
8. Verify.

Current rebuild uses:

```text
current repository
+
current tenant.yaml
+
currently referenced component releases
+
current recovery data/secrets
```

## Historical Restore

Historical restore is different from current rebuild. A backup and recovery
process should eventually record the exact Git commit SHA corresponding to the
deployed state.

Conceptually:

```text
backup data
+
backup metadata
+
repository commit SHA
```

This allows exact historical reconstruction even if an old component release
has later been retired from the current operational branch. This document only
defines the principle; it does not implement backup metadata.
