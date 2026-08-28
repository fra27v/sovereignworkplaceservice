# Kubernetes Repository Structure

This directory contains the Kubernetes operating model for Sovereign Workplace
Services.

The top-level taxonomy is:

- `common/`
- `components/`
- `operator-plane/`
- `tenants/`

The principle is:

```text
common = how reusable host and Kubernetes baselines are applied
components = what reusable workloads can be deployed
operator-plane = global operator runtime
tenants = where and how reusable components are instantiated
```

## common

`k8s/common/` contains shared host and Kubernetes operational baselines.

It contains reusable installation, configuration, reconciliation, and
verification logic. It must not contain tenant-specific names, DNS names, IP
addresses, tokens, or secrets.

## components

`k8s/components/` contains reusable workload and component definitions shared by
tenant environments.

Components must not contain environment-specific runtime values. Tenant values,
domains, hostnames, storage decisions, and runtime composition belong under
`k8s/tenants/`.

Component directories are added only when a reusable workload is actually
implemented. No placeholder component directories are maintained.

Components own supported component releases, approved upstream software
versions, image digests, manifests, reusable defaults, reconciliation behavior,
upgrade paths, and verification logic. A component release is distinct from the
upstream software version it deploys, and upgrades must be explicit and
reviewable through Git.

Future component implementations use immutable release catalogs under each
component. A release referenced by an active tenant must remain deployable from
the current repository state and must not be modified in place.

## operator-plane

`k8s/operator-plane/` contains the global/operator control-plane
implementation.

This directory is intentionally self-contained and is not being refactored by
the `common/` and `tenants/` reorganization because it represents a tested live
deployment.

## tenants

`k8s/tenants/` contains tenant-specific configuration, values, runbooks, and
deployment composition.

Tenant directories are added only when actual tenant-specific configuration is
introduced. No placeholder tenant directories are maintained.

Future tenants use `tenant.yaml` for structured non-secret tenant-wide
configuration. Tenants select supported Sovereign component releases, not
arbitrary upstream software versions. Component-specific tenant values belong
under that component's tenant instantiation only when they are actually needed.

Tenant configuration uses a YAML `schemaVersion` that is separate from both the
component release and the upstream software version. The current tree contains
the current desired tenant configuration; Git history preserves previous
desired states. Historical restore should record the repository commit SHA that
matches the backed-up deployed state.

## Removed environments Category

`k8s/environments/` is no longer used as a top-level category because it
duplicated the tenant model. Tenant runtime configuration now belongs under
`k8s/tenants/`.

## Git Posture

Commit only non-secret operating intent:

- scripts
- runbooks
- policy files
- Helm values without secrets
- manifests and templates
- `.example` files
- verification logic

Do not commit tokens, passwords, private keys, kubeconfig files, generated
cluster state, seal material, real `.env` files, or other secret material.
