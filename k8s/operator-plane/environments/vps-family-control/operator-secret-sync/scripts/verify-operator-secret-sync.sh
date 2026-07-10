#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
lock_file="${env_dir}/dependencies.lock.json"
foundation_verifier="${script_dir}/verify-operator-secret-sync-foundation.sh"
image_lib="${script_dir}/lib/resolve-runner-image.sh"

namespace="operator-secret-sync"
job_name="operator-plane-secret-sync"
runtime_image_id="operator-secret-sync-runner-candidate"

summary_ok=()
summary_warn=()
summary_fail=()

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-secret-sync.sh [--env-file <path>] [--lock-file <path>] [--help]

Verifies operator-secret-sync foundation, dependency-lock runner pinning, the
optional real Job status, and target Secret key names without printing Secret
data.

Options:
  --env-file <path>   Path to operator-plane.env.
  --lock-file <path>  Path to dependencies.lock.json.
  --help              Show this help.
USAGE
}

ok() {
  summary_ok+=("$1")
  echo "OK: $1"
}

warn() {
  summary_warn+=("$1")
  echo "WARN: $1" >&2
}

fail_component() {
  summary_fail+=("$1")
  echo "FAIL: $1" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    fail_component "Missing required command: $1"
    print_summary
    exit 1
  }
}

secret_keys() {
  local target_namespace="$1"
  local name="$2"

  kubectl -n "${target_namespace}" get secret "${name}" -o json \
    | jq -r '.data // {} | keys[]'
}

expect_exact_keys() {
  local target_namespace="$1"
  local name="$2"
  shift 2

  if ! kubectl -n "${target_namespace}" get secret "${name}" >/dev/null 2>&1; then
    warn "TODO: runtime Secret ${target_namespace}/${name} is missing until the explicit operator-secret-sync Job phase runs"
    return 0
  fi

  local expected_file
  local actual_file
  expected_file="$(mktemp)"
  actual_file="$(mktemp)"

  printf '%s\n' "$@" | sort > "${expected_file}"
  secret_keys "${target_namespace}" "${name}" | sort > "${actual_file}"

  echo "Secret ${target_namespace}/${name} key names:"
  sed 's/^/  - /' "${actual_file}"

  if cmp -s "${expected_file}" "${actual_file}"; then
    ok "Secret ${target_namespace}/${name} contains the expected key names only"
  else
    fail_component "Secret ${target_namespace}/${name} key names do not match expected set"
  fi

  rm -f "${expected_file}" "${actual_file}"
}

check_foundation() {
  if [[ ! -x "${foundation_verifier}" && ! -f "${foundation_verifier}" ]]; then
    fail_component "Foundation verifier is missing: ${foundation_verifier}"
    return 0
  fi

  echo
  echo "== operator-secret-sync foundation =="
  if "${foundation_verifier}" --env-file "${env_file}"; then
    ok "operator-secret-sync foundation verification passed"
  else
    fail_component "operator-secret-sync foundation verification failed"
  fi
}

check_locked_runner_image() {
  local effective_image image_part digest

  echo
  echo "== operator-secret-sync runner image =="
  if ! effective_image="$(resolve_operator_secret_sync_runner_image "${lock_file}" "${runtime_image_id}")"; then
    fail_component "dependency lock does not contain a valid digest-pinned runner image"
    return 0
  fi

  image_part="${effective_image%@*}"
  digest="${effective_image##*@}"
  if [[ "${effective_image}" == "${image_part}@${digest}" && "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    ok "dependency lock resolves runner image as tag@sha256 digest"
    echo "Runner image id: ${runtime_image_id}"
    echo "Runner digest: ${digest}"
  else
    fail_component "dependency lock runner image is not tag@sha256 digest pinned"
  fi
}

check_job() {
  local image succeeded failed active

  echo
  echo "== operator-secret-sync Job/run =="
  if ! kubectl -n "${namespace}" get job "${job_name}" >/dev/null 2>&1; then
    warn "TODO: Job ${namespace}/${job_name} is not present until the explicit real Job phase runs"
    return 0
  fi

  image="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sync")].image}')"
  echo "Job image: ${image}"
  if [[ "${image}" =~ :[^/@]+@sha256:[0-9a-f]{64}$ ]]; then
    ok "Job image uses tag@sha256 digest"
  else
    fail_component "Job image must use tag@sha256 digest"
  fi

  succeeded="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  failed="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  active="$(kubectl -n "${namespace}" get job "${job_name}" -o jsonpath='{.status.active}' 2>/dev/null || true)"
  echo "Job status: succeeded=${succeeded:-0} failed=${failed:-0} active=${active:-0}"
  if [[ "${succeeded:-0}" = "1" ]]; then
    ok "operator-secret-sync Job completed successfully"
  elif [[ "${failed:-0}" != "" && "${failed:-0}" != "0" ]]; then
    fail_component "operator-secret-sync Job has failed pods"
  else
    warn "operator-secret-sync Job exists but has not completed yet"
  fi
}

print_summary() {
  echo
  echo "== operator-secret-sync summary =="
  echo "OK components:"
  if [[ "${#summary_ok[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_ok[@]}"
  fi

  echo "WARN components:"
  if [[ "${#summary_warn[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_warn[@]}"
  fi

  echo "FAIL components:"
  if [[ "${#summary_fail[@]}" -eq 0 ]]; then
    echo "  none"
  else
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
    --lock-file)
      [[ "$#" -ge 2 ]] || {
        echo "--lock-file requires a path." >&2
        exit 1
      }
      lock_file="$2"
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
require_command sed
[[ -f "${image_lib}" ]] || {
  fail_component "Missing image resolver: ${image_lib}"
  print_summary
  exit 1
}
# shellcheck source=./lib/resolve-runner-image.sh
source "${image_lib}"

check_foundation
check_locked_runner_image
check_job

expect_exact_keys kube-system traefik-ovh-dns-credentials \
  OVH_ENDPOINT \
  OVH_APPLICATION_KEY \
  OVH_APPLICATION_SECRET \
  OVH_CONSUMER_KEY

expect_exact_keys operator-artifacts operator-artifacts-basicauth users

print_summary

if [[ "${#summary_fail[@]}" -gt 0 ]]; then
  exit 1
fi
