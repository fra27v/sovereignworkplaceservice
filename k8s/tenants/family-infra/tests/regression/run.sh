#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run.sh [--cleanup]

Runs the family-infra regression test suite.

Options:
  --cleanup   Delete the whoami routing smoke test after verification.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

on_error() {
  local exit_code="$?"

  echo >&2
  echo "family-infra regression test suite failed" >&2
  echo "failed step: ${current_step}" >&2

  if [[ "${whoami_smoke_test_applied}" == "true" && "${cleanup_completed}" != "true" ]]; then
    echo "cleanup: sudo ${repo_root}/k8s/tenants/family-infra/tests/smoke/whoami-routing/delete.sh" >&2
  fi

  exit "${exit_code}"
}

run_step() {
  current_step="$1"
  shift

  section "${current_step}"
  "$@"
}

cleanup="false"
cleanup_completed="false"
current_step="initialization"
whoami_smoke_test_applied="false"

trap on_error ERR

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup)
      cleanup="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"

[[ -d "${repo_root}/k8s/tenants/family-infra" ]] || fail "Could not determine repository root."

run_step "Verify k3s baseline" \
  "${repo_root}/k8s/common/k3s/scripts/setup-k3s.sh" verify

run_step "Verify Traefik runtime" \
  "${repo_root}/k8s/components/traefik/scripts/verify.sh" \
  --env-file "${repo_root}/k8s/tenants/family-infra/components/traefik-runtime.env"

run_step "Apply whoami routing smoke test" \
  "${repo_root}/k8s/tenants/family-infra/tests/smoke/whoami-routing/apply.sh"
whoami_smoke_test_applied="true"

run_step "Verify whoami routing smoke test" \
  "${repo_root}/k8s/tenants/family-infra/tests/smoke/whoami-routing/verify.sh"

if [[ "${cleanup}" == "true" ]]; then
  run_step "Delete whoami routing smoke test" \
    "${repo_root}/k8s/tenants/family-infra/tests/smoke/whoami-routing/delete.sh"
  cleanup_completed="true"
fi

echo
echo "family-infra regression test suite passed"
