#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
tenant_name="family-infra-01"

required_env_keys=(
  OPERATOR_ARTIFACTS_PUBLIC_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-ca-bundle-artifact.sh [--env-file <path>]

Verifies the published public Operator CA bundle artifact without printing PEM
contents.

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

file_size() {
  local path="$1"

  if stat -c '%s' "${path}" >/dev/null 2>&1; then
    stat -c '%s' "${path}"
  else
    stat -f '%z' "${path}"
  fi
}

check_public_file_mode() {
  local path="$1"
  local mode mode_value

  mode="$(file_mode "${path}")"
  mode_value=$((8#${mode}))
  (( (mode_value & 004) != 0 )) || fail "File is not public-readable: ${path}"
  (( (mode_value & 022) == 0 )) || fail "File is writable by group or other: ${path}"
}

derive_paths() {
  target_dir="${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants/${tenant_name}/trust"
  target_bundle="${target_dir}/operator-ca-bundle.pem"
  target_checksum="${target_dir}/operator-ca-bundle.pem.sha256"
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

require_command sha256sum
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
derive_paths

[[ -s "${target_bundle}" ]] || fail "Missing or empty Operator CA bundle artifact: ${target_bundle}"
[[ -s "${target_checksum}" ]] || fail "Missing or empty Operator CA checksum artifact: ${target_checksum}"
check_public_file_mode "${target_bundle}"
check_public_file_mode "${target_checksum}"
(
  cd "${target_dir}"
  sha256sum -c operator-ca-bundle.pem.sha256 >/dev/null
)

ok "Operator CA bundle artifact checksum validates"
echo "Target bundle: ${target_bundle}"
echo "Target checksum: ${target_checksum}"
echo "Bundle bytes: $(file_size "${target_bundle}")"
echo "SHA256: $(cat "${target_checksum}")"
echo "Operator CA bundle artifact verification completed without printing certificate contents."
