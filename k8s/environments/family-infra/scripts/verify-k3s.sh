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

command -v k3s >/dev/null 2>&1 || fail "k3s is not installed."

kubeconfig="/etc/rancher/k3s/k3s.yaml"
[[ -f "${kubeconfig}" ]] || fail "Missing kubeconfig: ${kubeconfig}"

section "k3s version"
k3s --version

section "Nodes"
k3s kubectl get nodes -o wide

not_ready_nodes="$(k3s kubectl get nodes --no-headers | awk '$2 !~ /Ready/ { print $1 " " $2 }')"
if [[ -n "${not_ready_nodes}" ]]; then
  echo "${not_ready_nodes}" >&2
  fail "One or more nodes are not Ready."
fi

section "Pods"
k3s kubectl get pods -A -o wide

if k3s kubectl get all -A --no-headers 2>/dev/null | awk '{ print tolower($0) }' | grep -q 'traefik'; then
  fail "Traefik resources exist, but embedded k3s Traefik must be disabled."
fi

section "Secrets encryption"
secrets_encryption_status="$(k3s secrets-encrypt status 2>&1)"
echo "${secrets_encryption_status}"

if ! grep -qi 'enabled' <<<"${secrets_encryption_status}"; then
  fail "k3s secrets encryption is not enabled."
fi

section "Kubeconfig permissions"
kubeconfig_mode="$(stat -c '%a' "${kubeconfig}")"
ls -l "${kubeconfig}"
echo "mode=${kubeconfig_mode}"

if [[ "${kubeconfig_mode}" != "600" ]]; then
  fail "${kubeconfig} must have mode 600."
fi

section "Listening ports"
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | awk 'NR == 1 || $4 ~ /(:80|:443|:6443)$/ || $4 ~ /(:80|:443|:6443)[[:space:]]/'
else
  echo "ss is not available; skipping listening port display."
fi

echo
echo "family-infra k3s baseline verification passed."
