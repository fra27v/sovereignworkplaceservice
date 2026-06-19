# Operator Artifacts Architecture

## Purpose

`operator-artifacts.<domain>` is the operator-plane artifact distribution endpoint.

It distributes bootstrap and configuration artifacts to tenants. It is separate from `operator-vault.<domain>`.

## Connectivity

Tenants pull artifacts outbound over HTTPS. No inbound connectivity to tenant environments is required.

SSH and SCP are intentionally not used for artifact distribution because they require broader host access patterns and operational key handling than this service needs.

## Authentication

Token authentication is used initially. Real tenant tokens must not be committed to Git, pasted into chat, or stored in runbooks.

BasicAuth through Traefik is acceptable for the first implementation.

Token transfer to tenant hosts must use a secure out-of-band channel.

## TLS

`operator-artifacts.<domain>` may use Let's Encrypt because it is an HTTPS artifact delivery endpoint.

This does not imply Let's Encrypt for `operator-vault.<domain>`.

`operator-vault.<domain>` remains private Operator PKI with TLS terminated by OpenBao.

## Artifact Model

The repository serves only public artifacts.

It must never serve private keys, root tokens, recovery material, static seal keys, or init JSON files.

Real artifact contents are not committed to public Git if they expose operational metadata.

The first expected real artifact family is:

```text
operator-ca-bundle.crt
operator-ca-bundle.sha256
operator-ca-bundle.meta.json
```

Artifact signatures are a deferred hardening step.

## Filesystem Model

Public artifacts are stored under:

```text
/var/lib/sovereignworkplaceservice/operator-artifacts/public
```

Private operational material is stored under:

```text
/var/lib/sovereignworkplaceservice/operator-artifacts/private
```

The static server must mount only the public directory read-only.

The private directory must never be mounted into the artifact server pod.

## Tenant Layout

Tenant artifacts are separated by tenant path, for example:

```text
tenants/family-infra-01/
```

This prepares the system for multiple tenants.

## Naming

`operator-artifacts.<domain>` is separate from `operator-vault.<domain>`.

`operator-vault.<domain>` is the logical operator-plane vault service DNS name. `operator-vault` is currently implemented with OpenBao.

Existing OpenBao configuration remains under the `openbao/` repository folders because those files are technology-specific. The `operator-artifacts/` folders are reserved for artifact repository configuration and operations.

## Deferred Hardening

Deferred hardening steps include:

- IP allowlist.
- Artifact signing.
- mTLS client authentication.
- Stronger per-tenant authorization model.
- Private artifact registry implementation if needed.

These should be added after the first artifact distribution workflow is working and the operational boundaries are clear.

## CA Bundle Rotation

CA bundle rotation uses the artifact repository.

Rotation uses overlap:

1. Publish old CA plus new CA.
2. Rotate new leaf certificates.
3. Publish new CA only after old leaf certificates are retired.

The tenant updates its local trust bundle by pulling the artifact, verifying it, updating a ConfigMap or local trust storage, and restarting or reloading dependent components.

## Initial Model

The initial model is:

- Operator-plane service endpoint: `operator-artifacts.<domain>`.
- Tenant access pattern: outbound HTTPS pull from tenant environments.
- Initial authentication: tenant token.
- Artifact storage: local VPS filesystem paths configured per environment.
- Repository content: examples, manifests, scripts, and runbooks only.

Do not commit real domains, artifacts, tokens, certificates, private keys, or generated access files.
