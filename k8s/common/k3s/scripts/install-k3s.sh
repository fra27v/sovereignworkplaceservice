#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install-k3s.sh

Install the pinned k3s version from k8s/common/k3s/dependencies.lock.json.

Options:
  -h, --help  Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
k3s_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_file="${k3s_dir}/dependencies.lock.json"
config_file="/etc/rancher/k3s/config.yaml"

[[ -f "${config_file}" ]] || fail "Missing ${config_file}. Run prepare-k3s-config.sh first."
[[ -f "${lock_file}" ]] || fail "Missing dependency lock: ${lock_file}"

command -v curl >/dev/null 2>&1 || fail "curl is required to install k3s."
command -v jq >/dev/null 2>&1 || fail "jq is required to read ${lock_file}."

k3s_version="$(jq -r '.platform.k3s.version // empty' "${lock_file}")"
[[ -n "${k3s_version}" && "${k3s_version}" != "null" && "${k3s_version}" != "live-check-required" ]] || fail "Pinned k3s version is missing from ${lock_file}."

if command -v k3s >/dev/null 2>&1; then
  installed_version="$(k3s --version | awk 'NR == 1 { print $3 }')"
  if [[ "${installed_version}" == "${k3s_version}" ]]; then
    echo "k3s ${k3s_version} is already installed."
    exit 0
  fi
  fail "k3s ${installed_version:-unknown} is installed, but ${k3s_version} is pinned."
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" sh -
