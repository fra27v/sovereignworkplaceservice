$VaultContainer = "vault"
$KeyFile = "vault-unseal-keys.txt"
$VaultAddr = "http://127.0.0.1:8200"

function Get-VaultStatus {
    $raw = docker exec -e VAULT_ADDR=$VaultAddr $VaultContainer vault status -format=json 2>$null
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
        return $null
    }
    return $raw | ConvertFrom-Json
}

if (!(Test-Path $KeyFile)) {
    Write-Error "Key file not found: $KeyFile"
    exit 1
}

Write-Host "Waiting for Vault container..."

$status = $null
for ($i = 0; $i -lt 30; $i++) {
    $status = Get-VaultStatus
    if ($null -ne $status) {
        break
    }
    Start-Sleep -Seconds 2
}

if ($null -eq $status) {
    Write-Error "Vault did not become reachable."
    exit 1
}

if ($status.sealed -eq $false) {
    Write-Host "Vault is already unsealed."
    exit 0
}

Write-Host "Vault is sealed. Starting unseal..."

$keys = Get-Content $KeyFile | Where-Object {
    $_ -and $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#")
}

foreach ($key in $keys) {
    docker exec -e VAULT_ADDR=$VaultAddr $VaultContainer vault operator unseal $key.Trim() | Out-Null

    $status = Get-VaultStatus

    if ($status.sealed -eq $false) {
        Write-Host "Vault unsealed successfully."
        exit 0
    }
}

Write-Error "Unseal failed. Check keys and Vault status."
exit 1