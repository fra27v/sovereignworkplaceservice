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
dry_run="false"

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
  configure-openbao-operator-pki.sh [--env-file <path>] [--dry-run]

Configures the vps-family-control Operator PKI foundation in Global OpenBao.

Options:
  --env-file <path>  Path to operator-pki.env.
  --dry-run          Print the planned checks and changes without calling kubectl.
  --help            Show this help.
USAGE
}

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

read_root_token() {
  [[ -f "${init_file}" ]] || fail "Missing init file: ${init_file}"
  check_private_file_permissions "${init_file}"

  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  [[ -n "${root_token}" ]] || fail "Could not read root token from init file."
}

print_plan() {
  cat <<PLAN
Operator PKI configuration plan:
  OpenBao namespace: ${OPENBAO_NAMESPACE}
  OpenBao pod: ${OPENBAO_POD_NAME}
  PKI mount: ${OPENBAO_PKI_MOUNT}
  Operator CA common name: ${OPENBAO_OPERATOR_CA_COMMON_NAME}
  Operator CA TTL: ${OPENBAO_OPERATOR_CA_TTL}
  operator-vault role: ${OPENBAO_OPERATOR_VAULT_ROLE}
  operator-vault common name: ${OPENBAO_OPERATOR_VAULT_COMMON_NAME}
  operator-vault DNS SANs: ${OPENBAO_OPERATOR_VAULT_ALT_NAMES}
  operator-vault IP SANs: ${OPENBAO_OPERATOR_VAULT_IP_SANS}
  operator-vault max TTL: ${OPENBAO_OPERATOR_VAULT_TTL}
  Public CA bundle directory: ${OPERATOR_PKI_PUBLIC_DIR}
  Future OpenBao TLS directory: ${OPENBAO_TLS_DIR}
PLAN
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
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

if [[ "${dry_run}" == "false" ]]; then
  require_command kubectl
  require_command sha256sum
  [[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
  check_private_file_permissions "${env_file}"
else
  if [[ ! -f "${env_file}" ]]; then
    env_file="${env_dir}/operator-pki.env.example"
    echo "DRY-RUN: using sanitized example env file because the real env file is missing."
  fi
fi

load_env_file "${env_file}"
print_plan

if [[ "${dry_run}" == "true" ]]; then
  cat <<'DRYRUN'
DRY-RUN: would read the local OpenBao init file without printing token material.
DRY-RUN: would verify or enable the OpenBao PKI secrets engine.
DRY-RUN: would tune the PKI max TTL.
DRY-RUN: would generate the internal Operator CA only if it is missing.
DRY-RUN: would create or update the operator-vault issuance role.
DRY-RUN: would export only the public CA bundle and checksum.
DRYRUN
  exit 0
fi

read_root_token

echo "Checking Operator PKI secrets engine."
secrets_output="$(token_exec "${root_token}" bao secrets list -format=json)"
if printf '%s\n' "${secrets_output}" | jq -e --arg mount "${OPENBAO_PKI_MOUNT}/" 'has($mount)' >/dev/null; then
  echo "Operator PKI secrets engine is already enabled at ${OPENBAO_PKI_MOUNT}/."
else
  echo "Enabling Operator PKI secrets engine at ${OPENBAO_PKI_MOUNT}/."
  token_exec "${root_token}" bao secrets enable -path="${OPENBAO_PKI_MOUNT}" pki >/dev/null
fi

echo "Tuning Operator PKI max TTL."
token_exec "${root_token}" bao secrets tune -max-lease-ttl="${OPENBAO_OPERATOR_CA_TTL}" "${OPENBAO_PKI_MOUNT}" >/dev/null

echo "Checking Operator CA."
set +e
ca_read_output="$(token_exec "${root_token}" bao read -format=json "${OPENBAO_PKI_MOUNT}/cert/ca" 2>&1)"
ca_read_exit_code="$?"
set -e

if [[ "${ca_read_exit_code}" -eq 0 ]] && printf '%s\n' "${ca_read_output}" | jq -e '.data.certificate // empty' >/dev/null; then
  ca_certificate="$(printf '%s\n' "${ca_read_output}" | jq -r '.data.certificate')"
  ca_fingerprint="$(printf '%s\n' "${ca_certificate}" | sha256sum | awk '{print $1}')"
  ca_size_bytes="$(printf '%s\n' "${ca_certificate}" | wc -c | awk '{print $1}')"
  echo "Operator CA already exists; leaving existing CA unchanged."
  echo "Existing Operator CA safe metadata: sha256=${ca_fingerprint}, pem_bytes=${ca_size_bytes}"
elif printf '%s\n' "${ca_read_output}" | grep -Eiq 'No value found|missing|not found|404'; then
  echo "Generating internal Operator CA. The CA private key will remain inside OpenBao."
  token_exec "${root_token}" bao write -format=json "${OPENBAO_PKI_MOUNT}/root/generate/internal" \
    "common_name=${OPENBAO_OPERATOR_CA_COMMON_NAME}" \
    "ttl=${OPENBAO_OPERATOR_CA_TTL}" >/dev/null
else
  echo "ERROR: could not check Operator CA." >&2
  exit "${ca_read_exit_code}"
fi

echo "Creating or updating operator-vault issuance role."
token_exec "${root_token}" bao write "${OPENBAO_PKI_MOUNT}/roles/${OPENBAO_OPERATOR_VAULT_ROLE}" \
  "allowed_domains=${OPENBAO_OPERATOR_VAULT_ALT_NAMES}" \
  allow_bare_domains=true \
  allow_subdomains=false \
  allow_localhost=true \
  allow_ip_sans=true \
  server_flag=true \
  client_flag=false \
  "max_ttl=${OPENBAO_OPERATOR_VAULT_TTL}" >/dev/null

echo "Exporting public Operator CA bundle."
mkdir -p "${OPERATOR_PKI_PUBLIC_DIR}"
chmod 0755 "${OPERATOR_PKI_PUBLIC_DIR}"
ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
ca_checksum_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem.sha256"
token_exec "${root_token}" bao read -field=certificate "${OPENBAO_PKI_MOUNT}/cert/ca" > "${ca_bundle_path}"
[[ -s "${ca_bundle_path}" ]] || fail "Public CA bundle was not written or is empty: ${ca_bundle_path}"
chmod 0644 "${ca_bundle_path}"
(
  cd "${OPERATOR_PKI_PUBLIC_DIR}"
  sha256sum operator-ca-bundle.pem > operator-ca-bundle.pem.sha256
)
chmod 0644 "${ca_checksum_path}"

echo "Operator PKI foundation is configured."
echo "Public CA bundle: ${ca_bundle_path}"
echo "Public CA bundle checksum: ${ca_checksum_path}"
echo "No CA private key, leaf private key, token, or issuance JSON was exported."
