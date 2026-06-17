# Runbook - Restart Services

## Purpose

Restart Docker Compose services without modifying configuration or data.

## Prerequisites

- Run commands from the service directory.
- For services that use Vault Agent, Vault must be reachable and unsealed.

## General Procedure

```powershell
cd .\core\traefik
docker compose restart
```

```powershell
cd .\core\vault
docker compose restart
```

```powershell
cd .\services\keycloak
docker compose restart
```

```powershell
cd .\services\identity
docker compose restart
```

```powershell
cd .\services\orangehrm
docker compose restart
```

```powershell
cd .\services\nextcloud
docker compose restart
```

```powershell
cd .\services\collabora
docker compose restart
```

```powershell
cd .\services\vaultwarden
docker compose restart
```

## Verification

```powershell
docker ps
docker logs <container> --tail=80
```

For Traefik, also verify the `*.internal` endpoints.

## Notes

- Restarting Vault may require manual unseal.
- Application containers often wait for files in `/secrets`; if Vault Agent cannot render them, the service may remain waiting.

TODO: define the recommended restart order for full maintenance windows.
