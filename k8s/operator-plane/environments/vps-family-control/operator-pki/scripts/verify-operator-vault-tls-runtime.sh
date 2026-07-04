#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_pki_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${operator_pki_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

required_env_keys=(
  OPERATOR_DOMAIN
  KUBERNETES_CLUSTER_DNS_SUFFIX
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_SERVICE_NAME
  OPENBAO_PKI_MOUNT
  OPENBAO_OPERATOR_VAULT_ROLE
  OPENBAO_OPERATOR_VAULT_IP_SANS
  OPENBAO_OPERATOR_VAULT_TTL
  OPERATOR_PKI_PUBLIC_DIR
  OPENBAO_TLS_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-vault-tls-runtime.sh [--env-file <path>]

Verifies operator-vault runtime TLS files and the configured OpenBao pod
without printing private keys or certificate PEM.

Options:
  --env-file <path>  Path to operator-plane.env.
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

warn() {
  echo "WARN: $*" >&2
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

file_owner_group() {
  local path="$1"

  if stat -c '%U:%G' "${path}" >/dev/null 2>&1; then
    stat -c '%U:%G' "${path}"
  else
    stat -f '%Su:%Sg' "${path}"
  fi
}

expect_file_metadata() {
  local path="$1"
  local expected_owner_group="$2"
  local expected_mode="$3"
  local actual_owner_group actual_mode

  [[ -s "${path}" ]] || fail "Missing or empty file: ${path}"
  actual_owner_group="$(file_owner_group "${path}")"
  actual_mode="$(file_mode "${path}")"
  [[ "${actual_owner_group}" == "${expected_owner_group}" ]] || fail "Unexpected owner/group for ${path}: ${actual_owner_group}, expected ${expected_owner_group}"
  [[ "${actual_mode}" == "${expected_mode}" ]] || fail "Unexpected mode for ${path}: ${actual_mode}, expected ${expected_mode}"
  ok "metadata matches for ${path}"
}

verify_cert_key_match() {
  local cert_pubkey_hash key_pubkey_hash

  cert_pubkey_hash="$(openssl x509 -in "${tls_cert_path}" -pubkey -noout | sha256sum | awk '{print $1}')"
  key_pubkey_hash="$(openssl pkey -in "${tls_key_path}" -pubout | sha256sum | awk '{print $1}')"
  [[ "${cert_pubkey_hash}" == "${key_pubkey_hash}" ]] || fail "Runtime TLS certificate and private key do not match."
  ok "runtime TLS certificate and private key match"
}

verify_certificate() {
  openssl verify -CAfile "${tls_ca_bundle_path}" "${tls_cert_path}" >/dev/null
  ok "runtime TLS certificate verifies against Operator CA bundle"

  echo "Runtime TLS certificate safe metadata:"
  openssl x509 -in "${tls_cert_path}" -noout -subject -issuer -dates -fingerprint -sha256
  openssl x509 -in "${tls_cert_path}" -noout -ext subjectAltName || true
}

verify_openbao_pod() {
  local pod_phase pod_ready

  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl is unavailable; skipping OpenBao pod checks"
    return 0
  fi

  pod_phase="$(kubectl -n "${OPENBAO_NAMESPACE}" get pod "${OPENBAO_POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${pod_phase}" == "Running" ]] || fail "OpenBao pod is not Running: ${OPENBAO_NAMESPACE}/${OPENBAO_POD_NAME}"

  pod_ready="$(kubectl -n "${OPENBAO_NAMESPACE}" get pod "${OPENBAO_POD_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "${pod_ready}" == "True" ]] || fail "OpenBao pod is not Ready: ${OPENBAO_NAMESPACE}/${OPENBAO_POD_NAME}"
  ok "OpenBao pod is Running and Ready"

  if kubectl -n "${OPENBAO_NAMESPACE}" exec "${OPENBAO_POD_NAME}" -- \
    sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_CACERT=/openbao/tls/operator-ca-bundle.pem BAO_ADDR=https://127.0.0.1:8200 BAO_CACERT=/openbao/tls/operator-ca-bundle.pem bao status >/dev/null'; then
    ok "OpenBao health check succeeds with the installed Operator CA bundle"
  else
    warn "OpenBao health check with installed Operator CA bundle did not pass"
  fi
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

require_command openssl
require_command sha256sum
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

tls_key_path="${OPENBAO_TLS_DIR}/tls.key"
tls_cert_path="${OPENBAO_TLS_DIR}/tls.crt"
tls_ca_bundle_path="${OPENBAO_TLS_DIR}/operator-ca-bundle.pem"

expect_file_metadata "${tls_key_path}" "root:ubuntu" "440"
expect_file_metadata "${tls_cert_path}" "root:root" "444"
expect_file_metadata "${tls_ca_bundle_path}" "root:root" "444"
verify_cert_key_match
verify_certificate
verify_openbao_pod

echo "operator-vault runtime TLS verification completed without printing private key material."
