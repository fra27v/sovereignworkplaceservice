#!/usr/bin/env bash
set -euo pipefail

init_file="${HOME}/openbao-bootstrap/openbao-global/openbao-global-init.json"
required_confirmation="I HAVE SECURED GLOBAL OPENBAO INIT MATERIAL"

echo "This script retires only the local Global OpenBao init JSON:"
echo "${init_file}"
echo
echo "WARNING: the init JSON contains the initial root token and recovery material."
echo "WARNING: before deleting it locally, the operator must have saved it in a secure external location."
echo
echo "This script never touches these runtime files:"
echo "/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key"
echo "/var/lib/sovereignworkplaceservice/openbao/tls/tls.key"
echo "/var/lib/sovereignworkplaceservice/openbao/tls/tls.crt"
echo

if [[ ! -e "${init_file}" ]]; then
  echo "Init JSON does not exist locally; nothing to retire."
  exit 0
fi

echo "Type this exact confirmation to delete the local init JSON:"
echo "${required_confirmation}"
read -r confirmation

if [[ "${confirmation}" != "${required_confirmation}" ]]; then
  echo "Confirmation did not match exactly. Refusing to delete anything." >&2
  exit 1
fi

echo "Safe metadata for the file selected for deletion:"
ls -l "${init_file}"
echo "Path: ${init_file}"

# Secure deletion is not guaranteed on SSDs, copy-on-write filesystems, or cloud
# volumes. The real controls are secure custody, encrypted storage, and deleting
# unnecessary local copies.
rm -f "${init_file}"

if [[ -e "${init_file}" ]]; then
  echo "ERROR: init JSON still exists after deletion attempt: ${init_file}" >&2
  exit 1
fi

echo "Local Global OpenBao init JSON was deleted."
echo "Reminder: the static seal key is still required for runtime auto-unseal and disaster recovery."
