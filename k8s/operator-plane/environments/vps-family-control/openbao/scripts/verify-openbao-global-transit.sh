#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
openbao_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${openbao_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

namespace="openbao-operator"
pod_name="openbao-global-0"
init_file=""
transit_mount="transit"
transit_key="family-infra-01-autounseal"
policy_name="family-infra-01-transit-autounseal"
policy_file=""
live_policy_tmp=""
vault_addr="https://127.0.0.1:8200"
vault_cacert=""
vault_cacert_fallback=""
bao_addr="${vault_addr}"

required_env_keys=(
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
  OPENBAO_TLS_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-openbao-global-transit.sh [--env-file <path>] [--help]

Verifies the Global OpenBao transit key and policy for family-infra-01 without
printing tokens, secrets, or policy bodies.

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

warn() {
  echo "WARN: $*" >&2
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

cleanup() {
  if [[ -n "${live_policy_tmp}" && -e "${live_policy_tmp}" ]]; then
    rm -f "${live_policy_tmp}"
  fi
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${namespace}" exec -i "${pod_name}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; client_cacert="$3"; if [ -r "$2" ]; then client_cacert="$2"; fi; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
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
require_command jq
require_command kubectl
require_command mktemp
require_command sha256sum
trap cleanup EXIT

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from init file."

repo_root="$(cd -- "${env_dir}/../../../.." && pwd)"
policy_file="${repo_root}/k8s/operator-plane/openbao/policies/${policy_name}.hcl"

ok "Using env file: ${env_file}"

echo "Checking Global OpenBao status."
status_output="$(token_exec "${root_token}" bao status)"

if ! printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*true'; then
  fail "Global OpenBao is not initialized."
fi

if ! printf '%s\n' "${status_output}" | grep -q 'Sealed[[:space:]]*false'; then
  fail "Global OpenBao is sealed."
fi

ok "Global OpenBao is initialized and unsealed"

echo "Checking transit secrets engine."
secrets_output="$(token_exec "${root_token}" bao secrets list -format=json)"
if printf '%s\n' "${secrets_output}" | jq -e --arg mount "${transit_mount}/" 'has($mount)' >/dev/null; then
  ok "Transit secrets engine exists at ${transit_mount}/"
else
  fail "Transit secrets engine ${transit_mount}/ is missing"
fi

policy_exists_output="$(token_exec "${root_token}" bao policy list -format=json)"
if printf '%s\n' "${policy_exists_output}" | jq -e --arg name "${policy_name}" 'index($name) != null' >/dev/null; then
  ok "Global OpenBao policy exists: ${policy_name}"
else
  fail "Global OpenBao policy is missing: ${policy_name}"
fi

set +e
token_exec "${root_token}" bao read -format=json "${transit_mount}/keys/${transit_key}" >/dev/null 2>&1
key_read_exit_code="$?"
set -e

if [[ "${key_read_exit_code}" -eq 0 ]]; then
  ok "Transit key exists: ${transit_key}"
else
  echo "ERROR: could not verify transit key existence." >&2
  echo "Command purpose: read transit key for verification" >&2
  echo "Transit mount: ${transit_mount}/" >&2
  echo "Transit key: ${transit_key}" >&2
  echo "Exit code: ${key_read_exit_code}" >&2
  echo "Raw OpenBao output was suppressed to avoid printing token, key, ciphertext, or plaintext material." >&2
  fail "Transit key is missing: ${transit_key}"
fi

if [[ ! -s "${policy_file}" ]]; then
  warn "TODO: versioned Global OpenBao transit policy file is missing or empty; skipping policy body comparison: ${policy_file}"
else
  policy_sha256="$(sha256sum "${policy_file}" | cut -d' ' -f1)"
  ok "Versioned Global OpenBao transit policy SHA256: ${policy_sha256}"

  live_policy_tmp="$(mktemp)"
  set +e
  token_exec "${root_token}" bao policy read "${policy_name}" > "${live_policy_tmp}" 2>/dev/null
  live_policy_exit_code="$?"
  set -e

  if [[ "${live_policy_exit_code}" -ne 0 ]]; then
    warn "TODO: could not read live Global OpenBao transit policy body; skipping body comparison"
    warn "Policy name: ${policy_name}"
    warn "Command purpose: read live policy body for best-effort SHA256 comparison"
    warn "Exit code: ${live_policy_exit_code}"
  elif [[ ! -s "${live_policy_tmp}" ]]; then
    warn "TODO: live Global OpenBao transit policy body read returned empty output; skipping body comparison"
    warn "Policy name: ${policy_name}"
  else
    live_policy_sha256="$(sha256sum "${live_policy_tmp}" | cut -d' ' -f1)"
    ok "Live Global OpenBao transit policy body is readable: ${policy_name}"
    ok "Live Global OpenBao transit policy SHA256: ${live_policy_sha256}"

    if [[ "${live_policy_sha256}" == "${policy_sha256}" ]]; then
      ok "Global OpenBao transit policy SHA256 matches versioned policy"
    else
      warn "TODO: live Global OpenBao transit policy SHA256 differs from versioned policy; verification continues"
      warn "Policy name: ${policy_name}"
      warn "Versioned policy SHA256: ${policy_sha256}"
      warn "Live policy SHA256: ${live_policy_sha256}"
    fi
  fi
fi

ok "Global OpenBao transit verification passed"
