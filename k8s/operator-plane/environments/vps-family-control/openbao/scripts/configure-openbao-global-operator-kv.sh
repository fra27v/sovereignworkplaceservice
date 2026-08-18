#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

namespace="openbao-operator"
pod_name="openbao-global-0"
kv_mount="operator-kv"
vault_addr="https://127.0.0.1:8200"
bao_addr="${vault_addr}"
vault_cacert=""
dry_run="false"

required_env_keys=(
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
  OPENBAO_TLS_DIR
)

usage() {
  cat <<EOF
Usage: $0 [--env-file <path>] [--dry-run] [--help]

Configure the Global OpenBao operator-plane KV v2 mount.

Options:
  --env-file <path>  Path to operator-plane.env.
                     Defaults to:
                     ${env_file}
  --dry-run          Print planned checks and changes without mutating OpenBao.
  --help             Show this help.

Safety:
  - Uses the bao CLI inside the configured Global OpenBao pod.
  - Uses the Operator CA bundle inside the pod for OpenBao client trust.
  - Reads the bootstrap/admin token from OPENBAO_BOOTSTRAP_INIT_FILE.
  - Does not print OpenBao tokens or secret values.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${namespace}" exec -i "${pod_name}" -- \
    sh -c '
      IFS= read -r BAO_TOKEN
      [ -r "$2" ] || {
        echo "ERROR: OpenBao Operator CA bundle is missing or unreadable inside the pod: $2" >&2
        exit 1
      }
      export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$2"
      shift 3
      "$@"
    ' sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "$@"
}

ensure_openbao_pod_ready() {
  local phase ready

  kubectl -n "${namespace}" get pod "${pod_name}" >/dev/null 2>&1 \
    || fail "Global OpenBao pod is missing: ${namespace}/${pod_name}"

  phase="$(kubectl -n "${namespace}" get pod "${pod_name}" -o jsonpath='{.status.phase}')"
  [[ "${phase}" = "Running" ]] \
    || fail "Global OpenBao pod is not Running: ${namespace}/${pod_name} phase=${phase}"

  ready="$(kubectl -n "${namespace}" get pod "${pod_name}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')"
  [[ "${ready}" = "True" ]] \
    || fail "Global OpenBao pod is not Ready: ${namespace}/${pod_name}"
}

ensure_openbao_unsealed() {
  local status_output

  status_output="$(token_exec "${root_token}" bao status)" \
    || fail "Could not run bao status inside ${namespace}/${pod_name}. Global OpenBao may be sealed or unreachable."

  if ! printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*true'; then
    fail "Global OpenBao is not initialized."
  fi

  if ! printf '%s\n' "${status_output}" | grep -q 'Sealed[[:space:]]*false'; then
    fail "Global OpenBao is sealed."
  fi
}

configure_operator_kv() {
  local secrets_json type version

  secrets_json="$(token_exec "${root_token}" bao secrets list -format=json)" \
    || fail "Could not list OpenBao secrets engines."

  if printf '%s\n' "${secrets_json}" | jq -e --arg mount "${kv_mount}/" 'has($mount)' >/dev/null; then
    type="$(printf '%s\n' "${secrets_json}" | jq -r --arg mount "${kv_mount}/" '.[$mount].type')"
    version="$(printf '%s\n' "${secrets_json}" | jq -r --arg mount "${kv_mount}/" '.[$mount].options.version // ""')"

    [[ "${type}" = "kv" ]] || fail "OpenBao mount ${kv_mount}/ exists but is type ${type}, expected kv-v2."
    [[ "${version}" = "2" ]] || fail "OpenBao mount ${kv_mount}/ is KV version ${version:-unset}, expected kv-v2."
    echo "OK: OpenBao KV v2 mount ${kv_mount}/ already exists."
    return 0
  fi

  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would enable OpenBao KV v2 mount ${kv_mount}/."
    return 0
  fi

  echo "Enabling OpenBao KV v2 mount ${kv_mount}/."
  token_exec "${root_token}" bao secrets enable -path="${kv_mount}" -version=2 kv >/dev/null
  echo "OK: OpenBao KV v2 mount ${kv_mount}/ is enabled."
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
    --help|-h)
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

[[ -s "${env_loader}" ]] || fail "Missing operator-plane env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
if [[ "${dry_run}" = "true" ]]; then
  load_operator_plane_env "${env_file}" "false" "${required_env_keys[@]}"
else
  load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
fi

namespace="${OPENBAO_NAMESPACE}"
pod_name="${OPENBAO_POD_NAME}"
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"

init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from OpenBao bootstrap init file."

ensure_openbao_pod_ready
ensure_openbao_unsealed
configure_operator_kv

echo "OpenBao operator-plane KV bootstrap completed without printing tokens or secret values."
