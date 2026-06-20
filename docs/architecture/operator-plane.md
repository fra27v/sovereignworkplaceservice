# Operator Plane Architecture

This document describes the first `vps-family-control` operator-plane bootstrap model.

The operator plane is the administrative control plane for family infrastructure. It is separate from tenant workloads and from the `trading` namespace. Operator-plane bootstrap must be repeatable, non-destructive, and explicit about which local files are temporary bootstrap material.

## Authority Model

Global OpenBao is the operator-plane authority for secrets.

Kubernetes Secrets are runtime projections or bootstrap imports. They are not the long-term source of truth for operator-plane credentials. A Kubernetes Secret may be created from current local bootstrap files during the first implementation phase, but the target model is to project it from Global OpenBao.

Local `.env` files are bootstrap, import, and recovery material only. They must remain local, ignored by Git, and treated as temporary operational material until the corresponding values are imported into OpenBao and synchronized into Kubernetes.

The same principle applies later to tenant environments: OpenBao is the secret authority and runtime secrets are projections into the workload runtime.

## Current Endpoints

`operator-artifacts` is the authenticated artifact delivery endpoint. It is served through Traefik with Traefik TLS termination. Public TLS certificates for `operator-artifacts` use Let's Encrypt DNS-01 with OVH credentials projected into the Traefik runtime.

`operator-artifacts` authentication material is currently represented as local bootstrap files and a Kubernetes BasicAuth Secret. The target source of truth is OpenBao KV.

## Future Operator Vault Endpoint

`operator-vault` will expose Global OpenBao later through Traefik TCP passthrough with TLS terminated by OpenBao itself.

`operator-vault` must not use Let's Encrypt certificates. It will use the future Operator CA hosted by Global OpenBao.

## Operator PKI Next Phase

Global OpenBao will also host the Operator PKI/CA in the next phase. Operator CA keys and OpenBao transit keys are OpenBao-managed state, not KV secrets.

This first version does not implement Operator PKI. It documents the boundary so that the bootstrap model does not couple internal operator trust to public ACME certificates.

## Bootstrap Interface

Manual component scripts remain available for focused debugging. The environment-level operator interface is:

- `k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh`
- `k8s/operator-plane/environments/vps-family-control/scripts/verify-operator-plane.sh`

The bootstrap entrypoint orchestrates validated component scripts where stable entrypoints exist. The verification entrypoint performs read-only checks and runs available component verification scripts.
