#!/usr/bin/env bash
set -euo pipefail

image_ref=""

usage() {
  cat <<EOF
Usage: $0 --image <image>

Resolve RepoDigest candidates through k3s/containerd tooling.

Options:
  --image <image>  Image reference to pull and inspect.
  --help           Show this help.

This helper does not edit dependencies.lock.json. After review, manually copy
the selected sha256 digest into dependencies.lock.json.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --image)
      [[ "$#" -ge 2 ]] || fail "Missing value for --image."
      image_ref="$2"
      shift
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

[[ -n "${image_ref}" ]] || fail "Missing required --image <image>."
require_command sudo
require_command jq

echo "Image: ${image_ref}"
echo "+ sudo k3s crictl pull ${image_ref}"
sudo k3s crictl pull "${image_ref}" >/dev/null

echo "RepoDigest candidates:"
sudo k3s crictl inspecti "${image_ref}" \
  | jq -r '
      [
        (.status.repoDigests // []),
        (.info.imageSpec.repoDigests // [])
      ]
      | flatten
      | unique
      | .[]
    '

cat <<'EOF'

Review the selected RepoDigest, then manually copy the sha256 digest into
dependencies.lock.json. This helper does not modify repository files.
EOF
