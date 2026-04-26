#!/bin/sh
set -eu

until [ -s /secrets/tls.crt ] && \
      [ -s /secrets/tls.key ] && \
      [ -s /secrets/ca.crt ] && \
      [ -s /secrets/admin_username ] && \
      [ -s /secrets/admin_password ]; do
  echo "waiting for Vault Agent secrets..."
  sleep 2
done

export username="$(cat /secrets/admin_username)"
export password="$(cat /secrets/admin_password)"

exec /start-collabora-online.sh