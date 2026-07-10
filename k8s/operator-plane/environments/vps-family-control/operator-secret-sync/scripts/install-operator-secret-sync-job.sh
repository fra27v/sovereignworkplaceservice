#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
lock_file="${env_dir}/dependencies.lock.json"
image_lib="${script_dir}/lib/resolve-runner-image.sh"
preflight_script="${script_dir}/preflight-operator-secret-sync.sh"
job_manifest="${sync_dir}/job.yaml"

namespace="operator-secret-sync"
job_name="operator-plane-secret-sync"
runtime_image_id="operator-secret-sync-runner-candidate"
dry_run="false"
wait_for_job="false"
replace_completed="false"

usage() {
  cat <<'USAGE'
Usage:
  install-operator-secret-sync-job.sh [--env-file <path>] [--lock-file <path>] [--dry-run] [--wait] [--replace-completed] [--help]

Runs the explicit one-shot operator-secret-sync Job using the digest-pinned
runner image resolved from dependencies.lock.json.

Options:
  --env-file <path>      Path to operator-plane.env.
  --lock-file <path>     Path to dependencies.lock.json.
  --dry-run              Print safe manifest metadata without mutating live state.
  --wait                 Wait for the Job to complete or fail.
  --replace-completed    Delete and recreate an existing completed Job with the same name.
  --help                 Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

render_job_manifest() {
  local output_file="$1"
  local effective_image="$2"

  sed -E "s#^([[:space:]]*image: ).*#\1${effective_image}#" "${job_manifest}" > "${output_file}"
}

print_dry_run_metadata() {
  local effective_image="$1"

  cat <<PLAN
DRY-RUN: would run preflight ${preflight_script}
DRY-RUN: would apply one-shot Job metadata:
  Namespace: ${namespace}
  Job: ${job_name}
  ServiceAccount: ${namespace}/operator-plane-secret-sync
  Runner image id: ${runtime_image_id}
  Runner image: ${effective_image}
  Mount: ConfigMap ${namespace}/openbao-ca-bundle at /var/run/openbao-ca
  Mount: ConfigMap ${namespace}/operator-plane-secret-sync-script at /scripts
  hostPath: no
  privileged: no
  package install at runtime: no
  mounted OpenBao token Secret: no
PLAN
}

check_existing_job() {
  local status_json succeeded failed active

  if ! kubectl -n "${namespace}" get job "${job_name}" >/dev/null 2>&1; then
    return 0
  fi

  status_json="$(kubectl -n "${namespace}" get job "${job_name}" -o json)"
  succeeded="$(printf '%s\n' "${status_json}" | jq -r '.status.succeeded // 0')"
  failed="$(printf '%s\n' "${status_json}" | jq -r '.status.failed // 0')"
  active="$(printf '%s\n' "${status_json}" | jq -r '.status.active // 0')"

  echo "Existing Job ${namespace}/${job_name}: succeeded=${succeeded} failed=${failed} active=${active}"

  if [[ "${succeeded}" = "1" && "${replace_completed}" = "true" ]]; then
    echo "+ kubectl -n ${namespace} delete job ${job_name}"
    kubectl -n "${namespace}" delete job "${job_name}"
    return 0
  fi

  if [[ "${succeeded}" = "1" ]]; then
    fail "Job ${namespace}/${job_name} already completed. Use --replace-completed to delete and recreate it explicitly."
  fi

  fail "Job ${namespace}/${job_name} already exists and is not completed; refusing to replace it."
}

wait_for_completion() {
  local phase succeeded failed pod_name

  echo "Waiting for Job ${namespace}/${job_name} to Complete or Failed."
  while true; do
    succeeded="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    if [[ "${succeeded:-0}" = "1" ]]; then
      echo "Job ${namespace}/${job_name} completed successfully."
      kubectl -n "${namespace}" get job "${job_name}" \
        -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.succeeded,START:.status.startTime,COMPLETION:.status.completionTime' \
        --no-headers
      return 0
    fi
    if [[ "${failed:-0}" != "" && "${failed:-0}" != "0" ]]; then
      echo "Job ${namespace}/${job_name} failed." >&2
      pod_name="$(kubectl -n "${namespace}" get pods -l job-name="${job_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      if [[ -n "${pod_name}" ]]; then
        kubectl -n "${namespace}" describe pod "${pod_name}" | sed -n '/^Events:/,$p' >&2 || true
        kubectl -n "${namespace}" logs "${pod_name}" >&2 || true
      fi
      return 1
    fi
    phase="$(kubectl -n "${namespace}" get pods -l job-name="${job_name}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
    echo "Job status: succeeded=${succeeded:-0} failed=${failed:-0} podPhase=${phase:-pending}"
    sleep 5
  done
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
    --dry-run)
      dry_run="true"
      shift
      ;;
    --wait)
      wait_for_job="true"
      shift
      ;;
    --replace-completed)
      replace_completed="true"
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

require_command jq
require_command sed
[[ -f "${image_lib}" ]] || fail "Missing image resolver: ${image_lib}"
[[ -x "${preflight_script}" || -f "${preflight_script}" ]] || fail "Missing preflight script: ${preflight_script}"
[[ -f "${job_manifest}" ]] || fail "Missing Job manifest: ${job_manifest}"
# shellcheck source=./lib/resolve-runner-image.sh
source "${image_lib}"

effective_image="$(resolve_operator_secret_sync_runner_image "${lock_file}" "${runtime_image_id}")"

if [[ "${dry_run}" = "true" ]]; then
  print_dry_run_metadata "${effective_image}"
  exit 0
fi

require_command kubectl
"${preflight_script}" --env-file "${env_file}" --lock-file "${lock_file}"

rendered_manifest="$(mktemp)"
cleanup() {
  rm -f "${rendered_manifest}"
}
trap cleanup EXIT
render_job_manifest "${rendered_manifest}" "${effective_image}"

check_existing_job
echo "+ kubectl apply -f <rendered operator-secret-sync Job>"
kubectl apply -f "${rendered_manifest}"

if [[ "${wait_for_job}" = "true" ]]; then
  wait_for_completion
else
  echo "operator-secret-sync Job was created."
fi

echo "Secret values, OpenBao tokens, PEM contents, htpasswd contents, and generated hashes were not printed."
