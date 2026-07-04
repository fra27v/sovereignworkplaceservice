#!/usr/bin/env bash
set -euo pipefail

summary_ok=()
summary_warn=()
summary_fail=()

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
    fail_component "Secret ${namespace}/${name} is missing"
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
    fail_component "Secret ${namespace}/${name} key names do not match expected set"
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
    fail_component "operator-secret-sync Job has not completed successfully"
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

require_command kubectl
require_command jq

check_resource "Namespace operator-secret-sync" get namespace operator-secret-sync
check_resource "ServiceAccount operator-secret-sync/operator-plane-secret-sync" -n operator-secret-sync get serviceaccount operator-plane-secret-sync
check_resource "Role kube-system/operator-plane-secret-sync" -n kube-system get role operator-plane-secret-sync
check_resource "RoleBinding kube-system/operator-plane-secret-sync" -n kube-system get rolebinding operator-plane-secret-sync
check_resource "Role operator-artifacts/operator-plane-secret-sync" -n operator-artifacts get role operator-plane-secret-sync
check_resource "RoleBinding operator-artifacts/operator-plane-secret-sync" -n operator-artifacts get rolebinding operator-plane-secret-sync
check_resource "ConfigMap operator-secret-sync/operator-plane-secret-sync-script" -n operator-secret-sync get configmap operator-plane-secret-sync-script
check_openbao_ca_bundle
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
