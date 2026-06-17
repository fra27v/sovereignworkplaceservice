# Runbook - Troubleshoot Traefik Routing

## Symptoms

- `*.internal` host does not respond.
- Browser-side TLS error.
- 404/502/503 error from Traefik.
- HTTPS backend not accepted because of CA or server name.

## Checks

Verify that Traefik is running:

```powershell
docker ps
docker logs traefik --tail=120
```

Verify static configuration:

```powershell
Get-Content .\core\traefik\traefik.yml
```

Verify dynamic route:

```powershell
Get-Content .\core\traefik\dynamic\<hostname>.yml
```

Verify registered certificate:

```powershell
Get-Content .\core\traefik\dynamic\tls.yml
```

## Common Causes

- Missing dynamic file or wrong hostname.
- Backend container not connected to the `proxy` network.
- `TargetUrl` points to the wrong port.
- HTTPS backend uses a certificate with a hostname different from `serverName`.
- Generated HTTPS route references `serversTransport` but lacks a matching `serversTransports` definition with the internal CA.
- Internal CA not available in the Traefik container.
- Client DNS or hostfile does not resolve `*.internal`.

## Actions

Restart Traefik after certificate or mount changes:

```powershell
cd .\core\traefik
docker compose restart traefik
```

Regenerate route/certificate if the service was registered incorrectly:

```powershell
.\scripts\new-service.ps1 -Hostname <hostname> -TargetUrl <url> -ForceCert
```

TODO: add standardized HTTP/TLS test commands for Windows.
