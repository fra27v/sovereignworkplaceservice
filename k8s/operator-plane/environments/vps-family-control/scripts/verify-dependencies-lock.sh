#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_file="${env_dir}/dependencies.lock.json"

summary_ok=0
summary_warn=0
summary_fail=0

usage() {
  cat <<'USAGE'
Usage:
  verify-dependencies-lock.sh [--lock-file <path>] [--help]

Static jq-based verification for vps-family-control dependencies.lock.json.

The verifier does not mutate Kubernetes state, pull images, run Jobs or Pods,
or read secrets.

Options:
  --lock-file <path>  Dependency lock JSON file to verify.
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

jq_bool_is_true() {
  local path="$1"
  jq -e "${path} == true" "${lock_file}" >/dev/null
}

jq_type_is() {
  local path="$1"
  local expected="$2"
  jq -e "(${path} | type) == \"${expected}\"" "${lock_file}" >/dev/null
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

is_floating_tag() {
  local tag="$1"

  case "${tag}" in
    stable|stable-alpine|edge|main|master|nightly|rolling)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_required_fields() {
  local field

  for field in schemaVersion environment lastReviewed policy platform managedComponents helmReleases runtimeImages hostTools; do
    if jq -e --arg field "${field}" 'has($field)' "${lock_file}" >/dev/null; then
      ok "Top-level field exists: ${field}"
    else
      fail "Missing top-level field: ${field}"
    fi
  done
}

validate_array_fields() {
  local field

  for field in managedComponents helmReleases runtimeImages hostTools; do
    if jq_type_is ".${field}" "array"; then
      ok "Field is an array: ${field}"
    else
      fail "Field must be an array: ${field}"
    fi
  done
}

validate_policy() {
  local field

  for field in rejectLatest noRuntimePackageInstall updatesRequireGitCommit vpsRunsOnlyGitState; do
    if jq_bool_is_true ".policy.${field}"; then
      ok "Policy ${field} is true"
    else
      fail "Policy ${field} must be true"
    fi
  done
}

validate_digest() {
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

validate_runtime_image() {
  local json="$1"
  local id image status update_flow digest tag

  id="$(jq -r '.id // ""' <<< "${json}")"
  image="$(jq -r '.image // ""' <<< "${json}")"
  status="$(jq -r '.status // ""' <<< "${json}")"
  update_flow="$(jq -r '.updateFlow // ""' <<< "${json}")"
  digest="$(jq -r '.digest // "null"' <<< "${json}")"

  if [[ -z "${id}" ]]; then
    fail "Runtime image entry is missing id"
    return 0
  fi

  if [[ -z "${image}" || -z "${status}" || -z "${update_flow}" ]]; then
    fail "Runtime image ${id} must include image, status, and updateFlow"
    return 0
  fi

  tag="$(image_tag "${image}")"

  if [[ "${tag}" = "latest" ]]; then
    fail "Runtime image ${id} uses forbidden :latest tag: ${image}"
  elif [[ -n "${tag}" ]] && is_floating_tag "${tag}"; then
    if [[ "${status}" = "needs-pinning" ]]; then
      warn "Runtime image ${id} uses floating tag and is marked needs-pinning: ${image}"
    else
      fail "Runtime image ${id} uses floating tag without needs-pinning status: ${image}"
    fi
  elif [[ -z "${tag}" && "${image}" != *@sha256:* ]]; then
    if [[ "${update_flow}" = "helm-managed" && "${status}" = "helm-app-version" ]]; then
      ok "Runtime image ${id} is helm app-version managed without explicit image digest"
    else
      fail "Runtime image ${id} has no explicit tag or digest: ${image}"
    fi
  elif [[ "${status}" = "helm-app-version" && "${update_flow}" = "helm-managed" && ( -z "${digest}" || "${digest}" = "null" ) ]]; then
    ok "Runtime image ${id} is helm app-version managed without digest: ${image}"
  elif [[ "${status}" = "candidate" && ( -z "${digest}" || "${digest}" = "null" ) ]]; then
    warn "Candidate runtime image ${id} has no digest yet: ${image}"
  else
    ok "Runtime image ${id} is pinned or acceptable: ${image}"
  fi

  validate_digest "${id}" "${digest}"
}

validate_runtime_images() {
  local count index image_json

  count="$(jq '.runtimeImages | length' "${lock_file}")"
  if [[ "${count}" -eq 0 ]]; then
    fail "runtimeImages must not be empty"
    return 0
  fi

  for ((index = 0; index < count; index += 1)); do
    image_json="$(jq -c ".runtimeImages[${index}]" "${lock_file}")"
    validate_runtime_image "${image_json}"
  done
}

validate_host_tools() {
  local count index tool_name required

  count="$(jq '.hostTools | length' "${lock_file}")"
  if [[ "${count}" -eq 0 ]]; then
    fail "hostTools must not be empty"
    return 0
  fi

  for ((index = 0; index < count; index += 1)); do
    tool_name="$(jq -r ".hostTools[${index}].name // \"\"" "${lock_file}")"
    required="$(jq -r ".hostTools[${index}].required // false" "${lock_file}")"
    if [[ "${required}" = "true" && -n "${tool_name}" ]]; then
      ok "Required host tool is declared: ${tool_name}"
    elif [[ "${required}" = "true" ]]; then
      fail "Required host tool entry at index ${index} has empty name"
    else
      warn "Host tool entry is not marked required: ${tool_name:-index ${index}}"
    fi
  done
}

validate_helm_releases() {
  local count

  count="$(jq '.helmReleases | length' "${lock_file}")"
  if [[ "${count}" -gt 0 ]]; then
    ok "Helm release entries declared: ${count}"
  else
    fail "helmReleases must not be empty"
  fi
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

require_command jq

if [[ ! -f "${lock_file}" ]]; then
  echo "FAIL: Missing dependency lock file: ${lock_file}" >&2
  exit 1
fi

if jq . "${lock_file}" >/dev/null; then
  ok "Dependency lock is valid JSON: ${lock_file}"
else
  echo "FAIL: Dependency lock is not valid JSON: ${lock_file}" >&2
  exit 1
fi

validate_required_fields
validate_array_fields
validate_policy
validate_helm_releases
validate_runtime_images
validate_host_tools

echo
echo "Dependency lock verification summary:"
echo "  OK: ${summary_ok}"
echo "  WARN: ${summary_warn}"
echo "  FAIL: ${summary_fail}"

if [[ "${summary_fail}" -gt 0 ]]; then
  exit 1
fi
