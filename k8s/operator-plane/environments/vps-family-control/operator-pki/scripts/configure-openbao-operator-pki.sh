#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_pki_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${operator_pki_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_example_file="${env_dir}/operator-plane.env.example"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
init_file=""
vault_addr="https://127.0.0.1:8200"
vault_cacert=""
vault_cacert_fallback=""
bao_addr="${vault_addr}"
dry_run="false"

required_env_keys=(
  OPERATOR_DOMAIN
  KUBERNETES_CLUSTER_DNS_SUFFIX
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_SERVICE_NAME
  OPENBAO_PKI_MOUNT
  OPENBAO_OPERATOR_CA_COMMON_NAME
  OPENBAO_OPERATOR_CA_TTL
  OPENBAO_OPERATOR_VAULT_ROLE
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
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Print the planned checks and changes without calling kubectl.
  --help            Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD_NAME}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; client_cacert="$3"; if [ -r "$2" ]; then client_cacert="$2"; fi; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

read_root_token() {
  init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"

  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  [[ -n "${root_token}" ]] || fail "Could not read root token from init file."
}

is_missing_operator_ca_error() {
  local output="$1"

  printf '%s\n' "${output}" | grep -Eiq \
    'No value found|missing|not found|404|no issuing certificate|no default issuer currently configured|no certificate|no ca certificate|certificate is nil'
}

print_operator_ca_metadata() {
  local label="$1"
  local ca_fingerprint ca_size_bytes

  ca_fingerprint="$(printf '%s\n' "${ca_certificate}" | sha256sum | awk '{print $1}')"
  ca_size_bytes="$(printf '%s\n' "${ca_certificate}" | wc -c | awk '{print $1}')"
  echo "${label}: sha256=${ca_fingerprint}, pem_bytes=${ca_size_bytes}"
}

print_operator_ca_command_error() {
  local purpose="$1"
  local exit_code="$2"

  echo "ERROR: could not check Operator CA." >&2
  echo "Command purpose: ${purpose}" >&2
  echo "PKI mount: ${OPENBAO_PKI_MOUNT}" >&2
  echo "Exit code: ${exit_code}" >&2
  echo "Raw OpenBao output was suppressed to avoid printing sensitive or environment-specific context." >&2
}

read_public_operator_ca_certificate() {
  local ca_read_output ca_read_exit_code

  set +e
  ca_read_output="$(token_exec "${root_token}" bao read -format=json "${OPENBAO_PKI_MOUNT}/cert/ca" 2>&1)"
  ca_read_exit_code="$?"
  set -e

  if [[ "${ca_read_exit_code}" -eq 0 ]] && printf '%s\n' "${ca_read_output}" | jq -e '.data.certificate // empty' >/dev/null; then
    ca_certificate="$(printf '%s\n' "${ca_read_output}" | jq -r '.data.certificate')"
    return 0
  fi

  if is_missing_operator_ca_error "${ca_read_output}"; then
    return 1
  fi

  print_operator_ca_command_error "read the public Operator CA certificate" "${ca_read_exit_code}"
  return 2
}

require_public_operator_ca_certificate() {
  local context="$1"
  local ca_read_status

  if read_public_operator_ca_certificate; then
    return 0
  fi

  ca_read_status="$?"
  if [[ "${ca_read_status}" -eq 1 ]]; then
    fail "Public Operator CA certificate is missing at mount ${OPENBAO_PKI_MOUNT} after ${context}."
  fi

  exit "${ca_read_status}"
}

generate_operator_ca() {
  echo "Generating internal Operator CA. The CA private key will remain inside OpenBao."
  token_exec "${root_token}" bao write -format=json "${OPENBAO_PKI_MOUNT}/root/generate/internal" \
    "common_name=${OPENBAO_OPERATOR_CA_COMMON_NAME}" \
    "ttl=${OPENBAO_OPERATOR_CA_TTL}" >/dev/null
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
  operator-vault common name: derived from OPERATOR_DOMAIN
  operator-vault DNS SANs: derived from OpenBao service identity
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
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

if [[ "${dry_run}" == "false" ]]; then
  require_command kubectl
  require_command sha256sum
  [[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
else
  if [[ ! -f "${env_file}" ]]; then
    env_file="${env_example_file}"
    echo "DRY-RUN: using sanitized central example env file because the real env file is missing."
  fi
fi

if [[ "${dry_run}" == "true" && "${env_file}" == "${env_example_file}" ]]; then
  load_operator_plane_env "${env_file}" "false" "${required_env_keys[@]}"
else
  load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
fi
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"
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
# For an empty PKI mount, OpenBao returns "no default issuer currently
# configured" when reading cert/ca. That is expected before root generation and
# should trigger CA generation, not fail the first run.
if read_public_operator_ca_certificate; then
  echo "Operator CA already exists; leaving existing CA unchanged."
  print_operator_ca_metadata "Existing Operator CA safe metadata"
else
  ca_status="$?"
  if [[ "${ca_status}" -eq 1 ]]; then
    generate_operator_ca
    require_public_operator_ca_certificate "internal Operator CA generation"
    print_operator_ca_metadata "Generated Operator CA safe metadata"
  else
    exit "${ca_status}"
  fi
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
ensure_public_parent_traversable() {
  # Ensure parent directories are at least executable for others so unprivileged
  # verifiers can traverse into the public directory without exposing other
  # private content. Walk up a few ancestors conservatively and add o+x and
  # remove o+r/o+w where possible.
  local dir="$1"
  local parent
  parent="$(dirname -- "${dir}")"
  local i=0
  local max_levels=6
  while [[ "${parent}" != "/" && "${parent}" != "." && ${i} -lt ${max_levels} ]]; do
    if [[ -d "${parent}" ]]; then
      chmod o-rw "${parent}" 2>/dev/null || true
      chmod o+x "${parent}" 2>/dev/null || true
    fi
    parent="$(dirname -- "${parent}")"
    i=$((i+1))
  done
  # Ensure the public directory itself is readable/traversable
  chmod 0755 "${dir}" 2>/dev/null || true
}

ensure_public_parent_traversable "${OPERATOR_PKI_PUBLIC_DIR}"
ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
ca_checksum_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem.sha256"
printf '%s\n' "${ca_certificate}" > "${ca_bundle_path}"
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
