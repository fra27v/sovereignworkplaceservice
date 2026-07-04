#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
namespace="openbao-operator"
pod_name="openbao-global-0"
init_file=""
bootstrap_dir=""
vault_addr="https://127.0.0.1:8200"
vault_cacert="/openbao/tls/tls.crt"
bao_addr="${vault_addr}"
bao_cacert="${vault_cacert}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

bao_exec() {
  kubectl -n "${namespace}" exec "${pod_name}" -- \
    sh -c 'export VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "$@"
}

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" OPENBAO_BOOTSTRAP_INIT_FILE
init_file="${OPENBAO_BOOTSTRAP_INIT_FILE}"
bootstrap_dir="$(dirname -- "${init_file}")"

mkdir -p "${bootstrap_dir}"
chmod 0700 "${bootstrap_dir}"

if [[ -e "${init_file}" ]]; then
  fail "Refusing to continue because init file already exists: ${init_file}"
fi

echo "Checking Global OpenBao initialization status."
status_output="$(
  set +e
  bao_exec bao status 2>&1
  status_code="$?"
  set -e
  printf '\n__BAO_STATUS_EXIT_CODE__=%s\n' "${status_code}"
)"

bao_status_exit_code="$(printf '%s\n' "${status_output}" | awk -F= '/^__BAO_STATUS_EXIT_CODE__=/{print $2}')"
status_body="$(printf '%s\n' "${status_output}" | sed '/^__BAO_STATUS_EXIT_CODE__=/d')"

if [[ -z "${bao_status_exit_code}" ]]; then
  fail "Could not determine bao status exit code."
fi

if printf '%s\n' "${status_body}" | grep -q 'Initialized[[:space:]]*true'; then
  fail "Global OpenBao is already initialized. No init file was written."
fi

if ! printf '%s\n' "${status_body}" | grep -q 'Initialized[[:space:]]*false'; then
  echo "bao status output did not contain the expected uninitialized state." >&2
  echo "Safe status output follows; it must not contain init JSON:" >&2
  printf '%s\n' "${status_body}" >&2
  exit 1
fi

echo "Global OpenBao is not initialized. Initializing now."
bao_exec bao operator init -format=json > "${init_file}"
chmod 0600 "${init_file}"

if [[ ! -s "${init_file}" ]]; then
  fail "Init file was not written or is empty: ${init_file}"
fi

echo "Initialization output was written to: ${init_file}"
echo "WARNING: this file contains the root token and recovery material."
echo "Never commit it, paste it into chat, or print it in logs."

echo "Final Global OpenBao status:"
bao_exec bao status
