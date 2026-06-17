# Runbook - Troubleshoot Vault Agent

## Symptoms

- Application container keeps waiting for files in `/secrets`.
- Template files are not generated.
- Service logs show `waiting for Vault Agent secrets`.
- Vault Agent cannot authenticate.

## Checks

Verify Vault:

```powershell
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status
```

Verify agent logs:

```powershell
docker logs <nome-agent> --tail=120
```

Existing agent names:

- `keycloak-agent`
- `midpoint-agent`
- `orangehrm-agent`
- `nextcloud-agent`
- `collabora-agent`
- `vaultwarden-agent`

Verify that the service has template and config files:

```powershell
Get-ChildItem .\services\<servizio>\config
Get-ChildItem .\services\<servizio>\templates
```

## Common Causes

- Vault sealed.
- missing or invalid `role_id` or `secret_id`.
- Vault policy insufficient for the paths required by templates.
- template with wrong secret path.
- `secrets/` directory not mounted or not writable by Vault Agent.
- Vault Agent started, but the application service started before the required files existed.

## Actions

1. Unseal Vault if needed.
2. Restart the service Vault Agent.
3. Check agent logs.
4. Check that expected files exist, without printing their content.
5. Restart the dependent application service.

Example:

```powershell
cd .\services\nextcloud
docker compose restart vault-agent
docker compose restart nextcloud
```

TODO: document the Vault paths used by each template without including secret values.
