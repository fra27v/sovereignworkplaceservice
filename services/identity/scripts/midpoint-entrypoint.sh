#!/usr/bin/env bash
set -euo pipefail

echo "=== midPoint entrypoint starting ==="

########################################
# 1. WAIT FOR SECRETS + TLS
########################################

echo "waiting for Vault/TLS files..."

until [ -s /secrets/db_password ] &&
      [ -s /secrets/tls_keystore_password ] &&
      [ -s /secrets/tls_truststore_password ] &&
      [ -s /tls/keystore.p12 ] &&
      [ -s /tls/truststore.p12 ] &&
      [ -s /secrets/midpoint_keystore_password ] &&
      [ -s /generated/config.xml ];
do
  sleep 2
done

echo "Vault/TLS/config ready"

echo "copying config.xml..."
cp /generated/config.xml /opt/midpoint/var/config.xml

########################################
# 2. INSTALL PSQL IF MISSING
########################################

if ! command -v psql >/dev/null 2>&1; then
  echo "installing postgresql client..."
  apt-get update
  apt-get install -y postgresql-client
fi

########################################
# 3. WAIT FOR POSTGRES
########################################

echo "waiting for PostgreSQL..."

until PGPASSWORD="$(cat /secrets/db_password)" psql \
  -h midpoint-db \
  -U midpoint \
  -d midpoint \
  -tAc "select 1" >/dev/null 2>&1;
do
  echo "PostgreSQL not ready yet..."
  sleep 5
done

echo "PostgreSQL is ready"

########################################
# 4. ENSURE MIDPOINT CONFIG EXISTS
########################################

cd /opt/midpoint

echo "ensuring midPoint config.xml exists..."
export MP_INIT_CFG=/opt/midpoint/var
export MP_SET_midpoint_administrator_initialPassword="$(tr -d '\r\n' < /secrets/midpoint_adm_password)"
bin/midpoint.sh init-native

########################################
# 5. CHECK SCHEMA
########################################

echo "checking midPoint schema..."

SCHEMA_EXISTS="$(PGPASSWORD="$(cat /secrets/db_password)" psql \
  -h midpoint-db \
  -U midpoint \
  -d midpoint \
  -tAc "select to_regclass('public.m_object');" | tr -d '[:space:]')"

if [ -z "$SCHEMA_EXISTS" ]; then
  echo "schema NOT found → initializing..."

  bin/ninja.sh run-sql --create --mode REPOSITORY
  bin/ninja.sh run-sql --create --mode AUDIT

  echo "schema initialized"
else
  echo "schema already exists → skipping init"
fi

########################################
# 6. SSL CONFIG
########################################

echo "configuring SSL..."

update-ca-certificates

export JAVA_OPTS="${JAVA_OPTS:-} \
  -Dserver.ssl.enabled=true \
  -Dserver.ssl.key-store=/tls/keystore.p12 \
  -Dserver.ssl.key-store-password=$(cat /secrets/tls_keystore_password) \
  -Dserver.ssl.key-store-type=PKCS12 \
  -Dserver.ssl.trust-store=/tls/truststore.p12 \
  -Dserver.ssl.trust-store-password=$(cat /secrets/tls_truststore_password) \
  -Dserver.ssl.trust-store-type=PKCS12 \
  -Dserver.port=8443 \
  -Djavax.net.ssl.trustStore=/tls/truststore.p12 \
  -Djavax.net.ssl.trustStorePassword=$(cat /secrets/tls_truststore_password) \
  -Djavax.net.ssl.trustStoreType=PKCS12"

########################################
# 7. START MIDPOINT
########################################

echo "starting midPoint (background)..."

/opt/midpoint/bin/midpoint.sh container &
MIDPOINT_PID=$!

echo "waiting for midPoint health..."
until curl -k -s https://localhost:8443/midpoint/actuator/health | grep -q "UP"; do
  sleep 5
done

echo "midPoint is UP"

BOOTSTRAP_MARKER="/opt/midpoint/var/.bootstrap-done"
NEEDS_RESTART=false

if [ ! -f "$BOOTSTRAP_MARKER" ]; then
  echo "running bootstrap..."

  cd /opt/midpoint

  if [ -f /generated/020-security-policy-keycloak.xml ]; then
    echo "importing security policy..."
    bin/ninja.sh import --input /generated/020-security-policy-keycloak.xml --overwrite
    NEEDS_RESTART=true
  else
    echo "WARN: security policy file missing"
  fi

  if [ -f /generated/030-system-configuration-security-policy.xml ]; then
    echo "binding Keycloak security policy as global policy..."
    bin/ninja.sh import --input /generated/030-system-configuration-security-policy.xml --overwrite
    NEEDS_RESTART=true
  else
    echo "WARN: system configuration security policy file missing"
  fi

  if [ "$NEEDS_RESTART" = true ]; then
    echo "restarting midPoint so authentication policy is loaded..."
    kill "$MIDPOINT_PID"
    wait "$MIDPOINT_PID" || true

    /opt/midpoint/bin/midpoint.sh container &
    MIDPOINT_PID=$!
  fi

  touch "$BOOTSTRAP_MARKER"
else
  echo "bootstrap already done, skipping"
fi

wait "$MIDPOINT_PID"