#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
namespace="operator-secret-sync"
job_name="operator-plane-secret-sync"
configmap_name="operator-plane-secret-sync-script"
sync_script="${sync_dir}/scripts/sync-operator-plane-secrets.sh"
dry_run="false"

usage() {
  cat <<EOF
Usage: $0 [--dry-run]

Apply the vps-family-control operator-secret-sync namespace, ServiceAccount,
RBAC, ConfigMap, and one-shot Job.

Options:
  --dry-run  Print resources that would be applied without changing the cluster.
  --help     Show this help.

Safety:
  - Does not print Secret data.
  - Does not delete runtime Secrets.
  - Deletes only an old Job with the exact same name before reapplying, because
    Kubernetes Job pod templates are immutable.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

apply_file() {
  local path="$1"

  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would apply ${path}"
    return 0
  fi

  echo "+ kubectl apply -f ${path}"
  kubectl apply -f "${path}"
}

apply_sync_script_configmap() {
  [[ -s "${sync_script}" ]] || fail "Missing or empty sync script: ${sync_script}"

  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would create/update ConfigMap ${namespace}/${configmap_name} from ${sync_script}"
    return 0
  fi

  echo "+ kubectl -n ${namespace} create configmap ${configmap_name} --from-file=sync-operator-plane-secrets.sh=${sync_script} --dry-run=client -o yaml | kubectl apply -f -"
  kubectl -n "${namespace}" create configmap "${configmap_name}" \
    --from-file="sync-operator-plane-secrets.sh=${sync_script}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run="true"
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

apply_file "${sync_dir}/namespace.yaml"
apply_file "${sync_dir}/serviceaccount.yaml"
apply_file "${sync_dir}/rbac.yaml"
apply_sync_script_configmap

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: would delete old Job ${namespace}/${job_name} if present"
  echo "DRY-RUN: would apply ${sync_dir}/job.yaml"
  exit 0
fi

echo "+ kubectl -n ${namespace} delete job ${job_name} --ignore-not-found"
kubectl -n "${namespace}" delete job "${job_name}" --ignore-not-found

apply_file "${sync_dir}/job.yaml"

echo "operator-secret-sync Job was applied."
echo "Secret values were not printed."
