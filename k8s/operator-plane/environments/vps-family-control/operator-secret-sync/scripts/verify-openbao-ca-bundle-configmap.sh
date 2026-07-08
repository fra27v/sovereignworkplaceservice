#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_secret_sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${operator_secret_sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

namespace="operator-secret-sync"
configmap_name="openbao-ca-bundle"
configmap_key="ca.crt"

required_env_keys=(
  OPERATOR_PKI_PUBLIC_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-openbao-ca-bundle-configmap.sh [--env-file <path>] [--help]

Verifies the operator-secret-sync namespace ConfigMap projection of the public
Operator CA bundle without printing certificate contents.

This verification is read-only and checks:
  - Namespace exists
  - ConfigMap exists
  - ConfigMap key exists and is non-empty
  - ConfigMap content SHA256 matches the source file

Options:
  --env-file <path>  Path to operator-plane.env.
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

kubectl_safe() {
  kubectl "$@" 2>/dev/null
}

get_configmap_sha256() {
  local ns="$1"
  local cm="$2"
  local key="$3"
  local template

  template="{{ index .data \"${key}\" }}"
  kubectl -n "${ns}" get configmap "${cm}" -o "go-template=${template}" | sha256sum | cut -d' ' -f1
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

require_command bash
require_command kubectl
require_command sha256sum

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"

ok "Namespace: ${namespace}"
ok "ConfigMap name: ${configmap_name}"
ok "ConfigMap key: ${configmap_key}"
ok "Source path: ${ca_bundle_path}"

if ! kubectl_safe get namespace "${namespace}" >/dev/null; then
  fail "Namespace ${namespace} does not exist"
fi

ok "Namespace exists"

if ! kubectl_safe -n "${namespace}" get configmap "${configmap_name}" >/dev/null; then
  fail "ConfigMap ${namespace}/${configmap_name} does not exist"
fi

ok "ConfigMap exists"

configmap_content="$(kubectl -n "${namespace}" get configmap "${configmap_name}" -o "go-template={{ index .data \"${configmap_key}\" }}" 2>/dev/null || echo "")"
[[ -n "${configmap_content}" ]] || fail "ConfigMap key ${configmap_key} is empty or missing"

ok "ConfigMap key is non-empty"

[[ -f "${ca_bundle_path}" ]] || fail "Source CA bundle missing: ${ca_bundle_path}"
[[ -s "${ca_bundle_path}" ]] || fail "Source CA bundle is empty: ${ca_bundle_path}"

source_sha256="$(sha256sum "${ca_bundle_path}" | cut -d' ' -f1)"
configmap_sha256="$(get_configmap_sha256 "${namespace}" "${configmap_name}" "${configmap_key}")"

if [[ "${source_sha256}" != "${configmap_sha256}" ]]; then
  fail "ConfigMap CA bundle SHA256 mismatch. Expected: ${source_sha256}, Got: ${configmap_sha256}"
fi

ok "ConfigMap CA bundle SHA256 matches source"
ok "ConfigMap verification passed"
