#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
smoke_test_dir="${script_dir}/manifests"
kubeconfig="/etc/rancher/k3s/k3s.yaml"
namespace="smoke-whoami"
deployment="whoami"
service="whoami"
ingress="whoami"
host="whoami.internal"

[[ -d "${repo_root}" ]] || fail "Could not determine repository root."
[[ -f "${smoke_test_dir}/kustomization.yaml" ]] || fail "Missing smoke test kustomization: ${smoke_test_dir}"
[[ -f "${kubeconfig}" ]] || fail "Missing kubeconfig: ${kubeconfig}"
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed."
command -v curl >/dev/null 2>&1 || fail "curl is not installed."

export KUBECONFIG="${kubeconfig}"

kubectl rollout status deployment/"${deployment}" -n "${namespace}" --timeout=120s

section "Pods"
kubectl get pods -n "${namespace}" -o wide

section "Service"
kubectl get service "${service}" -n "${namespace}" -o wide

section "Ingress"
kubectl get ingress "${ingress}" -n "${namespace}" -o wide

section "Routing"
response="$(curl -sS -H "Host: ${host}" http://127.0.0.1/)"
echo "${response}"

if ! grep -q 'Hostname:' <<<"${response}"; then
  fail "Smoke test response did not contain Hostname:."
fi

echo
echo "whoami Traefik smoke test verification passed."
