#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
openbao_auth_script="${env_dir}/openbao/scripts/configure-openbao-kubernetes-auth-for-secret-sync.sh"
ca_bundle_script="${script_dir}/install-openbao-ca-bundle-configmap.sh"

namespace="operator-secret-sync"
service_account_name="operator-plane-secret-sync"
configmap_name="operator-plane-secret-sync-script"
configmap_key="sync-operator-plane-secrets.sh"
sync_script="${script_dir}/sync-operator-plane-secrets.sh"
dry_run="false"

usage() {
  cat <<'USAGE'
Usage:
  install-operator-secret-sync-foundation.sh [--env-file <path>] [--dry-run] [--help]

Installs the operator-secret-sync foundation without creating or running the
one-shot sync Job and without selecting a runner image.

The foundation includes namespace, ServiceAccount, least-privilege RBAC, the
sync script ConfigMap, the public OpenBao CA bundle ConfigMap, and Global
OpenBao Kubernetes auth configuration for the future Job.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Print planned resources and substeps without mutating Kubernetes or OpenBao.
  --help             Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || fail "Missing required command: ${name}"
}

run_step() {
  local label="$1"
  shift

  echo "+ $*"
  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would run ${label}"
    return 0
  fi

  "$@"
}

run_optional_dry_run_step() {
  local label="$1"
  shift
  local args=("$@")

  if [[ "${dry_run}" = "true" ]]; then
    args+=(--dry-run)
  fi

  run_step "${label}" "${args[@]}"
}

apply_foundation_yaml() {
  if [[ "${dry_run}" = "true" ]]; then
    cat <<PLAN
DRY-RUN: would apply Kubernetes foundation resources:
  Namespace: operator-secret-sync
  Namespace: operator-artifacts
  ServiceAccount: operator-secret-sync/${service_account_name}
  Role: kube-system/${service_account_name}
  RoleBinding: kube-system/${service_account_name}
  Role: operator-artifacts/${service_account_name}
  RoleBinding: operator-artifacts/${service_account_name}

RBAC tradeoff:
  The foundation grants get/update/patch only for the expected Secret names.
  It intentionally does not grant create because Kubernetes RBAC cannot combine
  create with resourceNames safely. The future Job phase must ensure target
  Secrets exist first or intentionally revise RBAC with a documented create path.
PLAN
    return 0
  fi

  kubectl apply -f "${sync_dir}/namespace.yaml"
  kubectl apply -f "${sync_dir}/serviceaccount.yaml"
  kubectl apply -f "${sync_dir}/rbac.yaml"
}

apply_sync_script_configmap() {
  [[ -s "${sync_script}" ]] || fail "Missing or empty sync script: ${sync_script}"

  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would create/update ConfigMap ${namespace}/${configmap_name} from ${sync_script}"
    echo "DRY-RUN: ConfigMap key would be ${configmap_key}"
    return 0
  fi

  kubectl -n "${namespace}" create configmap "${configmap_name}" \
    --from-file="${configmap_key}=${sync_script}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
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

require_command kubectl
[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true"

[[ -x "${ca_bundle_script}" ]] || fail "Missing executable CA bundle projection script: ${ca_bundle_script}"
[[ -x "${openbao_auth_script}" ]] || fail "Missing executable OpenBao Kubernetes auth script: ${openbao_auth_script}"

echo "Installing operator-secret-sync foundation."
echo "Namespace: ${namespace}"
echo "ServiceAccount: ${namespace}/${service_account_name}"
echo "Script ConfigMap: ${namespace}/${configmap_name}"
echo "No Job will be created or run."
echo "No runner image will be selected or validated."

apply_foundation_yaml
apply_sync_script_configmap

run_optional_dry_run_step "OpenBao CA bundle projection" "${ca_bundle_script}" --env-file "${env_file}"
run_optional_dry_run_step "OpenBao Kubernetes auth configuration" "${openbao_auth_script}" --env-file "${env_file}"

echo "operator-secret-sync foundation is installed."
echo "Secret values, OpenBao tokens, certificate PEM contents, and Job output were not printed."
