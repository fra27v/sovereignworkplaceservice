#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"

namespace="operator-secret-sync"
service_account_name="operator-plane-secret-sync"
configmap_name="operator-plane-secret-sync-script"
configmap_key="sync-operator-plane-secrets.sh"
ca_configmap_name="openbao-ca-bundle"
ca_configmap_key="ca.crt"
job_name="operator-plane-secret-sync"
openbao_namespace="openbao-operator"
openbao_pod_name="openbao-global-0"
auth_path="kubernetes"
openbao_role_name="operator-plane-secret-sync"
openbao_policy_name="operator-plane-secret-sync"
init_file=""
vault_addr="https://127.0.0.1:8200"
vault_cacert=""
vault_cacert_fallback=""
bao_addr="${vault_addr}"

summary_fail=()

required_env_keys=(
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
  OPENBAO_TLS_DIR
)

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-secret-sync-foundation.sh [--env-file <path>] [--help]

Read-only verification for the operator-secret-sync foundation. It does not
require the future sync Job or runner image to exist.

Options:
  --env-file <path>  Path to operator-plane.env.
  --help             Show this help.
USAGE
}

ok() {
  echo "OK: $*"
}

warn() {
  echo "WARN: $*" >&2
}

fail_component() {
  summary_fail+=("$1")
  echo "FAIL: $1" >&2
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || {
    fail_component "Missing required command: ${name}"
    print_summary
    exit 1
  }
}

kubectl_safe() {
  kubectl "$@" 2>/dev/null
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

  if kubectl_safe "$@" >/dev/null; then
    ok "${label} exists"
  else
    fail_component "${label} is missing"
  fi
}

