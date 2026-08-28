#!/usr/bin/env bash
set -euo pipefail

openbao_component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd -- "${openbao_component_dir}/../../.." && pwd)"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

yaml_value() {
  local file="$1"
  local path="$2"

  awk -v wanted="${path}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function unquote(value) {
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
        value = substr(value, 2, length(value) - 2)
      }
      return value
    }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      indent = match($0, /[^ ]/) - 1
      level = int(indent / 2) + 1
      line = $0
      sub(/^[[:space:]]*/, "", line)
      split(line, pair, ":")
      key = trim(pair[1])
      value = substr(line, length(pair[1]) + 2)
      value = trim(value)
      keys[level] = key
      for (i = level + 1; i <= 16; i++) {
        keys[i] = ""
      }
      current = keys[1]
      for (i = 2; i <= level; i++) {
        if (keys[i] != "") {
          current = current "." keys[i]
        }
      }
      if (current == wanted && value != "") {
        print unquote(value)
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "${file}"
}

require_yaml_value() {
  local file="$1"
  local path="$2"
  local value

  value="$(yaml_value "${file}" "${path}")" || fail "Missing YAML value: ${path} in ${file}"
  [[ -n "${value}" ]] || fail "Empty YAML value: ${path} in ${file}"
  printf '%s' "${value}"
}

resolve_tenant_file() {
  local tenant="${1:-family-infra}"
  printf '%s/k8s/tenants/%s/tenant.yaml' "${repo_root}" "${tenant}"
}

resolve_release_file() {
  local release="$1"
  printf '%s/releases/%s/release.yaml' "${openbao_component_dir}" "${release}"
}

resolve_release_image() {
  local release_file="$1"
  local repository version digest

  repository="$(require_yaml_value "${release_file}" "runtime.image.repository")"
  version="$(require_yaml_value "${release_file}" "runtime.image.version")"
  digest="$(require_yaml_value "${release_file}" "runtime.image.digest")"
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Release image digest is not a sha256 digest: ${digest}"
  printf '%s:%s@%s' "${repository}" "${version}" "${digest}"
}

indent_file() {
  local file="$1"
  sed 's/^/    /' "${file}"
}
