#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_file="${env_dir}/dependencies.lock.yaml"

summary_ok=0
summary_warn=0
summary_fail=0

usage() {
  cat <<'USAGE'
Usage:
  verify-dependencies-lock.sh [--lock-file <path>] [--help]

Static verification for vps-family-control dependencies.lock.yaml.

The verifier does not mutate Kubernetes state, pull images, run Jobs, or read
secrets.

Options:
  --lock-file <path>  Dependency lock file to verify.
  --help              Show this help.
USAGE
}

ok() {
  summary_ok=$((summary_ok + 1))
  echo "OK: $*"
}

warn() {
  summary_warn=$((summary_warn + 1))
  echo "WARN: $*" >&2
}

fail() {
  summary_fail=$((summary_fail + 1))
  echo "FAIL: $*" >&2
}

require_command() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || {
    echo "FAIL: Missing required command: ${name}" >&2
    exit 1
  }
}

is_floating_tag() {
  local tag="$1"

  case "${tag}" in
    latest|stable|stable-alpine|edge|main|master|dev|nightly)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

image_tag() {
  local image="$1"
  local without_digest last_component

  without_digest="${image%@*}"
  last_component="${without_digest##*/}"
  if [[ "${last_component}" == *:* ]]; then
    printf '%s' "${last_component##*:}"
  else
    printf ''
  fi
}

check_digest() {
  local id="$1"
  local digest="$2"

  if [[ -z "${digest}" || "${digest}" = "null" ]]; then
    return 0
  fi

  if [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    ok "Digest format is valid for ${id}"
  else
    fail "Malformed digest for ${id}: ${digest}"
  fi
}

check_image_record() {
  local id="$1"
  local image="$2"
  local status="$3"
  local digest="$4"
  local tag

  if [[ -z "${id}" || -z "${image}" ]]; then
    fail "Malformed runtime image record with missing id or image"
    return 0
  fi

  tag="$(image_tag "${image}")"
  if [[ "${tag}" = "latest" ]]; then
    fail "Image ${id} uses forbidden :latest tag: ${image}"
  elif [[ -n "${tag}" ]] && is_floating_tag "${tag}"; then
    if [[ "${status}" = "needs-pinning" ]]; then
      warn "Image ${id} uses floating tag and is marked needs-pinning: ${image}"
    else
      fail "Image ${id} uses floating tag without needs-pinning status: ${image}"
    fi
  elif [[ "${status}" = "candidate" && ( -z "${digest}" || "${digest}" = "null" ) ]]; then
    warn "Candidate image ${id} has no digest yet: ${image}"
  elif [[ -z "${tag}" && "${image}" != *@sha256:* ]]; then
    fail "Image ${id} has neither a tag nor digest: ${image}"
  else
    ok "Image ${id} is pinned or acceptable: ${image}"
  fi

  check_digest "${id}" "${digest}"
}

verify_runtime_images() {
  local in_images="false"
  local id="" image="" status="" digest=""
  local line trimmed value

  flush_record() {
    if [[ -n "${id}${image}${status}${digest}" ]]; then
      check_image_record "${id}" "${image}" "${status}" "${digest}"
    fi
    id=""
    image=""
    status=""
    digest=""
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"

    if [[ "${trimmed}" = "runtime_images:" ]]; then
      in_images="true"
      continue
    fi

    if [[ "${in_images}" = "true" && "${line}" =~ ^[^[:space:]] && "${trimmed}" != "runtime_images:" ]]; then
      flush_record
      in_images="false"
    fi

    [[ "${in_images}" = "true" ]] || continue

    if [[ "${trimmed}" == "- id:"* ]]; then
      flush_record
      value="${trimmed#- id:}"
      id="${value#"${value%%[![:space:]]*}"}"
      id="${id%\"}"
      id="${id#\"}"
    elif [[ "${trimmed}" == "image:"* ]]; then
      value="${trimmed#image:}"
      image="${value#"${value%%[![:space:]]*}"}"
      image="${image%\"}"
      image="${image#\"}"
    elif [[ "${trimmed}" == "status:"* ]]; then
      value="${trimmed#status:}"
      status="${value#"${value%%[![:space:]]*}"}"
      status="${status%\"}"
      status="${status#\"}"
    elif [[ "${trimmed}" == "digest:"* ]]; then
      value="${trimmed#digest:}"
      digest="${value#"${value%%[![:space:]]*}"}"
      digest="${digest%\"}"
      digest="${digest#\"}"
    fi
  done < "${lock_file}"

  flush_record
}

verify_required_sections() {
  local section

  for section in schema_version environment platform helm_releases runtime_images host_tools; do
    if grep -Eq "^${section}:" "${lock_file}"; then
      ok "Lock contains section: ${section}"
    else
      fail "Lock is missing required section: ${section}"
    fi
  done
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --lock-file)
      [[ "$#" -ge 2 ]] || {
        echo "--lock-file requires a path." >&2
        exit 1
      }
      lock_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command grep
[[ -f "${lock_file}" ]] || {
  echo "FAIL: Missing dependency lock file: ${lock_file}" >&2
  exit 1
}

verify_required_sections
verify_runtime_images

echo
echo "Dependency lock verification summary:"
echo "  OK: ${summary_ok}"
echo "  WARN: ${summary_warn}"
echo "  FAIL: ${summary_fail}"

if [[ "${summary_fail}" -gt 0 ]]; then
  exit 1
fi
