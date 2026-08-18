#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
parser_lib="${script_dir}/lib/bootstrap-secrets-parser.sh"
artifacts_env_helper="${env_dir}/operator-artifacts/scripts/lib/load-operator-artifacts-config.sh"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

operator_env_file="${env_dir}/operator-plane.env"
env_file="${env_dir}/operator-plane.bootstrap-secrets.env"
dry_run="false"
overwrite="false"
kv_mount="operator-kv"
openbao_namespace="openbao-operator"
openbao_pod_name="openbao-global-0"
vault_addr="https://127.0.0.1:8200"
vault_cacert=""
vault_cacert_fallback=""
bao_addr="${vault_addr}"

traefik_path="operator-plane/traefik/ovh-dns01"
artifacts_path="operator-plane/operator-artifacts/family-infra-01"
artifacts_config_path="operator-plane/operator-artifacts/family-infra-01-config"

required_operator_env_keys=(
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
  OPENBAO_TLS_DIR
)

usage() {
  cat <<EOF
Usage: $0 [--env-file <path>] [--operator-env-file <path>] [--dry-run] [--overwrite]

Import local vps-family-control bootstrap secret material into Global OpenBao KV.

Options:
  --env-file <path>  Env file to import. Defaults to:
                     ${env_file}
  --operator-env-file <path>
                     Central operator-plane.env file for non-secret runtime config.
                     Defaults to:
                     ${operator_env_file}
  --dry-run          Print target paths, key names, and existence only.
  --overwrite        Allow replacing existing OpenBao KV paths.
  --help             Show this help.

Safety:
  - Secret values are never printed.
  - Generated BasicAuth hashes and users lines are never printed.
  - Existing KV paths are not overwritten unless --overwrite is set.
  - The env file is bootstrap/import/recovery material only.
  - operator-artifacts token is local import material only; OpenBao runtime KV
    stores the final users key.
  - operator-artifacts hostname and allowed source ranges are read from
    operator-plane.env, not from the bootstrap secrets file.
  - operator-artifacts username is derived from OPERATOR_ARTIFACTS_TENANT_NAME
    in operator-plane.env.
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

path_exists() {
  local logical_path="$1"

  token_exec "${root_token}" bao kv metadata get -mount="${kv_mount}" "${logical_path}" >/dev/null 2>&1
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
  token_exec_with_json_file "${root_token}" "${json_file}" bao kv put -mount="${kv_mount}" "${logical_path}"
}

ensure_kv_mount() {
  local secrets_json type version

  secrets_json="$(token_exec "${root_token}" bao secrets list -format=json)" \
    || fail "Could not list OpenBao secrets engines. Global OpenBao may be sealed or unreachable."

  if printf '%s\n' "${secrets_json}" | jq -e --arg mount "${kv_mount}/" 'has($mount)' >/dev/null; then
    type="$(printf '%s\n' "${secrets_json}" | jq -r --arg mount "${kv_mount}/" '.[$mount].type')"
    [[ "${type}" = "kv" ]] || fail "OpenBao mount ${kv_mount}/ exists but is type ${type}, expected kv."

    version="$(printf '%s\n' "${secrets_json}" | jq -r --arg mount "${kv_mount}/" '.[$mount].options.version // ""')"
    [[ "${version}" = "2" ]] || fail "OpenBao mount ${kv_mount}/ is not KV v2."
    echo "OpenBao KV v2 mount ${kv_mount}/ already exists."
    return 0
  fi

  fail "OpenBao KV v2 mount is missing: ${kv_mount}/. Run: bootstrap-operator-plane.sh --openbao-operator-kv"
}

ensure_targets_writable() {
  local logical_path

  if [[ "${overwrite}" = "true" ]]; then
    return 0
  fi

  for logical_path in "${traefik_path}" "${artifacts_path}" "${artifacts_config_path}"; do
    if path_exists "${logical_path}"; then
      fail "Refusing to overwrite existing KV path without --overwrite: ${kv_mount}/${logical_path}"
    fi
  done
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${openbao_namespace}" exec -i "${openbao_pod_name}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; client_cacert="$3"; if [ -r "$2" ]; then client_cacert="$2"; fi; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

token_exec_with_json_file() {
  local token="$1"
  local json_file="$2"
  shift 2

  {
    printf '%s\n' "${token}"
    cat "${json_file}"
  } | kubectl -n "${openbao_namespace}" exec -i "${openbao_pod_name}" -- \
    sh -c '
      IFS= read -r BAO_TOKEN
      client_cacert="$3"
      if [ -r "$2" ]; then
        client_cacert="$2"
      fi
      export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"
      shift 4
      json_file="$(mktemp)"
      chmod 0600 "${json_file}"
      trap "rm -f \"${json_file}\"" EXIT
      cat > "${json_file}"
      "$@" @"${json_file}" >/dev/null
    ' sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

ensure_openbao_pod_ready() {
  local phase ready

  kubectl -n "${openbao_namespace}" get pod "${openbao_pod_name}" >/dev/null 2>&1 \
    || fail "Global OpenBao pod is missing: ${openbao_namespace}/${openbao_pod_name}"

  phase="$(kubectl -n "${openbao_namespace}" get pod "${openbao_pod_name}" -o jsonpath='{.status.phase}')"
  [[ "${phase}" = "Running" ]] \
    || fail "Global OpenBao pod is not Running: ${openbao_namespace}/${openbao_pod_name} phase=${phase}"

  ready="$(kubectl -n "${openbao_namespace}" get pod "${openbao_pod_name}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')"
  [[ "${ready}" = "True" ]] \
    || fail "Global OpenBao pod is not Ready: ${openbao_namespace}/${openbao_pod_name}"
}

ensure_openbao_unsealed() {
  local status_output

  status_output="$(token_exec "${root_token}" bao status)" \
    || fail "Could not run bao status inside ${openbao_namespace}/${openbao_pod_name}. Global OpenBao may be sealed or unreachable."

  if ! printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*true'; then
    fail "Global OpenBao is not initialized."
  fi

  if ! printf '%s\n' "${status_output}" | grep -q 'Sealed[[:space:]]*false'; then
    fail "Global OpenBao is sealed."
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "Missing value for --env-file."
      env_file="$2"
      shift
      ;;
    --operator-env-file)
      [[ "$#" -ge 2 ]] || fail "Missing value for --operator-env-file."
      operator_env_file="$2"
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

require_command kubectl
require_command jq
require_command grep
if [[ "${dry_run}" != "true" ]]; then
  require_command openssl
fi

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
[[ -s "${parser_lib}" ]] || fail "Missing parser library: ${parser_lib}"
[[ -f "${operator_env_file}" ]] || fail "Missing central operator-plane env file: ${operator_env_file}"
[[ -s "${artifacts_env_helper}" ]] || fail "Missing operator-artifacts config helper: ${artifacts_env_helper}"
[[ -s "${env_loader}" ]] || fail "Missing operator-plane env loader: ${env_loader}"

if [[ "${dry_run}" != "true" ]]; then
  mode="$(file_mode "${env_file}")"
  is_mode_private "${mode}" || fail "Env file permissions are too open (${mode}); expected 0600 or stricter: ${env_file}"
  operator_mode="$(file_mode "${operator_env_file}")"
  is_mode_private "${operator_mode}" || fail "Operator env file permissions are too open (${operator_mode}); expected 0600 or stricter: ${operator_env_file}"
fi

# shellcheck source=lib/bootstrap-secrets-parser.sh
source "${parser_lib}"
parse_bootstrap_secrets_file "${env_file}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
if [[ "${dry_run}" = "true" ]]; then
  load_operator_plane_env "${operator_env_file}" "false" "${required_operator_env_keys[@]}"
else
  load_operator_plane_env "${operator_env_file}" "true" "${required_operator_env_keys[@]}"
fi
# shellcheck source=../../operator-artifacts/scripts/lib/load-operator-artifacts-config.sh
source "${artifacts_env_helper}"
if [[ "${dry_run}" = "true" ]]; then
  load_operator_artifacts_env "${operator_env_file}" "false"
else
  load_operator_artifacts_env "${operator_env_file}" "true"
fi
openbao_namespace="${OPENBAO_NAMESPACE}"
openbao_pod_name="${OPENBAO_POD_NAME}"
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from OpenBao bootstrap init file."

ensure_openbao_pod_ready
ensure_openbao_unsealed
ensure_kv_mount

if [[ "${dry_run}" = "true" ]]; then
  echo "Env file: ${env_file}"
  echo "Central operator env file: ${operator_env_file}"
  echo "Accepted key names:"
  printf '  - %s\n' "${BOOTSTRAP_SECRET_ACCEPTED_KEYS[@]}"
  print_target "Traefik OVH DNS-01" "${traefik_path}" \
    OVH_ENDPOINT OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY
  print_target "operator-artifacts BasicAuth runtime projection" "${artifacts_path}" \
    users
  echo "  users present/generated: yes"
  print_target "operator-artifacts runtime config" "${artifacts_config_path}" \
    OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES
  echo "DRY-RUN: no values were written."
  exit 0
fi

ensure_targets_writable

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

traefik_json="${tmp_dir}/traefik-ovh-dns01.json"
artifacts_json="${tmp_dir}/operator-artifacts-family-infra-01.json"
artifacts_config_json="${tmp_dir}/operator-artifacts-family-infra-01-config.json"
artifacts_username="${OPERATOR_ARTIFACTS_AUTH_USERNAME}"
artifacts_token="${BOOTSTRAP_SECRETS[OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN]}"
artifacts_hash="$(printf '%s' "${artifacts_token}" | openssl passwd -apr1 -stdin)"
artifacts_users="${artifacts_username}:${artifacts_hash}"
unset artifacts_token artifacts_hash

export OVH_ENDPOINT="${BOOTSTRAP_SECRETS[OVH_ENDPOINT]}"
export OVH_APPLICATION_KEY="${BOOTSTRAP_SECRETS[OVH_APPLICATION_KEY]}"
export OVH_APPLICATION_SECRET="${BOOTSTRAP_SECRETS[OVH_APPLICATION_SECRET]}"
export OVH_CONSUMER_KEY="${BOOTSTRAP_SECRETS[OVH_CONSUMER_KEY]}"
export OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME
export OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES

jq -n '{
  OVH_ENDPOINT: env.OVH_ENDPOINT,
  OVH_APPLICATION_KEY: env.OVH_APPLICATION_KEY,
  OVH_APPLICATION_SECRET: env.OVH_APPLICATION_SECRET,
  OVH_CONSUMER_KEY: env.OVH_CONSUMER_KEY
}' > "${traefik_json}"

jq -n --arg users "${artifacts_users}" '{
  users: $users
}' > "${artifacts_json}"
unset artifacts_users artifacts_username

jq -n '{
  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME: env.OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME,
  OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES: env.OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES
}' > "${artifacts_config_json}"

chmod 0600 "${traefik_json}" "${artifacts_json}" "${artifacts_config_json}"

write_json_path "Traefik OVH DNS-01" "${traefik_path}" "${traefik_json}"
write_json_path "operator-artifacts BasicAuth runtime projection" "${artifacts_path}" "${artifacts_json}"
write_json_path "operator-artifacts runtime config" "${artifacts_config_path}" "${artifacts_config_json}"

echo "Operator-plane bootstrap secrets were imported into OpenBao KV."
echo "Secret values, generated hashes, and htpasswd users contents were not printed."
