#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
init_file=""
required_confirmation="I HAVE SECURED GLOBAL OPENBAO INIT MATERIAL"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

if [[ -f "${env_file}" ]]; then
  load_operator_plane_env "${env_file}" "true"
fi

[[ -n "${OPENBAO_BOOTSTRAP_INIT_FILE:-}" ]] || fail "OPENBAO_BOOTSTRAP_INIT_FILE must be set in operator-plane.env."
init_file="${OPENBAO_BOOTSTRAP_INIT_FILE}"

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
