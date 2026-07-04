#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_pki_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${operator_pki_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
dry_run="false"
init_file=""
vault_addr="https://127.0.0.1:8200"
vault_cacert="/openbao/tls/tls.crt"
bao_addr="${vault_addr}"
bao_cacert="${vault_cacert}"
tmp_dir=""
target_tmp_files=()

required_env_keys=(
  OPERATOR_DOMAIN
  KUBERNETES_CLUSTER_DNS_SUFFIX
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_SERVICE_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
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
  rotate-operator-vault-tls-from-operator-pki.sh [--env-file <path>] [--dry-run]

Issues operator-vault runtime TLS from Operator PKI and installs it into the
Global OpenBao runtime TLS directory.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Print safe planned metadata without issuing or installing.
  --help            Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  local path

  for path in "${target_tmp_files[@]}"; do
    rm -f -- "${path}"
  done

  if [[ -n "${tmp_dir}" ]]; then
    rm -rf -- "${tmp_dir}"
  fi
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD_NAME}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "$@"
}

read_root_token() {
  init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  [[ -n "${root_token}" ]] || fail "Could not read root token from init file."
}

prepare_tmp_dir() {
  tmp_dir="$(mktemp -d)"
  chmod 0700 "${tmp_dir}"
  trap cleanup EXIT
}

derive_paths() {
  ca_bundle_source="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
  tls_key_path="${OPENBAO_TLS_DIR}/tls.key"
  tls_cert_path="${OPENBAO_TLS_DIR}/tls.crt"
  tls_ca_bundle_path="${OPENBAO_TLS_DIR}/operator-ca-bundle.pem"
  issue_path="${OPENBAO_PKI_MOUNT}/issue/${OPENBAO_OPERATOR_VAULT_ROLE}"
}

print_plan() {
  cat <<PLAN
operator-vault TLS rotation plan:
  PKI issue path: ${issue_path}
  Common name: ${OPENBAO_OPERATOR_VAULT_COMMON_NAME}
  DNS SANs: ${OPENBAO_OPERATOR_VAULT_ALT_NAMES}
  IP SANs: ${OPENBAO_OPERATOR_VAULT_IP_SANS}
  TTL: ${OPENBAO_OPERATOR_VAULT_TTL}
  Target TLS directory: ${OPENBAO_TLS_DIR}
  Operator CA bundle source: ${ca_bundle_source}
  Restart target: namespace=${OPENBAO_NAMESPACE}, pod=${OPENBAO_POD_NAME}
PLAN
}

issue_operator_vault_tls() {
  local issue_json cert_file key_file

  cert_file="${tmp_dir}/tls.crt"
  key_file="${tmp_dir}/tls.key"

  echo "Issuing operator-vault TLS leaf certificate without printing issuance material."
  issue_json="$(token_exec "${root_token}" bao write -format=json "${issue_path}" \
    "common_name=${OPENBAO_OPERATOR_VAULT_COMMON_NAME}" \
    "alt_names=${OPENBAO_OPERATOR_VAULT_ALT_NAMES}" \
    "ip_sans=${OPENBAO_OPERATOR_VAULT_IP_SANS}" \
    "ttl=${OPENBAO_OPERATOR_VAULT_TTL}")"

  printf '%s\n' "${issue_json}" | jq -r '.data.certificate // empty' > "${cert_file}"
  printf '%s\n' "${issue_json}" | jq -r '.data.private_key // empty' > "${key_file}"
  chmod 0600 "${cert_file}" "${key_file}"

  [[ -s "${cert_file}" ]] || fail "Issued certificate is empty."
  [[ -s "${key_file}" ]] || fail "Issued private key is empty."

  issued_cert_file="${cert_file}"
  issued_key_file="${key_file}"
}

