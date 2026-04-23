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

function Show-Help {
    Write-Host ""
    Write-Host "=== register-service.ps1 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Crea o aggiorna un file servizio Traefik e registra il certificato in tls.yml."
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

if ($Help -or -not $Hostname -or -not $TargetUrl) {
    Show-Help
    exit 0
}

if (-not $RouterName -or $RouterName.Trim() -eq "") {
    $RouterName = (($Hostname -replace '[^a-zA-Z0-9]+', '-') -replace '-+$','').ToLower()
}

if (-not $ServiceName -or $ServiceName.Trim() -eq "") {
    $ServiceName = "$RouterName-svc"
}

$dynamicPath = Join-Path $TraefikRoot "dynamic"
if (-not (Test-Path $dynamicPath)) {
    throw "Directory dynamic non trovata: $dynamicPath"
}

$serviceFilePath = Join-Path $dynamicPath "$Hostname.yml"
$tlsFilePath = Join-Path $dynamicPath "tls.yml"

$targetUri = [System.Uri]$TargetUrl
$targetScheme = $targetUri.Scheme.ToLowerInvariant()
$useServersTransport = $targetScheme -eq "https"

# Build service YAML
$lines = @()
$lines += "http:"
$lines += "  routers:"
$lines += "    $RouterName:"
$lines += "      rule: ""Host(`"$Hostname`")"""
$lines += "      entryPoints:"
$lines += "        - $EntryPoint"

if (-not $NoTls.IsPresent) {
    $lines += "      tls: {}"
}

$lines += "      service: $ServiceName"

if ($Middlewares -and $Middlewares.Count -gt 0) {
    $lines += "      middlewares:"
    foreach ($mw in $Middlewares) {
        if ($mw -and $mw.Trim() -ne "") {
            $lines += "        - $mw"
        }
    }
}

$lines += ""
$lines += "  services:"
$lines += "    $ServiceName:"
$lines += "      loadBalancer:"
$lines += "        passHostHeader: true"

if ($useServersTransport) {
    $lines += "        serversTransport: $ServersTransportName"
}

$lines += "        servers:"
$lines += "          - url: ""$TargetUrl"""

if ($useServersTransport) {
    $lines += ""
    $lines += "  serversTransports:"
    $lines += "    $ServersTransportName:"
    $lines += "      serverName: ""$Hostname"""
    $lines += "      rootCAs:"
    $lines += "        - ""/pki/ca/internal-ca.crt"""
}

$serviceYaml = $lines -join "`r`n"
Set-Content -Path $serviceFilePath -Value $serviceYaml -Encoding UTF8

Write-Host "File servizio scritto: $serviceFilePath" -ForegroundColor Green

if (-not $NoTls.IsPresent) {
    $crtHostPath = Join-Path (Join-Path (Join-Path $PkiRoot "issued") $Hostname) "tls.crt"
    $keyHostPath = Join-Path (Join-Path (Join-Path $PkiRoot "issued") $Hostname) "tls.key"

    if (-not (Test-Path $crtHostPath)) {
        throw "Certificato non trovato: $crtHostPath"
    }
    if (-not (Test-Path $keyHostPath)) {
        throw "Chiave privata non trovata: $keyHostPath"
    }

    if (-not (Test-Path $tlsFilePath)) {
        $baseTls = @(
            "tls:"
            "  certificates:"
        ) -join "`r`n"
        Set-Content -Path $tlsFilePath -Value $baseTls -Encoding UTF8
    }

    $tlsRaw = Get-Content $tlsFilePath -Raw
    if (-not $tlsRaw) {
        $tlsRaw = "tls:`r`n  certificates:`r`n"
    }

    $certBlock = @(
        "    - certFile: /pki/issued/$Hostname/tls.crt"
        "      keyFile: /pki/issued/$Hostname/tls.key"
    ) -join "`r`n"

    $alreadyPresent = $tlsRaw -match [regex]::Escape("/pki/issued/$Hostname/tls.crt")

    if (-not $alreadyPresent) {
        $tlsRaw = $tlsRaw.TrimEnd() + "`r`n" + $certBlock + "`r`n"
        Set-Content -Path $tlsFilePath -Value $tlsRaw -Encoding UTF8
        Write-Host "Certificato aggiunto a tls.yml per $Hostname" -ForegroundColor Green
    }
    else {
        Write-Host "Certificato già presente in tls.yml per $Hostname" -ForegroundColor Yellow
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
Write-Host "Se Traefik non ricarica automaticamente: docker compose restart traefik" -ForegroundColor Yellow