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
      [ -s /tls/truststore.p12 ];
do
  sleep 2
done

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
  -Dserver.port=8443"

########################################
# 7. START MIDPOINT
########################################

echo "starting midPoint..."

exec /opt/midpoint/bin/midpoint.sh container