#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_secret_sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${operator_secret_sync_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

dry_run="false"
namespace="operator-secret-sync"
configmap_name="openbao-ca-bundle"
configmap_key="ca.crt"

required_env_keys=(
  OPERATOR_PKI_PUBLIC_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  install-openbao-ca-bundle-configmap.sh [--env-file <path>] [--dry-run] [--help]

Projects the public Operator CA bundle from operator-artifacts into the
operator-secret-sync namespace as a ConfigMap that operator-secret-sync pods
can mount to verify OpenBao TLS.

This is a public trust material projection only. The ConfigMap is created in
operator-secret-sync namespace and does not contain secret data.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Show what would be applied without creating resources.
  --help             Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

ok() {
  echo "OK: $*"
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

validate_source_file() {
  local path="$1"

  [[ -f "${path}" ]] || fail "Source file does not exist: ${path}"
  [[ -s "${path}" ]] || fail "Source file is empty: ${path}"
}

validate_source_checksum() {
  local path="$1"
  local checksum_file="${path}.sha256"

  if [[ ! -f "${checksum_file}" ]]; then
    return 0
  fi

  local expected_checksum actual_checksum

  expected_checksum="$(cut -d' ' -f1 "${checksum_file}")"
  actual_checksum="$(sha256sum "${path}" | cut -d' ' -f1)"

  [[ "${expected_checksum}" = "${actual_checksum}" ]] || \
    fail "Checksum mismatch for ${path}. Expected: ${expected_checksum}, Got: ${actual_checksum}"
}

get_file_bytes() {
  local path="$1"
  stat -f%z "${path}" 2>/dev/null || stat -c%s "${path}" 2>/dev/null || {
    wc -c < "${path}" | tr -d ' '
  }
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

require_command bash
require_command kubectl
require_command sha256sum

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"

validate_source_file "${ca_bundle_path}"
validate_source_checksum "${ca_bundle_path}"

source_bytes="$(get_file_bytes "${ca_bundle_path}")"
source_sha256="$(sha256sum "${ca_bundle_path}" | cut -d' ' -f1)"

ok "Source path: ${ca_bundle_path}"
ok "Source bytes: ${source_bytes}"
ok "Source SHA256: ${source_sha256}"
ok "Namespace: ${namespace}"
ok "ConfigMap name: ${configmap_name}"
ok "ConfigMap key: ${configmap_key}"

if [[ "${dry_run}" = "true" ]]; then
  echo
  echo "DRY-RUN: Would create namespace and ConfigMap as follows:"
  echo "  kubectl create namespace ${namespace} --dry-run=client -o yaml"
  echo "  kubectl create configmap -n ${namespace} ${configmap_name} --from-file=${configmap_key}=${ca_bundle_path} --dry-run=client -o yaml | kubectl apply -f -"
  exit 0
fi

echo
echo "Creating namespace if missing..."
kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating/updating ConfigMap..."
kubectl create configmap -n "${namespace}" "${configmap_name}" \
  --from-file="${configmap_key}=${ca_bundle_path}" \
  --dry-run=client -o yaml | kubectl apply -f -

ok "ConfigMap installed: ${namespace}/${configmap_name}"
