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

cleanup="false"

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

[[ -d "${repo_root}/k8s/environments/family-infra" ]] || fail "Could not determine repository root."

section "Verify k3s baseline"
"${repo_root}/k8s/environments/family-infra/scripts/setup-family-infra.sh" verify

section "Verify Traefik runtime"
"${repo_root}/k8s/platform/components/traefik/scripts/verify.sh" \
  --env-file "${repo_root}/k8s/environments/family-infra/components/traefik-runtime.env"

section "Apply whoami routing smoke test"
"${repo_root}/k8s/environments/family-infra/tests/smoke/whoami-routing/apply.sh"

section "Verify whoami routing smoke test"
"${repo_root}/k8s/environments/family-infra/tests/smoke/whoami-routing/verify.sh"

if [[ "${cleanup}" == "true" ]]; then
  section "Delete whoami routing smoke test"
  "${repo_root}/k8s/environments/family-infra/tests/smoke/whoami-routing/delete.sh"
fi

echo
echo "family-infra regression test suite passed"
