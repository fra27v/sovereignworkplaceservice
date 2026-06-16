param(
    [string]$Container = "midpoint",

    # Assumendo che lo script sia in D:\lab-sovrano\services\identity
    [string]$IssuedDir = (Join-Path $PSScriptRoot "..\..\pki\issued\identity.internal"),

    [switch]$RestartMidpoint,
    [switch]$ForceRecreateMidpoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-DockerBash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [Parameter(Mandatory = $true)]
        [string]$StepName
    )

    Write-Host ""
    Write-Host "=== $StepName ==="

    $tmpHostScript = Join-Path $env:TEMP ("midpoint-keystore-step-" + [guid]::NewGuid().ToString() + ".sh")
    $tmpContainerScript = "/tmp/update-keystores-step.sh"

    try {
        # Normalize Windows CRLF to Linux LF, otherwise bash sees pipefail\r
        $normalizedScript = $Script -replace "`r`n", "`n" -replace "`r", "`n"

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tmpHostScript, $normalizedScript, $utf8NoBom)

        docker cp $tmpHostScript "${Container}:$tmpContainerScript"
        if ($LASTEXITCODE -ne 0) {
            throw "docker cp failed while copying temporary script"
        }

        docker exec $Container bash $tmpContainerScript
        if ($LASTEXITCODE -ne 0) {
            throw "$StepName failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        docker exec $Container rm -f $tmpContainerScript 2>$null | Out-Null

        if (Test-Path $tmpHostScript) {
            Remove-Item $tmpHostScript -Force
        }
    }
}

Write-Host ""
Write-Host "=== update-keystores.ps1 ==="
Write-Host "Container : $Container"
Write-Host "IssuedDir : $IssuedDir"
Write-Host ""

if (-not (Test-Path $IssuedDir)) {
    throw "Issued directory not found: $IssuedDir"
}

# 1. Check input files and generate /tmp stores inside the container.
$generateScript = @'
set -Eeuo pipefail

echo "Checking input files..."
ls -l /tls/tls.crt /tls/tls.key /tls/ca.crt
ls -l /secrets/tls_keystore_password /secrets/tls_truststore_password

ks_pass="$(tr -d '\r\n' < /secrets/tls_keystore_password)"
ts_pass="$(tr -d '\r\n' < /secrets/tls_truststore_password)"

if [ -z "$ks_pass" ]; then
  echo "ERROR: tls_keystore_password is empty" >&2
  exit 1
fi

if [ -z "$ts_pass" ]; then
  echo "ERROR: tls_truststore_password is empty" >&2
  exit 1
fi

echo "Removing temporary stores..."
rm -f /tmp/keystore.p12 /tmp/truststore.p12

echo "Creating /tmp/keystore.p12..."
openssl pkcs12 -export \
  -in /tls/tls.crt \
  -inkey /tls/tls.key \
  -certfile /tls/ca.crt \
  -name tomcat \
  -out /tmp/keystore.p12 \
  -passout "pass:${ks_pass}"

echo "Creating /tmp/truststore.p12..."
keytool -importcert \
  -noprompt \
  -alias internal-ca \
  -file /tls/ca.crt \
  -keystore /tmp/truststore.p12 \
  -storetype PKCS12 \
  -storepass "$ts_pass"

echo "Verifying /tmp/keystore.p12..."
keytool -list \
  -storetype PKCS12 \
  -keystore /tmp/keystore.p12 \
  -storepass "$ks_pass" \
  >/dev/null

echo "Verifying /tmp/truststore.p12..."
keytool -list \
  -storetype PKCS12 \
  -keystore /tmp/truststore.p12 \
  -storepass "$ts_pass" \
  >/dev/null

echo "Temporary stores OK."
'@

Invoke-DockerBash -StepName "Generate and verify temporary stores" -Script $generateScript

# 2. Copy generated stores from container to host.
$keystoreHost = Join-Path $IssuedDir "keystore.p12"
$truststoreHost = Join-Path $IssuedDir "truststore.p12"

Write-Host ""
Write-Host "=== Copy stores to host ==="

docker cp "${Container}:/tmp/keystore.p12" $keystoreHost
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy keystore.p12 to $keystoreHost"
}

docker cp "${Container}:/tmp/truststore.p12" $truststoreHost
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy truststore.p12 to $truststoreHost"
}

Write-Host "Copied:"
Write-Host " - $keystoreHost"
Write-Host " - $truststoreHost"

# 3. Verify the files as midPoint sees them through /tls.
$verifyMountedScript = @'
set -Eeuo pipefail

ks_pass="$(tr -d '\r\n' < /secrets/tls_keystore_password)"
ts_pass="$(tr -d '\r\n' < /secrets/tls_truststore_password)"

echo "Checking mounted stores..."
ls -l /tls/keystore.p12 /tls/truststore.p12

echo "Verifying /tls/keystore.p12..."
keytool -list \
  -storetype PKCS12 \
  -keystore /tls/keystore.p12 \
  -storepass "$ks_pass" \
  >/dev/null

echo "Verifying /tls/truststore.p12..."
keytool -list \
  -storetype PKCS12 \
  -keystore /tls/truststore.p12 \
  -storepass "$ts_pass" \
  >/dev/null

echo "Mounted stores OK."

echo ""
echo "Keystore aliases:"
keytool -list \
  -storetype PKCS12 \
  -keystore /tls/keystore.p12 \
  -storepass "$ks_pass" \
  | grep -Ei 'tomcat|PrivateKeyEntry|trustedCertEntry' || true

echo ""
echo "Truststore aliases:"
keytool -list \
  -storetype PKCS12 \
  -keystore /tls/truststore.p12 \
  -storepass "$ts_pass" \
  | grep -Ei 'internal-ca|PrivateKeyEntry|trustedCertEntry' || true
'@

Invoke-DockerBash -StepName "Verify mounted /tls stores" -Script $verifyMountedScript

# 4. Optional restart/recreate.
if ($ForceRecreateMidpoint) {
    Write-Host ""
    Write-Host "=== Force recreate midpoint ==="
    docker compose up -d --force-recreate midpoint
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up -d --force-recreate midpoint failed"
    }
}
elseif ($RestartMidpoint) {
    Write-Host ""
    Write-Host "=== Restart midpoint ==="
    docker restart $Container | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "docker restart $Container failed"
    }
}

Write-Host ""
Write-Host "All keystores updated successfully."

if ($RestartMidpoint -or $ForceRecreateMidpoint) {
    Write-Host ""
    Write-Host "midPoint logs:"
    docker logs $Container --tail 120
}
else {
    Write-Host ""
    Write-Host "Next step:"
    Write-Host "  docker restart $Container"
    Write-Host ""
    Write-Host "Or:"
    Write-Host "  docker compose up -d --force-recreate midpoint"
}