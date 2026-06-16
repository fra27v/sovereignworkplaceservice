param(
    [string]$DynamicDir = "..\core\traefik\dynamic",
    [string]$IssuerScript = ".\issue-cert-if-missing.ps1",
    [string]$TraefikContainer = "traefik"
)

Write-Host ""
Write-Host "=== renew-traefik-certs.ps1 ==="
Write-Host "Renewing all Traefik internal certificates..."
Write-Host ""

$ErrorActionPreference = "Stop"

if (-not (Test-Path $DynamicDir)) {
    throw "Dynamic Traefik directory not found: $DynamicDir"
}

if (-not (Test-Path $IssuerScript)) {
    throw "Issuer script not found: $IssuerScript"
}

$hostnames = Get-ChildItem $DynamicDir -Filter "*.internal.yml" |
    ForEach-Object {
        $_.BaseName
    } |
    Sort-Object -Unique

if (-not $hostnames -or $hostnames.Count -eq 0) {
    throw "No *.internal.yml files found in $DynamicDir"
}

Write-Host "Hostnames found:"
$hostnames | ForEach-Object { Write-Host " - $_" }
Write-Host ""

foreach ($hostname in $hostnames) {
    Write-Host "Renewing certificate for $hostname ..."
    & $IssuerScript -Hostname $hostname -Force

    if ($LASTEXITCODE -ne 0) {
        throw "Certificate renewal failed for $hostname"
    }

    Write-Host "OK: $hostname"
    Write-Host ""
}

Write-Host "Restarting Traefik container: $TraefikContainer"
docker restart $TraefikContainer | Out-Host

if ($LASTEXITCODE -ne 0) {
    throw "Failed to restart Traefik container"
}

Write-Host ""
Write-Host "Traefik logs:"
docker logs $TraefikContainer --tail=80

Write-Host ""
Write-Host "All Traefik certificates renewed successfully."