#!/bin/sh
set -eu

echo "[nextcloud-entrypoint] waiting for Vault Agent secrets..."
until [ -s /secrets/db_name ] &&
      [ -s /secrets/db_username ] &&
      [ -s /secrets/db_password ] &&
      [ -s /secrets/admin_username ] &&
      [ -s /secrets/admin_password ] &&
      [ -s /secrets/redis_password ]; do
  sleep 2
done

echo "[nextcloud-entrypoint] enabling apache ssl modules..."
a2enmod ssl headers rewrite remoteip >/dev/null 2>&1 || true
a2ensite default-ssl >/dev/null 2>&1 || true

echo "[nextcloud-entrypoint] updating CA trust..."
update-ca-certificates >/dev/null 2>&1 || true

if [ -f /bootstrap/zz-custom.config.php ]; then
  echo "[nextcloud-entrypoint] installing custom nextcloud config..."
  cp /bootstrap/zz-custom.config.php /var/www/html/config/zz-custom.config.php
  chown www-data:root /var/www/html/config/zz-custom.config.php
  chmod 640 /var/www/html/config/zz-custom.config.php
fi

echo "[nextcloud-entrypoint] handing off to upstream entrypoint..."
exec /entrypoint.sh apache2-foreground