check_rolebinding_subject() {
  local namespace_arg="$1"
  local name="$2"
  local subject_count

  subject_count="$(kubectl_safe -n "${namespace_arg}" get rolebinding "${name}" -o json \
    | jq -r --arg sa "${service_account_name}" --arg ns "${namespace}" '
        [(.subjects // [])
        | .[]
        | select(.kind == "ServiceAccount" and .name == $sa and .namespace == $ns)]
        | length
      ' || true)"

  if [[ "${subject_count}" = "1" ]]; then
    ok "RoleBinding ${namespace_arg}/${name} points to ServiceAccount ${namespace}/${service_account_name}"
  else
    fail_component "RoleBinding ${namespace_arg}/${name} does not point to ServiceAccount ${namespace}/${service_account_name}"
  fi
}

check_role_secret_scope() {
  local role_namespace="$1"
  local role_name="$2"
  local secret_name="$3"
  local scoped create_count

  scoped="$(kubectl_safe -n "${role_namespace}" get role "${role_name}" -o json \
    | jq -r --arg secret "${secret_name}" '
        [(.rules // [])
        | .[]
        | select((.apiGroups // []) == [""])
        | select((.resources // []) | index("secrets"))
        | select((.resourceNames // []) | index($secret))
        | select((.verbs // []) | index("get"))
        | select((.verbs // []) | index("update"))
        | select((.verbs // []) | index("patch"))]
        | length
      ' || true)"

  if [[ "${scoped}" -ge 1 ]]; then
    ok "Role ${role_namespace}/${role_name} is scoped to Secret ${secret_name}"
  else
    fail_component "Role ${role_namespace}/${role_name} is not scoped to Secret ${secret_name} with get/update/patch"
  fi

  create_count="$(kubectl_safe -n "${role_namespace}" get role "${role_name}" -o json \
    | jq -r '
        [(.rules // [])
        | .[]
        | select((.apiGroups // []) == [""])
        | select((.resources // []) | index("secrets"))
        | select((.verbs // []) | index("create"))]
        | length
      ' || true)"

  if [[ "${create_count}" = "0" ]]; then
    ok "Role ${role_namespace}/${role_name} does not grant Secret create"
  else
    fail_component "Role ${role_namespace}/${role_name} grants Secret create; foundation RBAC must stay resource-name scoped"
  fi
}

check_configmap_key_non_empty() {
  local cm_namespace="$1"
  local cm_name="$2"
  local key="$3"
  local has_key

  has_key="$(kubectl_safe -n "${cm_namespace}" get configmap "${cm_name}" -o json \
    | jq -r --arg key "${key}" 'if (((.data // {})[$key] // "") != "") then "yes" else "no" end' || true)"

  if [[ "${has_key}" = "yes" ]]; then
    ok "ConfigMap ${cm_namespace}/${cm_name} contains non-empty key ${key}"
  else
    fail_component "ConfigMap ${cm_namespace}/${cm_name} is missing non-empty key ${key}"
  fi
}

check_job_absent_or_future() {
  if kubectl_safe -n "${namespace}" get job "${job_name}" >/dev/null; then
    warn "Job ${namespace}/${job_name} exists; foundation verification does not require or run it"
  else
    ok "Job ${namespace}/${job_name} is absent as expected for foundation-only stage"
  fi
}

check_openbao_auth() {
  local root_token auth_list role_json role_sa_names role_sa_namespaces role_policies

  init_file="$(operator_plane_env_resolve_openbao_bootstrap_init_file)"
  root_token="$(jq -r '.root_token // empty' "${init_file}")"
  if [[ -z "${root_token}" ]]; then
    fail_component "Could not read root token from init file for OpenBao auth verification"
    return 0
  fi

  auth_list="$(token_exec "${root_token}" bao auth list -format=json)"
  if printf '%s\n' "${auth_list}" | jq -e --arg path "${auth_path}/" 'has($path)' >/dev/null; then
    ok "OpenBao Kubernetes auth method exists at ${auth_path}/"
  else
    fail_component "OpenBao Kubernetes auth method is missing at ${auth_path}/"
    return 0
  fi

  if token_exec "${root_token}" bao policy read "${openbao_policy_name}" >/dev/null 2>&1; then
    ok "OpenBao policy exists: ${openbao_policy_name}"
  else
    fail_component "OpenBao policy is missing: ${openbao_policy_name}"
  fi

  role_json="$(token_exec "${root_token}" bao read -format=json "auth/${auth_path}/role/${openbao_role_name}")"
  role_sa_names="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_names[]?')"
  role_sa_namespaces="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_namespaces[]?')"
  role_policies="$(printf '%s\n' "${role_json}" | jq -r '.data.policies[]?')"

  if printf '%s\n' "${role_sa_names}" | grep -Fxq "${service_account_name}"; then
    ok "OpenBao auth role is bound to ServiceAccount ${service_account_name}"
  else
    fail_component "OpenBao auth role is not bound to ServiceAccount ${service_account_name}"
  fi

  if printf '%s\n' "${role_sa_namespaces}" | grep -Fxq "${namespace}"; then
    ok "OpenBao auth role is bound to namespace ${namespace}"
  else
    fail_component "OpenBao auth role is not bound to namespace ${namespace}"
  fi

  if printf '%s\n' "${role_policies}" | grep -Fxq "${openbao_policy_name}"; then
    ok "OpenBao auth role attaches policy ${openbao_policy_name}"
  else
    fail_component "OpenBao auth role does not attach policy ${openbao_policy_name}"
  fi
}

print_summary() {
  echo
  echo "== operator-secret-sync foundation summary =="
  if [[ "${#summary_fail[@]}" -eq 0 ]]; then
    echo "FAIL components:"
    echo "  none"
  else
    echo "FAIL components:"
    printf '  %s\n' "${summary_fail[@]}"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || {
        echo "--env-file requires a path." >&2
        exit 1
      }
      env_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command kubectl
require_command jq
require_command grep

[[ -f "${env_loader}" ]] || {
  fail_component "Missing env loader: ${env_loader}"
  print_summary
  exit 1
}
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || {
  fail_component "Missing env file: ${env_file}"
  print_summary
  exit 1
}
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"
openbao_namespace="${OPENBAO_NAMESPACE}"
openbao_pod_name="${OPENBAO_POD_NAME}"
vault_cacert="$(operator_plane_env_openbao_client_cacert_in_pod)"
vault_cacert_fallback="$(operator_plane_env_openbao_bootstrap_cacert_in_pod)"

check_resource "Namespace ${namespace}" get namespace "${namespace}"
check_resource "ServiceAccount ${namespace}/${service_account_name}" -n "${namespace}" get serviceaccount "${service_account_name}"
check_resource "Role kube-system/${service_account_name}" -n kube-system get role "${service_account_name}"
check_resource "RoleBinding kube-system/${service_account_name}" -n kube-system get rolebinding "${service_account_name}"
check_rolebinding_subject kube-system "${service_account_name}"
check_role_secret_scope kube-system "${service_account_name}" traefik-ovh-dns-credentials
check_resource "Role operator-artifacts/${service_account_name}" -n operator-artifacts get role "${service_account_name}"
check_resource "RoleBinding operator-artifacts/${service_account_name}" -n operator-artifacts get rolebinding "${service_account_name}"
check_rolebinding_subject operator-artifacts "${service_account_name}"
check_role_secret_scope operator-artifacts "${service_account_name}" operator-artifacts-basicauth
check_resource "ConfigMap ${namespace}/${configmap_name}" -n "${namespace}" get configmap "${configmap_name}"
check_configmap_key_non_empty "${namespace}" "${configmap_name}" "${configmap_key}"
check_resource "ConfigMap ${namespace}/${ca_configmap_name}" -n "${namespace}" get configmap "${ca_configmap_name}"
check_configmap_key_non_empty "${namespace}" "${ca_configmap_name}" "${ca_configmap_key}"
check_job_absent_or_future
check_openbao_auth
print_summary

if [[ "${#summary_fail[@]}" -gt 0 ]]; then
  exit 1
fi
