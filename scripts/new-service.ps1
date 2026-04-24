param(
    [string]$Hostname,
    [string]$TargetUrl,

    [string]$TraefikRoot = "D:\lab-sovrano\core\traefik",
    [string]$PkiRoot = "D:\lab-sovrano\pki",
    [string]$PkiIssuedRoot = "D:\lab-sovrano\pki\issued",

    [string]$VaultContainer = "vault",
    [string]$VaultAddr = "http://127.0.0.1:8200",
    [string]$RoleName = "internal-dot",
    [string]$Ttl = "672h",

    [string]$RouterName,
    [string]$ServiceName,
    [string]$ServersTransportName = "internal-ca",
    [string]$EntryPoint = "websecure",
    [string[]]$Middlewares = @(),

    [switch]$NoTls,
    [switch]$ForceCert,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host ""
    Write-Host "=== new-service.ps1 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Crea/aggiorna un servizio Traefik compatibile con il modello per-file."
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\new-service.ps1 -Hostname <hostname> -TargetUrl <url>"
    Write-Host ""
    Write-Host "Esempi:"
    Write-Host "  .\new-service.ps1 -Hostname files.internal -TargetUrl https://nextcloud:443"
    Write-Host "  .\new-service.ps1 -Hostname whoami.internal -TargetUrl http://whoami:80 -NoTls"
    Write-Host ""
    Write-Host "Opzioni:"
    Write-Host "  -NoTls        -> non genera certificati e non aggiorna tls.yml"
    Write-Host "  -ForceCert    -> rigenera certificati"
    Write-Host "  -Help         -> mostra questo help"
    Write-Host ""
}

if ($Help -or -not $Hostname -or -not $TargetUrl) {
    Show-Help
    exit 0
}

$issueScript = Join-Path $PSScriptRoot "issue-cert-if-missing.ps1"
$registerScript = Join-Path $PSScriptRoot "register-service.ps1"

Write-Host "Uso issue script   : $issueScript" -ForegroundColor DarkGray
Write-Host "Uso register script: $registerScript" -ForegroundColor DarkGray

if (-not (Test-Path $issueScript)) {
    throw "Script non trovato: $issueScript"
}
if (-not (Test-Path $registerScript)) {
    throw "Script non trovato: $registerScript"
}

if (-not $NoTls.IsPresent) {
    if ($ForceCert.IsPresent) {
        & $issueScript `
            -Hostname $Hostname `
            -VaultContainer $VaultContainer `
            -VaultAddr $VaultAddr `
            -RoleName $RoleName `
            -PkiIssuedRoot $PkiIssuedRoot `
            -Ttl $Ttl `
            -Force
    }
    else {
        & $issueScript `
            -Hostname $Hostname `
            -VaultContainer $VaultContainer `
            -VaultAddr $VaultAddr `
            -RoleName $RoleName `
            -PkiIssuedRoot $PkiIssuedRoot `
            -Ttl $Ttl
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Emissione certificato fallita per $Hostname"
    }
}
else {
    Write-Host "TLS disabilitato: salto emissione certificati." -ForegroundColor Yellow
}

if ($NoTls.IsPresent) {
    & $registerScript `
        -Hostname $Hostname `
        -TargetUrl $TargetUrl `
        -TraefikRoot $TraefikRoot `
        -PkiRoot $PkiRoot `
        -RouterName $RouterName `
        -ServiceName $ServiceName `
        -ServersTransportName $ServersTransportName `
        -EntryPoint $EntryPoint `
        -Middlewares $Middlewares `
        -NoTls
}
else {
    & $registerScript `
        -Hostname $Hostname `
        -TargetUrl $TargetUrl `
        -TraefikRoot $TraefikRoot `
        -PkiRoot $PkiRoot `
        -RouterName $RouterName `
        -ServiceName $ServiceName `
        -ServersTransportName $ServersTransportName `
        -EntryPoint $EntryPoint `
        -Middlewares $Middlewares
}

if ($LASTEXITCODE -ne 0) {
    throw "Registrazione servizio fallita per $Hostname"
}

Write-Host ""
Write-Host "Servizio pronto: $Hostname -> $TargetUrl" -ForegroundColor Green
Write-Host "Controlla Traefik su: https://$Hostname" -ForegroundColor Green
Write-Host "Se necessario: docker compose restart traefik" -ForegroundColor Yellow