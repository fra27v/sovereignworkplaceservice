#!/usr/bin/env bash

resolve_operator_secret_sync_runner_image() {
  local lock_file="$1"
  local runtime_image_id="${2:-operator-secret-sync-runner-candidate}"
  local image digest

  [[ -f "${lock_file}" ]] || {
    echo "ERROR: Missing dependency lock file: ${lock_file}" >&2
    return 1
  }

  image="$(jq -er --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id) | .image // empty' "${lock_file}")" || {
    echo "ERROR: Runtime image entry not found in lock: ${runtime_image_id}" >&2
    return 1
  }
  digest="$(jq -er --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id) | .digest // empty' "${lock_file}")" || {
    echo "ERROR: Runtime image digest is missing in lock for ${runtime_image_id}" >&2
    return 1
  }

  [[ -n "${image}" ]] || {
    echo "ERROR: Runtime image is empty in lock for ${runtime_image_id}" >&2
    return 1
  }
  [[ -n "${digest}" ]] || {
    echo "ERROR: Runtime image digest is empty in lock for ${runtime_image_id}" >&2
    return 1
  }
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "ERROR: Runtime image digest must match sha256:<64 lowercase hex>: ${runtime_image_id}" >&2
    return 1
  }

  local old_placeholder_prefix="REPLACE-WITH-"
  old_placeholder_prefix+="PINNED-STANDARD-RUNNER-IMAGE"

  case "${image}" in
    *:latest|*:latest@*)
      echo "ERROR: Runtime image uses forbidden :latest tag: ${runtime_image_id}" >&2
      return 1
      ;;
    "${old_placeholder_prefix}":*)
      echo "ERROR: Runtime image still uses the old placeholder: ${runtime_image_id}" >&2
      return 1
      ;;
  esac

  printf '%s@%s\n' "${image}" "${digest}"
}
