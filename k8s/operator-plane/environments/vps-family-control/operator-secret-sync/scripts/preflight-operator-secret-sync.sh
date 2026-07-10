#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
lock_file="${env_dir}/dependencies.lock.json"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
image_lib="${script_dir}/lib/resolve-runner-image.sh"

namespace="operator-secret-sync"
service_account_name="operator-plane-secret-sync"
runtime_image_id="operator-secret-sync-runner-candidate"
auth_path="kubernetes"
openbao_role_name="operator-plane-secret-sync"
openbao_policy_name="operator-plane-secret-sync"
openbao_namespace="openbao-operator"
openbao_pod_name="openbao-global-0"
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
  preflight-operator-secret-sync.sh [--env-file <path>] [--lock-file <path>] [--help]

Verifies the operator-secret-sync real Job prerequisites without printing
Secret data, OpenBao tokens, OpenBao init material, PEM contents, plaintext,
ciphertext, htpasswd contents, generated hashes, or issuance JSON.

Options:
  --env-file <path>   Path to operator-plane.env.
  --lock-file <path>  Path to dependencies.lock.json.
  --help              Show this help.
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
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

kubectl_json() {
  kubectl "$@" -o json 2>/dev/null
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${openbao_namespace}" exec -i "${openbao_pod_name}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; client_cacert="$3"; if [ -r "$2" ]; then client_cacert="$2"; fi; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$client_cacert" BAO_ADDR="$4" BAO_CACERT="$client_cacert"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${vault_cacert_fallback}" "${bao_addr}" "$@"
}

check_resource() {
  local label="$1"
  shift

  if kubectl "$@" >/dev/null 2>&1; then
    ok "${label} exists"
  else
    fail "${label} is missing"
  fi
}

check_configmap_key() {
  local cm_name="$1"
  local key="$2"
  local non_empty

  check_resource "ConfigMap ${namespace}/${cm_name}" -n "${namespace}" get configmap "${cm_name}"
  non_empty="$(kubectl_json -n "${namespace}" get configmap "${cm_name}" \
    | jq -r --arg key "${key}" 'if (((.data // {})[$key] // "") != "") then "yes" else "no" end')"
  echo "ConfigMap ${namespace}/${cm_name} key ${key}: non-empty ${non_empty}"
  [[ "${non_empty}" = "yes" ]] || fail "ConfigMap ${namespace}/${cm_name} key ${key} is missing or empty"
}

check_can_i_for_secret() {
  local target_namespace="$1"
  local secret_name="$2"
  local verb allowed
  local subject="system:serviceaccount:${namespace}:${service_account_name}"

  for verb in get update patch; do
    allowed="$(kubectl auth can-i "${verb}" "secret/${secret_name}" -n "${target_namespace}" --as="${subject}" 2>/dev/null || true)"
    echo "RBAC ${subject} can ${verb} ${target_namespace}/${secret_name}: ${allowed}"
    [[ "${allowed}" = "yes" ]] || fail "RBAC is missing ${verb} for Secret ${target_namespace}/${secret_name}"
  done

  if kubectl -n "${target_namespace}" get secret "${secret_name}" >/dev/null 2>&1; then
    ok "Target Secret ${target_namespace}/${secret_name} already exists for resource-name-scoped apply"
    return 0
  fi

  allowed="$(kubectl auth can-i create secrets -n "${target_namespace}" --as="${subject}" 2>/dev/null || true)"
  echo "RBAC ${subject} can create secrets in ${target_namespace}: ${allowed}"
  [[ "${allowed}" = "yes" ]] || fail "Target Secret ${target_namespace}/${secret_name} is missing and RBAC does not grant create; pre-create the expected Secret or intentionally update RBAC"
}

check_openbao_auth() {
  local root_token auth_list role_json role_sa_names role_sa_namespaces role_policies init_file

  init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  [[ -n "${root_token}" ]] || fail "Could not read root token from init file for OpenBao metadata checks"

  auth_list="$(token_exec "${root_token}" bao auth list -format=json)"
  if printf '%s\n' "${auth_list}" | jq -e --arg path "${auth_path}/" 'has($path)' >/dev/null; then
    ok "OpenBao Kubernetes auth method exists at ${auth_path}/"
  else
    fail "OpenBao Kubernetes auth method is missing at ${auth_path}/"
  fi

  token_exec "${root_token}" bao policy read "${openbao_policy_name}" >/dev/null \
    || fail "OpenBao policy is missing: ${openbao_policy_name}"
  ok "OpenBao policy exists: ${openbao_policy_name}"

  role_json="$(token_exec "${root_token}" bao read -format=json "auth/${auth_path}/role/${openbao_role_name}")"
  role_sa_names="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_names[]?')"
  role_sa_namespaces="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_namespaces[]?')"
  role_policies="$(printf '%s\n' "${role_json}" | jq -r '.data.policies[]?')"

  printf '%s\n' "${role_sa_names}" | grep -Fxq "${service_account_name}" \
    || fail "OpenBao auth role is not bound to ServiceAccount ${service_account_name}"
  printf '%s\n' "${role_sa_namespaces}" | grep -Fxq "${namespace}" \
    || fail "OpenBao auth role is not bound to namespace ${namespace}"
  printf '%s\n' "${role_policies}" | grep -Fxq "${openbao_policy_name}" \
    || fail "OpenBao auth role does not attach policy ${openbao_policy_name}"
  ok "OpenBao Kubernetes auth role metadata is valid"
}

