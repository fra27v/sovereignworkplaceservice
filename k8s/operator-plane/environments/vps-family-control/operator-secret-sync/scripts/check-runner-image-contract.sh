#!/usr/bin/env bash
set -euo pipefail

image_ref=""
dry_run="false"

usage() {
  cat <<EOF
Usage: $0 --image <image-ref> [--dry-run]

Check that a candidate standard runner image satisfies the operator-secret-sync
tooling contract.

Options:
  --image <image-ref>  Candidate image reference to check.
  --dry-run            Print safe metadata only; do not pull or run the image.
  --help               Show this help.

This script does not require secrets and does not print secret material.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

reject_latest() {
  local ref="$1"

  case "${ref}" in
    *:latest|*:latest@*)
      fail "Image references using :latest are forbidden."
      ;;
  esac

  if [[ "${ref}" != *@sha256:* && "${ref}" != *:* ]]; then
    fail "Image reference must be pinned by tag or digest."
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --image)
      [[ "$#" -ge 2 ]] || fail "Missing value for --image."
      image_ref="$2"
      shift
      ;;
    --dry-run)
      dry_run="true"
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

[[ -n "${image_ref}" ]] || fail "Missing required --image <image-ref>."
reject_latest "${image_ref}"

echo "Runner image candidate: ${image_ref}"
echo "Required commands: bash curl jq kubectl openssl"
echo "Required data: CA certificates"
echo "Required hash method: openssl passwd -apr1 -stdin or equivalent"

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: image was not pulled or run."
  exit 0
fi

require_command docker

docker run --rm --entrypoint /bin/sh "${image_ref}" -c '
  set -eu
  for command_name in bash curl jq kubectl openssl; do
    command -v "${command_name}" >/dev/null 2>&1
  done
  test -d /etc/ssl/certs
  printf "%s\n" "probe" | openssl passwd -apr1 -stdin >/dev/null
'

echo "Runner image contract check passed."
