#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
dry_run="false"
tenant_name="family-infra-01"
target_tmp_files=()

required_env_keys=(
  OPERATOR_PKI_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PUBLIC_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  publish-operator-ca-bundle.sh [--env-file <path>] [--dry-run]

Publishes the public Operator CA bundle to operator-artifacts for
family-infra-01.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Print safe planned metadata without writing files.
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
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

file_size() {
  local path="$1"

  if stat -c '%s' "${path}" >/dev/null 2>&1; then
    stat -c '%s' "${path}"
  else
    stat -f '%z' "${path}"
  fi
}

derive_paths() {
  source_bundle="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
  source_checksum="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem.sha256"
  target_dir="${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants/${tenant_name}/trust"
  target_bundle="${target_dir}/operator-ca-bundle.pem"
  target_checksum="${target_dir}/operator-ca-bundle.pem.sha256"
}

validate_source() {
  [[ -s "${source_bundle}" ]] || fail "Missing or empty source Operator CA bundle: ${source_bundle}"
  [[ -s "${source_checksum}" ]] || fail "Missing or empty source checksum: ${source_checksum}"
  (
    cd "${OPERATOR_PKI_PUBLIC_DIR}"
    sha256sum -c operator-ca-bundle.pem.sha256 >/dev/null
  )
}

print_safe_metadata() {
  local label="$1"
  local bundle_path="$2"
  local checksum_path="$3"

  echo "${label}:"
  echo "  bundle: ${bundle_path}"
  echo "  checksum: ${checksum_path}"
  echo "  bytes: $(file_size "${bundle_path}")"
  echo "  sha256: $(cat "${checksum_path}")"
}

publish_bundle() {
  local bundle_tmp checksum_tmp

  install -d -o root -g root -m 0755 "${OPERATOR_ARTIFACTS_PUBLIC_DIR}"
  install -d -o root -g root -m 0755 "${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants"
  install -d -o root -g root -m 0755 "${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants/${tenant_name}"
  install -d -o root -g root -m 0755 "${target_dir}"

  bundle_tmp="${target_dir}/.operator-ca-bundle.$$.pem.tmp"
  checksum_tmp="${target_dir}/.operator-ca-bundle.$$.pem.sha256.tmp"
  target_tmp_files=("${bundle_tmp}" "${checksum_tmp}")
  trap cleanup EXIT

  install -o root -g root -m 0644 "${source_bundle}" "${bundle_tmp}"
  (
    cd "${target_dir}"
    sha256sum "$(basename -- "${bundle_tmp}")" | sed "s|$(basename -- "${bundle_tmp}")|operator-ca-bundle.pem|" > "${checksum_tmp}"
  )
  chmod 0644 "${checksum_tmp}"

  mv -f -- "${bundle_tmp}" "${target_bundle}"
  mv -f -- "${checksum_tmp}" "${target_checksum}"
  target_tmp_files=()

  chmod 0644 "${target_bundle}" "${target_checksum}"
}

verify_target() {
  [[ -s "${target_bundle}" ]] || fail "Missing or empty target Operator CA bundle: ${target_bundle}"
  [[ -s "${target_checksum}" ]] || fail "Missing or empty target checksum: ${target_checksum}"
  (
    cd "${target_dir}"
    sha256sum -c operator-ca-bundle.pem.sha256 >/dev/null
  )
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

require_command sha256sum
require_command install
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
derive_paths
validate_source

print_safe_metadata "Source Operator CA bundle" "${source_bundle}" "${source_checksum}"
echo "Target bundle: ${target_bundle}"
echo "Target checksum: ${target_checksum}"

if [[ "${dry_run}" == "true" ]]; then
  echo "DRY-RUN: would publish public Operator CA bundle to operator-artifacts."
  exit 0
fi

publish_bundle
verify_target
print_safe_metadata "Published Operator CA bundle" "${target_bundle}" "${target_checksum}"

echo "Operator CA bundle artifact was published without printing certificate contents."