check_kv_path() {
  local root_token="$1"
  local logical_path="$2"
  shift 2
  local required_keys=("$@")
  local response key present non_empty

  response="$(token_exec "${root_token}" bao read -format=json "operator-kv/data/${logical_path}")" \
    || fail "OpenBao KV path is missing or unreadable: operator-kv/${logical_path}"

  echo "OpenBao KV path checked: operator-kv/${logical_path}"
  for key in "${required_keys[@]}"; do
    present="$(printf '%s\n' "${response}" | jq -r --arg key "${key}" 'if ((.data.data // {}) | has($key)) then "yes" else "no" end')"
    non_empty="$(printf '%s\n' "${response}" | jq -r --arg key "${key}" 'if (((.data.data // {})[$key] // "") != "") then "yes" else "no" end')"
    echo "OpenBao KV key ${key}: present ${present}; non-empty ${non_empty}"
    [[ "${present}" = "yes" && "${non_empty}" = "yes" ]] || fail "OpenBao KV key ${key} is missing or empty at operator-kv/${logical_path}"
  done
}

check_openbao_kv() {
  local root_token init_file legacy_username legacy_token users_present users_non_empty artifacts_response

  init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  [[ -n "${root_token}" ]] || fail "Could not read root token from init file for OpenBao KV metadata checks"

  check_kv_path "${root_token}" "operator-plane/traefik/ovh-dns01" \
    OVH_ENDPOINT \
    OVH_APPLICATION_KEY \
    OVH_APPLICATION_SECRET \
    OVH_CONSUMER_KEY

  artifacts_response="$(token_exec "${root_token}" bao read -format=json "operator-kv/data/operator-plane/operator-artifacts/family-infra-01")" \
    || fail "OpenBao KV path is missing or unreadable: operator-kv/operator-plane/operator-artifacts/family-infra-01"
  echo "OpenBao KV path checked: operator-kv/operator-plane/operator-artifacts/family-infra-01"
  users_present="$(printf '%s\n' "${artifacts_response}" | jq -r 'if ((.data.data // {}) | has("users")) then "yes" else "no" end')"
  users_non_empty="$(printf '%s\n' "${artifacts_response}" | jq -r 'if (((.data.data // {}).users // "") != "") then "yes" else "no" end')"
  legacy_username="$(printf '%s\n' "${artifacts_response}" | jq -r 'if ((.data.data // {}) | has("username")) then "yes" else "no" end')"
  legacy_token="$(printf '%s\n' "${artifacts_response}" | jq -r 'if ((.data.data // {}) | has("token")) then "yes" else "no" end')"
  echo "OpenBao KV key users: present ${users_present}; non-empty ${users_non_empty}"
  if [[ "${users_present}" != "yes" || "${users_non_empty}" != "yes" ]]; then
    if [[ "${legacy_username}" = "yes" || "${legacy_token}" = "yes" ]]; then
      fail "operator-artifacts BasicAuth KV must contain final key users; runtime hash generation is no longer supported."
    fi
    fail "OpenBao KV key users is missing or empty at operator-kv/operator-plane/operator-artifacts/family-infra-01"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --lock-file)
      [[ "$#" -ge 2 ]] || fail "--lock-file requires a path."
      lock_file="$2"
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

require_command kubectl
require_command jq
require_command grep
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
[[ -f "${image_lib}" ]] || fail "Missing image resolver: ${image_lib}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
# shellcheck source=./lib/resolve-runner-image.sh
source "${image_lib}"

[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
openbao_namespace="${OPENBAO_NAMESPACE}"
openbao_pod_name="${OPENBAO_POD_NAME}"
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

effective_image="$(resolve_operator_secret_sync_runner_image "${lock_file}" "${runtime_image_id}")"
runner_digest="${effective_image##*@}"
echo "Runner image id: ${runtime_image_id}"
echo "Runner image digest present: yes"
echo "Runner image digest: ${runner_digest}"
echo "Effective runner image: ${effective_image}"

check_resource "Namespace ${namespace}" get namespace "${namespace}"
check_resource "ServiceAccount ${namespace}/${service_account_name}" -n "${namespace}" get serviceaccount "${service_account_name}"
check_configmap_key openbao-ca-bundle ca.crt
check_configmap_key operator-plane-secret-sync-script sync-operator-plane-secrets.sh
check_can_i_for_secret kube-system traefik-ovh-dns-credentials
check_can_i_for_secret operator-artifacts operator-artifacts-basicauth
check_openbao_auth
check_openbao_kv

echo "operator-secret-sync preflight passed."
echo "No Secret data, OpenBao tokens, PEM contents, htpasswd contents, or generated hashes were printed."
