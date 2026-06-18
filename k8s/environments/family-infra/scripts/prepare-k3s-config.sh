#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: prepare-k3s-config.sh [--force]

Copy k3s-config.yaml.example to /etc/rancher/k3s/config.yaml.

Options:
  --force   Overwrite an existing target config file.
  -h, --help
            Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=true
      shift
      ;;
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
environment_dir="$(cd -- "${script_dir}/.." && pwd)"
source_config="${environment_dir}/k3s-config.yaml.example"
target_dir="/etc/rancher/k3s"
target_config="${target_dir}/config.yaml"

[[ -f "${source_config}" ]] || fail "Source config not found: ${source_config}"

if [[ -e "${target_config}" && "${force}" != true ]]; then
  fail "${target_config} already exists. Re-run with --force to overwrite it."
fi

install -d -m 0755 "${target_dir}"
install -o root -g root -m 0600 "${source_config}" "${target_config}"

echo "Installed ${target_config} with owner root:root and mode 0600."
