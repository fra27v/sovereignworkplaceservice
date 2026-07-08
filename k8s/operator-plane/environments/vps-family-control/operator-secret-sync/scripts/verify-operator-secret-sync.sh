#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sync_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${sync_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
foundation_verifier="${script_dir}/verify-operator-secret-sync-foundation.sh"

summary_ok=()
summary_warn=()
summary_fail=()

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-secret-sync.sh [--env-file <path>] [--help]

Verifies operator-secret-sync in staged mode:
  - foundation resources are required target state
  - future Job/run and runtime Secret projection checks are WARN/TODO for now

Options:
  --env-file <path>  Path to operator-plane.env.
  --help             Show this help.
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
  local namespace="$1"
  local name="$2"

  kubectl -n "${namespace}" get secret "${name}" -o json \
    | jq -r '.data // {} | keys[]'
}

expect_exact_keys() {
  local namespace="$1"
  local name="$2"
  shift 2

  if ! kubectl -n "${namespace}" get secret "${name}" >/dev/null 2>&1; then
    warn "TODO: runtime Secret ${namespace}/${name} is missing until the future operator-secret-sync Job phase runs"
    return 0
  fi

  local expected_file
  local actual_file
  expected_file="$(mktemp)"
  actual_file="$(mktemp)"

  printf '%s\n' "$@" | sort > "${expected_file}"
  secret_keys "${namespace}" "${name}" | sort > "${actual_file}"

  echo "Secret ${namespace}/${name} key names:"
  sed 's/^/  - /' "${actual_file}"

  if cmp -s "${expected_file}" "${actual_file}"; then
    ok "Secret ${namespace}/${name} contains the expected key names only"
  else
    warn "TODO: Secret ${namespace}/${name} key names do not match expected set; future Job/run phase must reconcile it"
  fi

  rm -f "${expected_file}" "${actual_file}"
}

check_resource() {
  local label="$1"
  shift

  if kubectl "$@" >/dev/null 2>&1; then
    ok "${label} exists"
  else
    fail_component "${label} is missing"
  fi
}

check_job() {
  if ! kubectl -n operator-secret-sync get job operator-plane-secret-sync >/dev/null 2>&1; then
    warn "Job operator-secret-sync/operator-plane-secret-sync is not present"
    return 0
  fi

  kubectl -n operator-secret-sync get job operator-plane-secret-sync \
    -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.succeeded,FAILED:.status.failed' \
    --no-headers

  local succeeded
  succeeded="$(kubectl -n operator-secret-sync get job operator-plane-secret-sync -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  if [[ "${succeeded:-0}" = "1" ]]; then
    ok "operator-secret-sync Job completed successfully"
  else
    warn "TODO: operator-secret-sync Job has not completed successfully; runner image and Job execution are future explicit work"
  fi
}

check_openbao_ca_bundle() {
  if ! kubectl -n operator-secret-sync get configmap openbao-ca-bundle >/dev/null 2>&1; then
    fail_component "ConfigMap operator-secret-sync/openbao-ca-bundle is missing"
    return 0
  fi

  local has_ca_key
  has_ca_key="$(kubectl -n operator-secret-sync get configmap openbao-ca-bundle -o json | jq -r 'if ((.data // {}) | has("ca.crt")) then "yes" else "no" end')"
  if [[ "${has_ca_key}" = "yes" ]]; then
    ok "ConfigMap operator-secret-sync/openbao-ca-bundle contains key ca.crt"
  else
    fail_component "ConfigMap operator-secret-sync/openbao-ca-bundle is missing key ca.crt"
  fi
}

check_foundation() {
  if [[ ! -x "${foundation_verifier}" ]]; then
    fail_component "Foundation verifier is missing or not executable: ${foundation_verifier}"
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
check_foundation

echo
echo "== future operator-secret-sync Job/run =="
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
