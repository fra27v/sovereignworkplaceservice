#!/usr/bin/env bash

resolve_operator_artifacts_image() {
  local lock_file="$1"
  local runtime_image_id="${2:-operator-artifacts-nginx}"
  local image digest effective_image

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
  effective_image="$(jq -er --arg id "${runtime_image_id}" '.runtimeImages[] | select(.id == $id) | .effectiveImage // empty' "${lock_file}")" || {
    effective_image=""
  }

  [[ -n "${image}" ]] || {
    echo "ERROR: Runtime image is empty in lock for ${runtime_image_id}" >&2
    return 1
  }
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "ERROR: Runtime image digest must match sha256:<64 lowercase hex>: ${runtime_image_id}" >&2
    return 1
  }

  case "${image}" in
    *:latest|*:latest@*)
      echo "ERROR: Runtime image uses forbidden :latest tag: ${runtime_image_id}" >&2
      return 1
      ;;
    *@sha256:*)
      [[ "${image}" == *"@${digest}" ]] || {
        echo "ERROR: Runtime image digest does not match digest field for ${runtime_image_id}" >&2
        return 1
      }
      ;;
    *)
      image="${image}@${digest}"
      ;;
  esac

  if [[ -n "${effective_image}" && "${effective_image}" != "${image}" ]]; then
    echo "ERROR: effectiveImage does not match resolved image for ${runtime_image_id}" >&2
    return 1
  fi

  printf '%s\n' "${image}"
}
