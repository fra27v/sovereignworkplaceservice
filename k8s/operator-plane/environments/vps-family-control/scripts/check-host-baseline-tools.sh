#!/usr/bin/env bash
set -euo pipefail

missing_count=0
version_file="/tmp/check-host-baseline-tools.version"
trap 'rm -f "${version_file}"' EXIT

print_status() {
  local command_name="$1"
  shift

  if command -v "${command_name}" >/dev/null 2>&1; then
    echo "OK: ${command_name}"
    if "$@" >"${version_file}" 2>&1; then
      sed 's/^/  /' "${version_file}"
    else
      echo "  Version output is not supported or failed."
    fi
    rm -f "${version_file}"
  else
    echo "MISSING: ${command_name}"
    missing_count=$((missing_count + 1))
  fi
}

echo "Checking required host baseline commands."
print_status kubectl kubectl version --client
print_status helm helm version --short
print_status jq jq --version
print_status openssl openssl version
print_status curl sh -c 'curl --version | head -n 1'
print_status git git --version
print_status htpasswd bash -c 'if htpasswd -v >/dev/null 2>&1; then htpasswd -v; else echo "htpasswd is installed; version output is not supported by this build."; fi'

if [[ "${missing_count}" -gt 0 ]]; then
  echo "Missing required commands: ${missing_count}" >&2
  exit 1
fi

echo "All required host baseline commands are available."