validate_issued_tls() {
  local cert_pubkey_hash key_pubkey_hash

  [[ -s "${ca_bundle_source}" ]] || fail "Missing or empty Operator CA bundle: ${ca_bundle_source}"

  cert_pubkey_hash="$(openssl x509 -in "${issued_cert_file}" -pubkey -noout | sha256sum | awk '{print $1}')"
  key_pubkey_hash="$(openssl pkey -in "${issued_key_file}" -pubout | sha256sum | awk '{print $1}')"
  [[ "${cert_pubkey_hash}" == "${key_pubkey_hash}" ]] || fail "Issued certificate and private key do not match."

  openssl verify -CAfile "${ca_bundle_source}" "${issued_cert_file}" >/dev/null

  echo "Issued certificate safe metadata:"
  openssl x509 -in "${issued_cert_file}" -noout -subject -issuer -dates -fingerprint -sha256
  openssl x509 -in "${issued_cert_file}" -noout -ext subjectAltName || true
}

install_runtime_tls() {
  local key_tmp cert_tmp ca_tmp

  [[ -d "${OPENBAO_TLS_DIR}" ]] || fail "OpenBao TLS directory does not exist: ${OPENBAO_TLS_DIR}"

  key_tmp="${OPENBAO_TLS_DIR}/.operator-vault-tls.$$.tls.key"
  cert_tmp="${OPENBAO_TLS_DIR}/.operator-vault-tls.$$.tls.crt"
  ca_tmp="${OPENBAO_TLS_DIR}/.operator-vault-tls.$$.operator-ca-bundle.pem"
  target_tmp_files=("${key_tmp}" "${cert_tmp}" "${ca_tmp}")

  install -o root -g ubuntu -m 0440 "${issued_key_file}" "${key_tmp}"
  install -o root -g root -m 0444 "${issued_cert_file}" "${cert_tmp}"
  install -o root -g root -m 0444 "${ca_bundle_source}" "${ca_tmp}"

  mv -f -- "${cert_tmp}" "${tls_cert_path}"
  mv -f -- "${ca_tmp}" "${tls_ca_bundle_path}"
  mv -f -- "${key_tmp}" "${tls_key_path}"

  target_tmp_files=()

  chown root:ubuntu "${tls_key_path}"
  chmod 0440 "${tls_key_path}"
  chown root:root "${tls_cert_path}" "${tls_ca_bundle_path}"
  chmod 0444 "${tls_cert_path}" "${tls_ca_bundle_path}"

  echo "Installed runtime TLS files with safe permissions."
}

restart_openbao_pod() {
  echo "Restarting only ${OPENBAO_NAMESPACE}/${OPENBAO_POD_NAME}."
  kubectl -n "${OPENBAO_NAMESPACE}" delete pod "${OPENBAO_POD_NAME}"

  for _ in $(seq 1 60); do
    if kubectl -n "${OPENBAO_NAMESPACE}" get pod "${OPENBAO_POD_NAME}" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  kubectl -n "${OPENBAO_NAMESPACE}" wait --for=condition=Ready "pod/${OPENBAO_POD_NAME}" --timeout=180s
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
require_command openssl
require_command sha256sum
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

if [[ "${dry_run}" == "false" ]]; then
  require_command kubectl
  require_command install
  [[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
fi

load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
derive_paths
print_plan

if [[ "${dry_run}" == "true" ]]; then
  cat <<'DRYRUN'
DRY-RUN: would issue a TLS leaf certificate without printing or saving issuance JSON.
DRY-RUN: would validate the certificate, key, and CA chain.
DRY-RUN: would install tls.key, tls.crt, and operator-ca-bundle.pem.
DRY-RUN: would delete only the configured OpenBao pod and wait for Ready.
DRYRUN
  exit 0
fi

prepare_tmp_dir
read_root_token
issue_operator_vault_tls
validate_issued_tls
install_runtime_tls
restart_openbao_pod

echo "operator-vault runtime TLS was issued, installed, and OpenBao was restarted."
echo "No private key, token, issuance JSON, or secret value was printed."
