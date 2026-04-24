param(
    [string]$Hostname,
    [string]$TargetUrl,

    [string]$TraefikRoot = "D:\lab-sovrano\core\traefik",
    [string]$PkiRoot = "D:\lab-sovrano\pki",

    [string]$RouterName,
    [string]$ServiceName,

    [string]$ServersTransportName = "internal-ca",
    [string]$EntryPoint = "websecure",
    [string[]]$Middlewares = @(),

    [switch]$NoTls,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Show-Help {
    Write-Host ""
    Write-Host "=== register-service.ps1 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Crea o aggiorna un servizio Traefik (modello per-file)." 
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\register-service.ps1 -Hostname <hostname> -TargetUrl <url>"
    Write-Host ""
    Write-Host "Esempi:"
    Write-Host "  .\register-service.ps1 -Hostname files.internal -TargetUrl https://nextcloud:443"
    Write-Host "  .\register-service.ps1 -Hostname whoami.internal -TargetUrl http://whoami:80 -NoTls"
    Write-Host ""
    Write-Host "Opzioni:"
    Write-Host "  -TraefikRoot            Root Traefik locale"
    Write-Host "  -PkiRoot                Root PKI locale"
    Write-Host "  -RouterName             Nome router Traefik"
    Write-Host "  -ServiceName            Nome service Traefik"
    Write-Host "  -ServersTransportName   Nome serversTransport (default: internal-ca)"
    Write-Host "  -EntryPoint             EntryPoint Traefik (default: websecure)"
    Write-Host "  -Middlewares            Lista middlewares"
    Write-Host "  -NoTls                  Non aggiorna tls.yml e non mette tls:{} nel router"
    Write-Host "  -Help                   Mostra questo help"
    Write-Host ""
}

if ($Help -or [string]::IsNullOrWhiteSpace($Hostname) -or [string]::IsNullOrWhiteSpace($TargetUrl)) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($RouterName)) {
    $RouterName = (($Hostname -replace '[^a-zA-Z0-9]+', '-') -replace '-+$', '').ToLower()
}

if ([string]::IsNullOrWhiteSpace($ServiceName)) {
    $ServiceName = "$RouterName-svc"
}

$dynamicPath = Join-Path $TraefikRoot "dynamic"
$serviceFilePath = Join-Path $dynamicPath "$Hostname.yml"
$tlsFilePath = Join-Path $dynamicPath "tls.yml"

if (-not (Test-Path $dynamicPath)) {
    throw "Directory dynamic non trovata: $dynamicPath"
}

try {
    $uri = [System.Uri]$TargetUrl
}
catch {
    throw "TargetUrl non valido: $TargetUrl"
}

$useServersTransport = $uri.Scheme.ToLowerInvariant() -eq "https"

$validMiddlewares = @()
if ($Middlewares) {
    $validMiddlewares = @($Middlewares | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$lines = @()
$lines += "http:"
$lines += "  routers:"
$lines += "    ${RouterName}:"
$lines += ('      rule: "Host(`{0}`)"' -f $Hostname)
$lines += "      entryPoints:"
$lines += "        - $EntryPoint"

if (-not $NoTls.IsPresent) {
    $lines += "      tls: {}"
}

$lines += "      service: $ServiceName"

if ($validMiddlewares.Count -gt 0) {
    $lines += "      middlewares:"
    foreach ($mw in $validMiddlewares) {
        $lines += "        - $mw"
    }
}

$lines += ""
$lines += "  services:"
$lines += "    ${ServiceName}:"
$lines += "      loadBalancer:"
$lines += "        passHostHeader: true"

if ($useServersTransport) {
    $lines += "        serversTransport: $ServersTransportName"
}

$lines += "        servers:"
$lines += "          - url: ""$TargetUrl"""

$serviceYaml = $lines -join "`r`n"
Write-Utf8NoBom -Path $serviceFilePath -Content $serviceYaml

Write-Host "File servizio creato/aggiornato: $serviceFilePath" -ForegroundColor Green

if (-not $NoTls.IsPresent) {
    $crtPath = Join-Path (Join-Path (Join-Path $PkiRoot "issued") $Hostname) "tls.crt"
    $keyPath = Join-Path (Join-Path (Join-Path $PkiRoot "issued") $Hostname) "tls.key"

    if (-not (Test-Path $crtPath)) {
        throw "Certificato non trovato: $crtPath"
    }

    if (-not (Test-Path $keyPath)) {
        throw "Chiave privata non trovata: $keyPath"
    }

    if (-not (Test-Path $tlsFilePath)) {
        $initialTls = @(
            "tls:"
            "  certificates:"
        ) -join "`r`n"
        Write-Utf8NoBom -Path $tlsFilePath -Content ($initialTls + "`r`n")
    }

    $tlsRaw = Get-Content $tlsFilePath -Raw
    $certFileRef = "/pki/issued/$Hostname/tls.crt"
    $keyFileRef = "/pki/issued/$Hostname/tls.key"

    if ($tlsRaw -notmatch [regex]::Escape($certFileRef)) {
        $tlsBlock = @(
            "    - certFile: $certFileRef"
            "      keyFile: $keyFileRef"
        ) -join "`r`n"

        $newTls = $tlsRaw.TrimEnd() + "`r`n" + $tlsBlock + "`r`n"
        Write-Utf8NoBom -Path $tlsFilePath -Content $newTls

        Write-Host "TLS aggiornato per $Hostname" -ForegroundColor Green
    }
    else {
        Write-Host "TLS già presente per $Hostname" -ForegroundColor Yellow
    }
}
else {
    Write-Host "NoTls attivo: tls.yml non modificato." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Servizio registrato: $Hostname -> $TargetUrl" -ForegroundColor Green
Write-Host "File dinamico: $serviceFilePath"
Write-Host "File TLS    : $tlsFilePath"
Write-Host ""
Write-Host "Se necessario:"
Write-Host "cd D:\lab-sovrano\core\traefik"
Write-Host "docker compose restart traefik"