#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"

env_file="${env_dir}/operator-plane.bootstrap-secrets.env"
dry_run="false"
overwrite="false"
kv_mount="operator-kv"

traefik_path="operator-plane/traefik/ovh-dns01"
artifacts_path="operator-plane/operator-artifacts/family-infra-01"
artifacts_config_path="operator-plane/operator-artifacts/family-infra-01-config"

usage() {
  cat <<EOF
Usage: $0 [--env-file <path>] [--dry-run] [--overwrite]

Import local vps-family-control bootstrap secret material into Global OpenBao KV.

Options:
  --env-file <path>  Env file to import. Defaults to:
                     ${env_file}
  --dry-run          Print target paths, key names, and existence only.
  --overwrite        Allow replacing existing OpenBao KV paths.
  --help             Show this help.

Safety:
  - Secret values are never printed.
  - Existing KV paths are not overwritten unless --overwrite is set.
  - The env file is bootstrap/import/recovery material only.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

is_mode_private() {
  local mode="$1"
  local group_perms="${mode: -2:1}"
  local other_perms="${mode: -1:1}"

  [[ "${group_perms}" = "0" && "${other_perms}" = "0" ]]
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || fail "Missing required variable in env file: ${name}"
}

path_exists() {
  local logical_path="$1"

  bao kv metadata get -mount="${kv_mount}" "${logical_path}" >/dev/null 2>&1
}

print_target() {
  local label="$1"
  local logical_path="$2"
  shift 2

  local exists="no"
  if path_exists "${logical_path}"; then
    exists="yes"
  fi

  echo "${label}:"
  echo "  mount: ${kv_mount}"
  echo "  logical path: ${logical_path}"
  echo "  exists: ${exists}"
  echo "  expected keys:"
  printf '    - %s\n' "$@"
}

write_json_path() {
  local label="$1"
  local logical_path="$2"
  local json_file="$3"

  if path_exists "${logical_path}" && [[ "${overwrite}" != "true" ]]; then
    fail "Refusing to overwrite existing KV path without --overwrite: ${kv_mount}/${logical_path}"
  fi

  echo "Writing ${label} to ${kv_mount}/${logical_path} without printing values."
  bao kv put -mount="${kv_mount}" "${logical_path}" @"${json_file}" >/dev/null
}

ensure_kv_mount() {
  if bao secrets list -format=json | jq -e --arg mount "${kv_mount}/" 'has($mount)' >/dev/null; then
    local type
    type="$(bao secrets list -format=json | jq -r --arg mount "${kv_mount}/" '.[$mount].type')"
    [[ "${type}" = "kv" ]] || fail "OpenBao mount ${kv_mount}/ exists but is type ${type}, expected kv."

    local version
    version="$(bao secrets list -format=json | jq -r --arg mount "${kv_mount}/" '.[$mount].options.version // ""')"
    [[ "${version}" = "2" ]] || fail "OpenBao mount ${kv_mount}/ is not KV v2."
    echo "OpenBao KV v2 mount ${kv_mount}/ already exists."
    return 0
  fi

  echo "Enabling OpenBao KV v2 mount ${kv_mount}/."
  bao secrets enable -path="${kv_mount}" -version=2 kv >/dev/null
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "Missing value for --env-file."
      env_file="$2"
      shift
      ;;
    --dry-run)
      dry_run="true"
      ;;
    --overwrite)
      overwrite="true"
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

require_command bao
require_command jq
require_command kubectl

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"

if [[ "${dry_run}" != "true" ]]; then
  mode="$(file_mode "${env_file}")"
  is_mode_private "${mode}" || fail "Env file permissions are too open (${mode}); expected 0600 or stricter: ${env_file}"
fi

set -a
# shellcheck source=/dev/null
source "${env_file}"
set +a

require_var OVH_ENDPOINT
require_var OVH_APPLICATION_KEY
require_var OVH_APPLICATION_SECRET
require_var OVH_CONSUMER_KEY
require_var OPERATOR_ARTIFACTS_FAMILY_INFRA_01_USERNAME
require_var OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN
require_var OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME
require_var OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES

if [[ "${dry_run}" = "true" ]]; then
  print_target "Traefik OVH DNS-01" "${traefik_path}" \
    OVH_ENDPOINT OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY
  print_target "operator-artifacts tenant access" "${artifacts_path}" \
    username token
  print_target "operator-artifacts runtime config" "${artifacts_config_path}" \
    OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES
  echo "DRY-RUN: no values were written."
  exit 0
fi

ensure_kv_mount

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

traefik_json="${tmp_dir}/traefik-ovh-dns01.json"
artifacts_json="${tmp_dir}/operator-artifacts-family-infra-01.json"
artifacts_config_json="${tmp_dir}/operator-artifacts-family-infra-01-config.json"

jq -n '{
  OVH_ENDPOINT: env.OVH_ENDPOINT,
  OVH_APPLICATION_KEY: env.OVH_APPLICATION_KEY,
  OVH_APPLICATION_SECRET: env.OVH_APPLICATION_SECRET,
  OVH_CONSUMER_KEY: env.OVH_CONSUMER_KEY
}' > "${traefik_json}"

jq -n '{
  username: env.OPERATOR_ARTIFACTS_FAMILY_INFRA_01_USERNAME,
  token: env.OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN
}' > "${artifacts_json}"

jq -n '{
  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME: env.OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME,
  OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES: env.OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES
}' > "${artifacts_config_json}"

chmod 0600 "${traefik_json}" "${artifacts_json}" "${artifacts_config_json}"

write_json_path "Traefik OVH DNS-01" "${traefik_path}" "${traefik_json}"
write_json_path "operator-artifacts tenant access" "${artifacts_path}" "${artifacts_json}"
write_json_path "operator-artifacts runtime config" "${artifacts_config_path}" "${artifacts_config_json}"

echo "Operator-plane bootstrap secrets were imported into OpenBao KV."
echo "Secret values were not printed."
