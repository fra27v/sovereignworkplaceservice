#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"
env_file="${env_dir}/operator-pki.env"
init_file="${HOME}/openbao-bootstrap/openbao-global/openbao-global-init.json"
vault_addr="https://127.0.0.1:8200"
vault_cacert="/openbao/tls/tls.crt"
bao_addr="${vault_addr}"
bao_cacert="${vault_cacert}"

required_env_keys=(
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_PKI_MOUNT
  OPENBAO_OPERATOR_CA_COMMON_NAME
  OPENBAO_OPERATOR_CA_TTL
  OPENBAO_OPERATOR_VAULT_ROLE
  OPENBAO_OPERATOR_VAULT_COMMON_NAME
  OPENBAO_OPERATOR_VAULT_ALT_NAMES
  OPENBAO_OPERATOR_VAULT_IP_SANS
  OPENBAO_OPERATOR_VAULT_TTL
  OPERATOR_PKI_PUBLIC_DIR
  OPENBAO_TLS_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-openbao-operator-pki.sh [--env-file <path>]

Verifies the vps-family-control Operator PKI foundation without changing
OpenBao state and without printing certificate, token, or private key material.

Options:
  --env-file <path>  Path to operator-pki.env.
  --help            Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

ok() {
  echo "OK: $*"
}

file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

validate_env_key() {
  local key="$1"
  local allowed

  for allowed in "${required_env_keys[@]}"; do
    [[ "${key}" == "${allowed}" ]] && return 0
  done

  fail "Unknown key in env file: ${key}"
}

load_env_file() {
  local path="$1"
  local line key value seen_keys
  declare -A seen_keys=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" != *"="* ]] && fail "Invalid env line without '=': ${line}"
    [[ "${line}" =~ ^[[:space:]]*export[[:space:]]+ ]] && fail "Do not use export in ${path}."
    [[ "${line}" == *'$('* || "${line}" == *'`'* ]] && fail "Command substitution is not allowed in ${path}."

    key="${line%%=*}"
    value="${line#*=}"
    [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || fail "Invalid env key: ${key}"
    validate_env_key "${key}"
    [[ -z "${seen_keys[${key}]+x}" ]] || fail "Duplicate env key: ${key}"
    seen_keys["${key}"]=1
    printf -v "${key}" '%s' "${value}"
  done < "${path}"

  for key in "${required_env_keys[@]}"; do
    [[ -n "${!key:-}" ]] || fail "Missing or empty required env key: ${key}"
  done
}

check_private_file_permissions() {
  local path="$1"
  local mode mode_value

  mode="$(file_mode "${path}")"
  mode_value=$((8#${mode}))
  if (( (mode_value & 077) != 0 || (mode_value & 100) != 0 )); then
    fail "File permissions are too open (${mode}); expected 0600 or 0400: ${path}"
  fi
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD_NAME}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "$@"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command jq
require_command kubectl
require_command sha256sum

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
check_private_file_permissions "${env_file}"
load_env_file "${env_file}"

[[ -f "${init_file}" ]] || fail "Missing init file: ${init_file}"
check_private_file_permissions "${init_file}"
root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from init file."

echo "Verifying Operator PKI foundation."

secrets_output="$(token_exec "${root_token}" bao secrets list -format=json)"
if printf '%s\n' "${secrets_output}" | jq -e --arg mount "${OPENBAO_PKI_MOUNT}/" 'has($mount)' >/dev/null; then
  ok "PKI mount exists at ${OPENBAO_PKI_MOUNT}/"
else
  fail "PKI mount is missing at ${OPENBAO_PKI_MOUNT}/"
fi

ca_metadata="$(token_exec "${root_token}" bao read -format=json "${OPENBAO_PKI_MOUNT}/cert/ca")"
if printf '%s\n' "${ca_metadata}" | jq -e '.data.certificate // empty' >/dev/null; then
  ok "Operator CA certificate exists"
else
  fail "Operator CA certificate is missing or empty"
fi

role_metadata="$(token_exec "${root_token}" bao read -format=json "${OPENBAO_PKI_MOUNT}/roles/${OPENBAO_OPERATOR_VAULT_ROLE}")"
if printf '%s\n' "${role_metadata}" | jq -e '.data // empty' >/dev/null; then
  ok "operator-vault role exists"
else
  fail "operator-vault role is missing"
fi

ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
ca_checksum_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem.sha256"
[[ -s "${ca_bundle_path}" ]] || fail "Public CA bundle is missing or empty: ${ca_bundle_path}"
ok "Public CA bundle exists"

[[ -s "${ca_checksum_path}" ]] || fail "Public CA bundle checksum is missing or empty: ${ca_checksum_path}"
(
  cd "${OPERATOR_PKI_PUBLIC_DIR}"
  sha256sum -c operator-ca-bundle.pem.sha256 >/dev/null
)
ok "Public CA bundle checksum validates"

echo "Operator PKI verification completed without printing certificate, token, or private key material."
