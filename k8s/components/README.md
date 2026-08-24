# Components

This directory contains reusable Kubernetes workload and component
implementations shared across tenant deployments.

Components define how a workload can be deployed, but must not contain
tenant-specific runtime configuration such as tenant names, domains, hostnames,
IP addresses, storage choices, credentials, tokens, or secrets.

Tenant-specific values and deployment composition belong under `k8s/tenants/`.

Directories are added here only when a reusable component is actually
implemented. No placeholder component directories are maintained.
