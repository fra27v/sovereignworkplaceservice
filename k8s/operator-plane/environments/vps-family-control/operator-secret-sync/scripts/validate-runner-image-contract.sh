#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"

runtime_image_id="operator-secret-sync-runner-candidate"
lock_file="${env_dir}/dependencies.lock.json"
namespace="operator-secret-sync"
dry_run="false"

usage() {
  cat <<EOF
Usage: $0 [--lock-file <path>] [--namespace <namespace>] [--dry-run] [--help]

Validate the operator-secret-sync runner image candidate from dependencies.lock.json
using a temporary Kubernetes workload.

Options:
  --lock-file <path>   Dependency lock file to read.
  --namespace <name>   Namespace for the temporary validation Job.
  --dry-run            Print the planned validation without creating anything.
  --help               Show this help.

The validation Job does not mount Secrets, does not use the real sync
ServiceAccount, and does not run the real operator-secret-sync Job.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

reject_latest() {
  local ref="$1"
  local last_component="${ref##*/}"

  if [[ "${last_component}" == "latest" || "${last_component}" == *":latest" || "${last_component}" == *":latest@"* ]]; then
    fail "Image references using :latest are forbidden: ${ref}"
  fi
}

validate_digest() {
  local digest="$1"

  [[ -z "${digest}" || "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Malformed digest for ${runtime_image_id}: ${digest}"
}

print_metadata() {
  cat <<EOF
Runner image validation metadata:
  lock file: ${lock_file}
  runtime image id: ${runtime_image_id}
  image tag: ${image_ref}
  digest configured: ${digest_configured}
  effective image: ${effective_image}
  validation namespace: ${namespace}
  required tools: ${required_tools_display}
EOF
}

cleanup_job() {
  if [[ -n "${job_name:-}" ]]; then
    kubectl -n "${namespace}" delete job "${job_name}" --ignore-not-found --cascade=foreground --wait=true --timeout=60s >/dev/null 2>&1 || true
  fi
}

run_validation_job() {
  local suffix
  suffix="$(date +%s)-${RANDOM}"
  job_name="operator-secret-sync-runner-image-check-${suffix}"

  trap cleanup_job EXIT

  cat <<EOF | kubectl -n "${namespace}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  labels:
    app.kubernetes.io/name: operator-secret-sync
    app.kubernetes.io/component: runner-image-validation
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 60
  template:
    metadata:
      labels:
        app.kubernetes.io/name: operator-secret-sync
        app.kubernetes.io/component: runner-image-validation
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: validate-runner-image
          image: ${effective_image}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -ceu
            - |
              command -v bash >/dev/null 2>&1
              bash -ceu 'printf "%s\n" "bash ok" >/dev/null'
              curl --version >/dev/null
              jq --version >/dev/null
              kubectl version --client=true >/dev/null
              openssl version >/dev/null
              printf "%s\n" "probe" | openssl passwd -apr1 -stdin >/dev/null
              test -r /etc/ssl/certs/ca-certificates.crt || test -d /etc/ssl/certs
          securityContext:
            allowPrivilegeEscalation: false
            privileged: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
EOF

  kubectl -n "${namespace}" wait --for=condition=complete "job/${job_name}" --timeout=180s
  kubectl -n "${namespace}" logs "job/${job_name}" --tail=50 >/dev/null || true
  cleanup_job
  trap - EXIT
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --lock-file)
      [[ "$#" -ge 2 ]] || fail "Missing value for --lock-file."
      lock_file="$2"
      shift
      ;;
    --namespace)
      [[ "$#" -ge 2 ]] || fail "Missing value for --namespace."
      namespace="$2"
      shift
      ;;
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

require_command jq
require_command kubectl

[[ -f "${lock_file}" ]] || fail "Dependency lock file not found: ${lock_file}"

entry_json="$(jq -er --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id)' "${lock_file}")" \
  || fail "Runtime image entry not found in lock: ${runtime_image_id}"

image_ref="$(jq -r '.image // empty' <<<"${entry_json}")"
digest="$(jq -r '.digest // empty' <<<"${entry_json}")"
required_tools_display="$(jq -r '(.requiredTools // []) | join(" ")' <<<"${entry_json}")"

[[ -n "${image_ref}" ]] || fail "Runtime image entry has no image: ${runtime_image_id}"
reject_latest "${image_ref}"
validate_digest "${digest}"

if [[ -n "${digest}" ]]; then
  digest_configured="yes"
  effective_image="${image_ref}@${digest}"
else
  digest_configured="no"
  effective_image="${image_ref}"
fi

print_metadata

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: would create a temporary no-secret Kubernetes Job for tool validation."
  exit 0
fi

run_validation_job
echo "Runner image contract validation passed."
