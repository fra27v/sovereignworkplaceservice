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
