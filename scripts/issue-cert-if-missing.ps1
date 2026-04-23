param(
    [string]$Hostname,
    [string]$VaultContainer = "vault",
    [string]$VaultAddr = "http://127.0.0.1:8200",
    [string]$RoleName = "internal-dot",
    [string]$PkiIssuedRoot = "D:\lab-sovrano\pki\issued",
    [string]$Ttl = "672h",
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host ""
    Write-Host "=== issue-cert-if-missing.ps1 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Genera un certificato interno da Vault PKI se non esiste già."
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\issue-cert-if-missing.ps1 -Hostname <hostname>"
    Write-Host ""
    Write-Host "Esempi:"
    Write-Host "  .\issue-cert-if-missing.ps1 -Hostname files.internal"
    Write-Host "  .\issue-cert-if-missing.ps1 -Hostname auth.internal -RoleName internal-dot"
    Write-Host "  .\issue-cert-if-missing.ps1 -Hostname whoami.internal -Force"
    Write-Host ""
    Write-Host "Opzioni:"
    Write-Host "  -VaultContainer  Nome container Vault (default: vault)"
    Write-Host "  -VaultAddr       URL Vault dal punto di vista del container"
    Write-Host "  -RoleName        PKI role da usare per l'emissione"
    Write-Host "  -PkiIssuedRoot   Root locale per salvare i certificati"
    Write-Host "  -Ttl             TTL certificato (default: 672h)"
    Write-Host "  -Force           Rigenera anche se i file esistono già"
    Write-Host "  -Help            Mostra questo help"
    Write-Host ""
}

if ($Help -or -not $Hostname) {
    Show-Help
    exit 0
}

$servicePkiPath = Join-Path $PkiIssuedRoot $Hostname

if (-not (Test-Path $servicePkiPath)) {
    New-Item -ItemType Directory -Path $servicePkiPath -Force | Out-Null
}

$crtPath = Join-Path $servicePkiPath "tls.crt"
$keyPath = Join-Path $servicePkiPath "tls.key"
$caPath  = Join-Path $servicePkiPath "ca.crt"

$allExist = (Test-Path $crtPath) -and (Test-Path $keyPath) -and (Test-Path $caPath)

if ($allExist -and -not $Force.IsPresent) {
    Write-Host "I certificati esistono già per $Hostname. Nessuna azione eseguita." -ForegroundColor Yellow
    Write-Host "CRT: $crtPath"
    Write-Host "KEY: $keyPath"
    Write-Host " CA: $caPath"
    exit 0
}

$json = docker exec $VaultContainer sh -c "export VAULT_ADDR=$VaultAddr && vault write -format=json pki/issue/$RoleName common_name='$Hostname' ttl='$Ttl'"

if (-not $json) {
    throw "Vault non ha restituito dati."
}

$obj = $json | ConvertFrom-Json

if (-not $obj.data) {
    throw "La risposta di Vault non contiene il blocco data."
}
if (-not $obj.data.certificate) {
    throw "La risposta di Vault non contiene il certificato."
}
if (-not $obj.data.private_key) {
    throw "La risposta di Vault non contiene la chiave privata."
}
if (-not $obj.data.issuing_ca) {
    throw "La risposta di Vault non contiene la issuing CA."
}

[System.IO.File]::WriteAllText($crtPath, ($obj.data.certificate -replace "\\n", "`n"))
[System.IO.File]::WriteAllText($keyPath, ($obj.data.private_key -replace "\\n", "`n"))
[System.IO.File]::WriteAllText($caPath,  ($obj.data.issuing_ca -replace "\\n", "`n"))

Write-Host "Certificati generati per $Hostname" -ForegroundColor Green
Write-Host "CRT: $crtPath"
Write-Host "KEY: $keyPath"
Write-Host " CA: $caPath"
Write-Host ""
Write-Host "Nota: lo script non registra automaticamente il servizio in Traefik." -ForegroundColor Cyan
Write-Host "Usa poi register-service.ps1 per aggiornare routes.generated.yml e tls.generated.yml." -ForegroundColor Cyan