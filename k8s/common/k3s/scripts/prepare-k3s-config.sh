#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: prepare-k3s-config.sh [--force] [--dry-run]

Install k8s/common/k3s/config.yaml to /etc/rancher/k3s/config.yaml.

Options:
  --force    Overwrite an existing divergent target config file.
  --dry-run  Show planned changes without writing files.
  -h, --help
             Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

force=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=true
      shift
      ;;
    --dry-run)
      dry_run=true
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

if [[ "${dry_run}" == false && "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
k3s_dir="$(cd -- "${script_dir}/.." && pwd)"
source_config="${k3s_dir}/config.yaml"
target_dir="/etc/rancher/k3s"
target_config="${target_dir}/config.yaml"

[[ -f "${source_config}" ]] || fail "Source config not found: ${source_config}"

if [[ -f "${target_config}" ]] && cmp -s "${source_config}" "${target_config}"; then
  echo "${target_config} already matches ${source_config}."
  exit 0
fi

if [[ -e "${target_config}" && "${force}" != true ]]; then
  fail "${target_config} exists and differs from ${source_config}. Re-run with --force to overwrite it."
fi

if [[ "${dry_run}" == true ]]; then
  echo "DRY-RUN: would install ${source_config} to ${target_config} with owner root:root and mode 0600."
  exit 0
fi

install -d -m 0755 "${target_dir}"
tmp="$(mktemp "${target_dir}/.config.yaml.XXXXXX")"
install -o root -g root -m 0600 "${source_config}" "${tmp}"
mv "${tmp}" "${target_config}"

echo "Installed ${target_config} with owner root:root and mode 0600."
