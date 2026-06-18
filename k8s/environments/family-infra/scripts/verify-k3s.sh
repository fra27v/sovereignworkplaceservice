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

section "Embedded k3s Traefik"
embedded_traefik_resources=""

kube_system_traefik_pods="$(k3s kubectl get pods -n kube-system --no-headers 2>/dev/null | awk 'tolower($1) ~ /traefik/ { print "pod/" $1 }')"
if [[ -n "${kube_system_traefik_pods}" ]]; then
  embedded_traefik_resources+="${kube_system_traefik_pods}"$'\n'
fi

kube_system_traefik_services="$(k3s kubectl get services -n kube-system --no-headers 2>/dev/null | awk 'tolower($1) ~ /traefik/ { print "service/" $1 }')"
if [[ -n "${kube_system_traefik_services}" ]]; then
  embedded_traefik_resources+="${kube_system_traefik_services}"$'\n'
fi

if k3s kubectl get crd helmcharts.helm.cattle.io >/dev/null 2>&1; then
  kube_system_traefik_helmcharts="$(k3s kubectl get helmchart.helm.cattle.io -n kube-system traefik --ignore-not-found -o name 2>/dev/null)"
  if [[ -n "${kube_system_traefik_helmcharts}" ]]; then
    embedded_traefik_resources+="${kube_system_traefik_helmcharts}"$'\n'
  fi
fi

if [[ -n "${embedded_traefik_resources}" ]]; then
  echo "${embedded_traefik_resources}" >&2
  fail "Embedded k3s Traefik resources exist in kube-system, but embedded k3s Traefik must be disabled."
fi

echo "embedded k3s Traefik is absent"

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
