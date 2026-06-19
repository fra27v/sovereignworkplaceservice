#!/usr/bin/env bash
set -euo pipefail

namespace="openbao-operator"
pod_name="openbao-global-0"
init_file="${HOME}/openbao-bootstrap/openbao-global/openbao-global-init.json"
audit_path="file/"
audit_file_path="/openbao/audit/audit.log"
vault_addr="https://127.0.0.1:8200"
vault_cacert="/openbao/tls/tls.crt"
bao_addr="${vault_addr}"
bao_cacert="${vault_cacert}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${namespace}" exec -i "${pod_name}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; export BAO_TOKEN VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "$@"
}

command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
[[ -f "${init_file}" ]] || fail "Missing init file: ${init_file}"

mode="$(file_mode "${init_file}")"
case "${mode}" in
  600|400) ;;
  *) fail "Init file permissions are too open (${mode}); expected 0600 or 0400: ${init_file}" ;;
esac

root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from init file."

echo "Checking Global OpenBao status."
status_output="$(token_exec "${root_token}" bao status -tls-skip-verify)"
printf '%s\n' "${status_output}"

if ! printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*true'; then
  fail "Global OpenBao is not initialized."
fi

if ! printf '%s\n' "${status_output}" | grep -q 'Sealed[[:space:]]*false'; then
  fail "Global OpenBao is sealed."
fi

echo "Checking declarative audit device registration."
audit_list_output="$(token_exec "${root_token}" bao audit list 2>&1)"
printf '%s\n' "${audit_list_output}"

if ! printf '%s\n' "${audit_list_output}" | awk '{print $1}' | grep -Fxq "${audit_path}"; then
  fail "File audit device is not registered at ${audit_path}."
fi

echo "Checking audit log file exists without printing contents."
token_exec "${root_token}" test -f "${audit_file_path}"

echo "Global OpenBao file audit device is registered and the audit log file exists."
echo "This script does not print or inspect audit log contents."
