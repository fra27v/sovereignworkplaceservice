#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
namespace="operator-secret-sync"
job_name="operator-plane-secret-sync"
configmap_name="operator-plane-secret-sync-script"
sync_script="${sync_dir}/scripts/sync-operator-plane-secrets.sh"
job_manifest="${sync_dir}/job.yaml"
lock_file="${env_dir}/dependencies.lock.json"
runtime_image_id="operator-secret-sync-runner-candidate"
ca_configmap_name="openbao-ca-bundle"
ca_configmap_key="ca.crt"
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

preflight_runner_image() {
  local image_ref
  local image_last_component
  local locked_image_ref
  local locked_digest

  image_ref="$(awk '
    $1 == "image:" {
      print $2
      exit
    }
  ' "${job_manifest}")"

  [[ -n "${image_ref}" ]] || fail "Could not find runner image in ${job_manifest}."
  case "${image_ref}" in
    REPLACE-WITH-PINNED-STANDARD-RUNNER-IMAGE:*|"")
      if [[ "${dry_run}" = "true" ]]; then
        echo "DRY-RUN: runner image is not selected; real install would fail before applying the Job"
        return 0
      fi
      fail "Runner image is not selected. Choose a pinned standard runner image that satisfies operator-secret-sync/image-contract.md before applying the Job."
      ;;
    *:latest|*:latest@*)
      fail "Runner image uses :latest, which is forbidden: ${image_ref}"
      ;;
  esac

  image_last_component="${image_ref##*/}"
  if [[ "${image_ref}" != *@sha256:* && "${image_last_component}" != *:* ]]; then
    fail "Runner image must be pinned by tag or digest: ${image_ref}"
  fi

  locked_image_ref="$(jq -er --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id) | .image' "${lock_file}")" \
    || fail "Runtime image entry not found in lock: ${runtime_image_id}"
  locked_digest="$(jq -r --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id) | .digest // empty' "${lock_file}")"

  if [[ "${dry_run}" = "true" && ! "${locked_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "DRY-RUN: runner image digest is not pinned in ${lock_file}; real install would fail before applying resources"
    return 0
  fi

  [[ "${locked_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || fail "Runner image digest must be pinned in ${lock_file} before running the real sync Job."

  if [[ "${image_ref}" != "${locked_image_ref}@${locked_digest}" && "${image_ref}" != *@${locked_digest} ]]; then
    fail "Runner image in job.yaml must use the reviewed dependency-lock digest before real Job execution."
  fi
}

preflight_openbao_ca_bundle() {
  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would verify ConfigMap ${namespace}/${ca_configmap_name} contains key ${ca_configmap_key}"
    return 0
  fi

  echo "Checking OpenBao CA bundle ConfigMap metadata."
  kubectl -n "${namespace}" get configmap "${ca_configmap_name}" >/dev/null
  kubectl -n "${namespace}" get configmap "${ca_configmap_name}" -o json \
    | jq -e --arg key "${ca_configmap_key}" '((.data // {})[$key] // "") != ""' >/dev/null \
    || fail "ConfigMap ${namespace}/${ca_configmap_name} is missing non-empty key ${ca_configmap_key}."
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
require_command awk
require_command grep
require_command jq

preflight_runner_image
apply_file "${sync_dir}/namespace.yaml"
apply_file "${sync_dir}/serviceaccount.yaml"
apply_file "${sync_dir}/rbac.yaml"
apply_sync_script_configmap
preflight_openbao_ca_bundle

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: would delete old Job ${namespace}/${job_name} if present"
  echo "DRY-RUN: would apply ${job_manifest}"
  exit 0
fi

echo "+ kubectl -n ${namespace} delete job ${job_name} --ignore-not-found"
kubectl -n "${namespace}" delete job "${job_name}" --ignore-not-found

apply_file "${job_manifest}"

echo "operator-secret-sync Job was applied."
echo "Secret values were not printed."
