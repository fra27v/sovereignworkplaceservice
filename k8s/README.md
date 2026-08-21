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

## operator-plane

`k8s/operator-plane/` contains the global/operator control-plane
implementation.

This directory is intentionally self-contained and is not being refactored by
the `common/` and `tenants/` reorganization because it represents a tested live
deployment.

## tenants

`k8s/tenants/` contains tenant-specific configuration, values, runbooks, and
deployment composition.

- `family-infra/` is the local family tenant operational environment.
- `customer-template/` is the starting template for future customer tenants.
- `family-infra-01/` contains existing tenant identity and OpenBao metadata for
  the `family-infra-01` tenant record.

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
