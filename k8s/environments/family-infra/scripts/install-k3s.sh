#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

config_file="/etc/rancher/k3s/config.yaml"

[[ -f "${config_file}" ]] || fail "Missing ${config_file}. Run prepare-k3s-config.sh first."

if command -v k3s >/dev/null 2>&1; then
  echo "k3s is already installed:"
  k3s --version
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

command -v curl >/dev/null 2>&1 || fail "curl is required to install k3s."

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -
