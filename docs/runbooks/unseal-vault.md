# Runbook - Unseal Vault

## Purpose

Unseal Vault after startup or restart.

## Prerequisites

- Container `vault` running.
- Unseal keys available in a secure location.
- Do not copy keys or tokens into documentation.

## Local Automated Procedure

The repository contains `scripts/unseal-vault.ps1`, which reads `vault-unseal-keys.txt` in the script's current directory.

```powershell
cd .\scripts
.\unseal-vault.ps1
```

The script:

- waits for Vault to respond.
- reads Vault status.
- exits if Vault is already unsealed.
- tries non-empty, non-commented keys from the local file.

## Manual Procedure

```powershell
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault operator unseal
```

Repeat with the number of keys required by the init configuration.

## Verification

```powershell
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status
```

Expected state: `Sealed` false.

## Warning

`scripts/vault-unseal-keys.txt` and any equivalent file are sensitive. Do not include them in commits, documentation, or shared output.

TODO: define secure custody for unseal keys outside the repository.
