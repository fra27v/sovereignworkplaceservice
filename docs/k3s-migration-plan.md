# k3s Migration Plan

## State

k3s is a future target. The current repository is Docker Compose first and does not contain complete Kubernetes manifests for the services.

## Target Objective

Progressively migrate from Docker Compose to k3s while preserving:

- repository-managed IaC.
- centralized routing.
- secrets managed by Vault/OpenBao or equivalent.
- internal TLS.
- separation between configuration, data, and runtime.

## Proposed Plan

1. Compose inventory.
   - Map containers, networks, volumes, ports, and dependencies.
   - Identify persistent directories and Docker volumes.

2. Storage.
   - Define PVCs for databases and application data.
   - TODO: choose k3s storage class.

3. Networking.
   - Map `*.internal` hostnames to Ingress or Gateway API.
   - Decide whether to keep Traefik as ingress controller.

4. Secrets.
   - Translate Vault Agent sidecar/template usage into a k3s model.
   - TODO: choose between sidecar agent, CSI driver, or another pattern.

5. PKI.
   - Move internal certificate issuance into a Kubernetes-friendly process.
   - TODO: define cert-manager integration or keep external scripts.

6. Service-by-service migration.
   - Start with a stateless or test service.
   - Then migrate services with databases.
   - Run restore tests before migrating real data.

7. Operations.
   - Add health checks, backup, monitoring, and logs.

## Non-Goals for Now

- Do not automatically convert all Compose files.
- Do not introduce k3s into the current runtime.
- Do not change existing service behavior.
