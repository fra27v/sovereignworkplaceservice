#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: setup-family-infra.sh <prepare|install|verify|all> [prepare-options]

Commands:
  prepare   Copy the example k3s config to /etc/rancher/k3s/config.yaml.
  install   Install k3s if it is not already installed.
  verify    Verify the family-infra k3s baseline.
  all       Run prepare, install, and verify in order.

Prepare options:
  --force   Allow prepare to overwrite an existing k3s config file.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -gt 0 ]] || {
  usage
  exit 1
}

command_name="$1"
shift

case "${command_name}" in
  prepare)
    "${script_dir}/prepare-k3s-config.sh" "$@"
    ;;
  install)
    [[ $# -eq 0 ]] || fail "install does not accept extra arguments."
    "${script_dir}/install-k3s.sh"
    ;;
  verify)
    [[ $# -eq 0 ]] || fail "verify does not accept extra arguments."
    "${script_dir}/verify-k3s.sh"
    ;;
  all)
    "${script_dir}/prepare-k3s-config.sh" --force "$@"
    "${script_dir}/install-k3s.sh"
    "${script_dir}/verify-k3s.sh"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    fail "Unknown command: ${command_name}"
    ;;
esac
