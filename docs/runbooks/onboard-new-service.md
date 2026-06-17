# Runbook - Onboard New Service

## Purpose

Add a Traefik route and, if needed, an internal certificate for a new service.

## Prerequisites

- Docker service already defined and connected to the `proxy` network.
- Container name resolvable by Traefik.
- Vault running and unsealed if internal TLS is needed.
- PKI role `internal-dot` available.

## Procedure

Backend HTTPS:

```powershell
.\scripts\new-service.ps1 -Hostname app.internal -TargetUrl https://app:443
```

Backend HTTP:

```powershell
.\scripts\new-service.ps1 -Hostname app.internal -TargetUrl http://app:80 -NoTls
```

## File Verification

Check:

- `core/traefik/dynamic/app.internal.yml`
- `core/traefik/dynamic/tls.yml`, if TLS is enabled.
- `pki/issued/app.internal/`, if TLS is enabled.

For HTTPS backends, also check whether the generated route needs a `serversTransports` block with the internal CA. The current script writes the `serversTransport` reference but not the CA transport definition.

Do not open or copy the private key content.

## Runtime Verification

```powershell
docker logs traefik --tail=80
```

Then open `https://app.internal`.

## TODO

TODO: add a checklist for Vault Agent/policy for the new service.

TODO: document DNS/hostfile handling for `app.internal`.
