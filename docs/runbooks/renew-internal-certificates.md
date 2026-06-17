# Runbook - Renew Internal Certificates

## Purpose

Renew the internal certificates used by Traefik route files matched by `core/traefik/dynamic/*.internal.yml`.

## Prerequisites

- Vault container `vault` started and unsealed.
- Vault PKI engine and `internal-dot` role already configured.
- Script `scripts/renew-traefik-certs.ps1` available.
- Traefik container `traefik` running.

## Procedure

From the repository root:

```powershell
cd .\scripts
.\renew-traefik-certs.ps1
```

The script:

- reads `..\core\traefik\dynamic\*.internal.yml`.
- extracts hostnames.
- calls `issue-cert-if-missing.ps1 -Force` for each hostname.
- restarts the Traefik container.
- prints the latest Traefik logs.

Current limitation: the script only processes files whose names match `*.internal.yml`. It does not process `whoami.yml`, even though that route uses host `whoami.internal` and `tls.yml` contains a `whoami.internal` certificate entry.

## Verification

```powershell
docker logs traefik --tail=80
```

Open the affected internal endpoints and verify that the certificate is valid against the internal CA installed on the client.

## Rollback

TODO: define a rollback procedure for previous certificates. The current script overwrites files in `pki/issued/<hostname>`.

## Warning

Do not copy `tls.key`, Vault tokens, or sensitive output into shared logs.
