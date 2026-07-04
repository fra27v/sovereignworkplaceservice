#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
namespace="openbao-operator"
pod_name="openbao-global-0"
init_file=""
audit_path="file/"
audit_file_path="/openbao/audit/audit.log"
vault_addr="https://127.0.0.1:8200"
vault_cacert=""
vault_cacert_fallback=""
bao_addr="${vault_addr}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${namespace}" exec -i "${pod_name}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; client_cacert="$3"; if [ -r "$2" ]; then client_cacert="$2"; fi; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

if [[ -f "${env_file}" ]]; then
  load_operator_plane_env "${env_file}" "true"
fi
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"

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
