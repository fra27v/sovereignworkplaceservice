#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
namespace="openbao-operator"
pod_name="openbao-global-0"
init_file=""
tenant_name="family-infra-01"
transit_mount="transit"
transit_key="family-infra-01-autounseal"
policy_name="family-infra-01-transit-autounseal"
policy_file="${repo_root}/k8s/operator-plane/openbao/policies/family-infra-01-transit-autounseal.hcl"
token_file=""
token_period="720h"
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

token_exec_with_policy_file() {
  local token="$1"
  local policy_path="$2"
  shift 2

  {
    printf '%s\n' "${token}"
    cat "${policy_path}"
  } | kubectl -n "${namespace}" exec -i "${pod_name}" -- \
    sh -c '
      IFS= read -r BAO_TOKEN
      client_cacert="$3"
      if [ -r "$2" ]; then
        client_cacert="$2"
      fi
      export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"
      shift 4
      policy_file="$(mktemp)"
      trap "rm -f \"${policy_file}\"" EXIT
      cat > "${policy_file}"
      bao policy write "$1" "${policy_file}" >/dev/null
    ' sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
command -v base64 >/dev/null 2>&1 || fail "Missing required command: base64"
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

if [[ -f "${env_file}" ]]; then
  load_operator_plane_env "${env_file}" "true"
fi
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
token_file="$(dirname -- "${init_file}")/family-infra-01-transit-token.json"
[[ -s "${policy_file}" ]] || fail "Missing or empty policy file: ${policy_file}"
[[ ! -e "${token_file}" ]] || fail "Refusing to overwrite existing tenant token file: ${token_file}"

root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from init file."

echo "Checking Global OpenBao status."
status_output="$(token_exec "${root_token}" bao status)"
printf '%s\n' "${status_output}"

if ! printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*true'; then
  fail "Global OpenBao is not initialized."
fi

if ! printf '%s\n' "${status_output}" | grep -q 'Sealed[[:space:]]*false'; then
  fail "Global OpenBao is sealed."
fi

echo "Verifying file audit is enabled before transit bootstrap."
audit_list_output="$(token_exec "${root_token}" bao audit list 2>&1)"
if ! printf '%s\n' "${audit_list_output}" | awk '{print $1}' | grep -Fxq "file/"; then
  fail "File audit device is not registered. Enable and verify audit before transit bootstrap."
fi

echo "Checking transit secrets engine."
secrets_output="$(token_exec "${root_token}" bao secrets list -format=json)"
if printf '%s\n' "${secrets_output}" | jq -e --arg mount "${transit_mount}/" 'has($mount)' >/dev/null; then
  echo "Transit secrets engine is already enabled at ${transit_mount}/."
else
  echo "Enabling transit secrets engine at ${transit_mount}/."
  token_exec "${root_token}" bao secrets enable -path="${transit_mount}" transit >/dev/null
fi

echo "Checking transit key for tenant ${tenant_name}."
set +e
key_read_output="$(token_exec "${root_token}" bao read "${transit_mount}/keys/${transit_key}" 2>&1)"
key_read_exit_code="$?"
set -e

if [[ "${key_read_exit_code}" -eq 0 ]]; then
  echo "Transit key already exists."
elif printf '%s\n' "${key_read_output}" | grep -Fq "No value found"; then
  echo "Creating transit key for tenant ${tenant_name}."
  token_exec "${root_token}" bao write -f "${transit_mount}/keys/${transit_key}" >/dev/null
else
  echo "ERROR: could not check transit key." >&2
  printf '%s\n' "${key_read_output}" >&2
  exit "${key_read_exit_code}"
fi

echo "Creating or updating minimal tenant transit policy from versioned HCL."
token_exec_with_policy_file "${root_token}" "${policy_file}" "${policy_name}"

echo "Creating orphan periodic tenant token and writing JSON output to local bootstrap file."
token_exec "${root_token}" bao token create \
  -format=json \
  -orphan \
  -period="${token_period}" \
  -policy="${policy_name}" \
  -display-name="${tenant_name}-openbao-autounseal" \
  > "${token_file}"
chmod 0600 "${token_file}"

[[ -s "${token_file}" ]] || fail "Tenant token file was not written or is empty: ${token_file}"

tenant_token="$(jq -r '.auth.client_token // empty' "${token_file}")"
[[ -n "${tenant_token}" ]] || fail "Could not read tenant token from token file."

echo "Running transit encrypt/decrypt smoke test without printing token or ciphertext."
smoke_plaintext="family-infra-01-autounseal-smoke-test"
smoke_plaintext_b64="$(printf '%s' "${smoke_plaintext}" | base64 | tr -d '\n')"
encrypt_output="$(token_exec "${tenant_token}" bao write -format=json "${transit_mount}/encrypt/${transit_key}" "plaintext=${smoke_plaintext_b64}")"
ciphertext="$(printf '%s\n' "${encrypt_output}" | jq -r '.data.ciphertext // empty')"
[[ -n "${ciphertext}" ]] || fail "Transit encrypt smoke test did not return ciphertext."

decrypt_output="$(token_exec "${tenant_token}" bao write -format=json "${transit_mount}/decrypt/${transit_key}" "ciphertext=${ciphertext}")"
decrypted_b64="$(printf '%s\n' "${decrypt_output}" | jq -r '.data.plaintext // empty')"
[[ -n "${decrypted_b64}" ]] || fail "Transit decrypt smoke test did not return plaintext."

decrypted_plaintext="$(printf '%s' "${decrypted_b64}" | base64 -d)"
[[ "${decrypted_plaintext}" = "${smoke_plaintext}" ]] || fail "Transit smoke test decrypted value did not match expected test value."

echo "Transit autounseal material for ${tenant_name} is configured."
echo "Tenant token JSON was written to: ${token_file}"
echo "WARNING: the tenant token file contains secret material. Do not print it, paste it into chat, or commit it."
echo "This script does not install Tenant OpenBao."
