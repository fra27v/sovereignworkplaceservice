# ADR 002: Operator Vault OpenBao Architecture

## Status

Accepted.

## Context

The operator-plane needs a vault service for bootstrap/operator secrets and for tenant OpenBao auto-unseal support.

The logical service name and the implementation technology are intentionally separate:

- `operator-vault.<domain>` is the logical DNS and service name.
- OpenBao is the current implementation technology.
- Repository folders remain named `openbao/` because the manifests, Helm values, scripts, and policies are technology-specific.

## Decisions

### Logical Service And Implementation

Use `operator-vault.<domain>` as the logical operator-plane vault service endpoint.

Use OpenBao as the implementation technology for the current operator-plane vault service.

Keep OpenBao-specific files under `openbao/` repository folders.

### Global And Tenant Split

Global OpenBao belongs to the operator-plane.

Tenant OpenBao belongs to a tenant environment.

Applications must use Tenant OpenBao, not Global OpenBao.

Global OpenBao is used for bootstrap/operator secrets and tenant auto-unseal support.

### Global OpenBao Target

The current Global OpenBao deployment target is:

- Namespace: `openbao-operator`.
- Helm release: `openbao-global`.
- Service type: `ClusterIP`.

Do not expose OpenBao on public port `8200`.

Do not use an OpenBao `LoadBalancer`, `NodePort`, or `hostPort`.

The external runtime endpoint will be `operator-vault.<domain>` on `443` through Traefik TCP TLS passthrough.

### Audit

OpenBao audit is declarative and config-based.

Do not use `bao audit enable` for this deployment.

Audit log contents must not be printed, pasted into chat, attached to tickets, or committed to Git.

Audit verification may list audit devices and check audit file existence only.

### Transit Auto-Unseal

Global OpenBao provides transit auto-unseal for Tenant OpenBao.

The first tenant transit key is:

```text
family-infra-01-autounseal
```

Transit key material is persistent state inside Global OpenBao storage.

The transit key must not be exported as plaintext.

The transit token can be renewed or regenerated if Global OpenBao is still recoverable.

The transit token is for Tenant OpenBao auto-unseal only, not for applications.

### Policy Management

OpenBao policies must be versioned as HCL files.

Scripts must apply versioned policy files.

Scripts must not define production policies inline with heredocs unless explicitly documented as temporary diagnostics.

### Disaster Recovery

Tenant OpenBao auto-unseal depends on the Global OpenBao transit key.

Losing Global OpenBao storage without backup can make the tenant vault unrecoverable after seal or restart.

Backup must include Global OpenBao storage plus the Global static seal key.

Recovery keys do not replace the Global static seal key or the transit key state.

The disaster recovery order is:

1. Restore Global OpenBao first.
2. Verify Global OpenBao can unseal.
3. Verify transit works.
4. Restore or restart Tenant OpenBao.

### TLS

`operator-vault.<domain>` uses private Operator PKI, not Let's Encrypt.

Traefik uses TCP passthrough.

Global OpenBao terminates TLS.

Tenant OpenBao trusts an Operator CA bundle.

Tenant OpenBao does not request or renew Global OpenBao certificates.

### CA Rotation

CA bundle rotation uses overlap:

1. Distribute old CA plus new CA.
2. Rotate leaf certificates.
3. Distribute new CA only after old leaf certificates are retired.

CA bundles are distributed through the operator artifacts system, not through public Git and not through SSH or SCP.

## Consequences

The operator-plane vault service can keep a stable logical DNS name while the implementation remains OpenBao-specific in the repository.

Global OpenBao must be treated as foundational operator-plane state. Tenant vault recoverability depends on Global OpenBao storage, the static seal key, and transit key state.

Tenant-facing application secret workflows must be implemented against Tenant OpenBao, not Global OpenBao.
