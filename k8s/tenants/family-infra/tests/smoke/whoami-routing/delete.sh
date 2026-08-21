#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
smoke_test_dir="${script_dir}/manifests"
kubeconfig="/etc/rancher/k3s/k3s.yaml"

[[ -d "${repo_root}" ]] || fail "Could not determine repository root."
[[ -f "${kubeconfig}" ]] || fail "Missing kubeconfig: ${kubeconfig}"
[[ -f "${smoke_test_dir}/kustomization.yaml" ]] || fail "Missing smoke test kustomization: ${smoke_test_dir}"
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed."

export KUBECONFIG="${kubeconfig}"

kubectl delete -k "${smoke_test_dir}"
