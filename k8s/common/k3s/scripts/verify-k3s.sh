#!/usr/bin/env bash
set -euo pipefail

ok_count=0
warn_count=0
fail_count=0

usage() {
  cat <<'USAGE'
Usage: verify-k3s.sh

Read-only verification of the common single-node k3s baseline.

Options:
  -h, --help  Show this help.
USAGE
}

section() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  ok_count=$((ok_count + 1))
  echo "OK: $*"
}

warn() {
  warn_count=$((warn_count + 1))
  echo "WARN: $*"
}

fail_check() {
  fail_count=$((fail_count + 1))
  echo "FAIL: $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
k3s_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_file="${k3s_dir}/dependencies.lock.json"
source_config="${k3s_dir}/config.yaml"
target_config="/etc/rancher/k3s/config.yaml"
kubeconfig="/etc/rancher/k3s/k3s.yaml"
expected_node_name="$(hostname)"

command -v jq >/dev/null 2>&1 || fail "jq is required to read ${lock_file}."
[[ -f "${lock_file}" ]] || fail "Missing dependency lock: ${lock_file}"
expected_k3s_version="$(jq -r '.platform.k3s.version // empty' "${lock_file}")"
[[ -n "${expected_k3s_version}" && "${expected_k3s_version}" != "null" && "${expected_k3s_version}" != "live-check-required" ]] || fail "Pinned k3s version is missing from ${lock_file}."

kubectl() {
  k3s kubectl "$@"
}

check_k3s_binary_and_service() {
  local installed_version
  section "k3s binary and service"

  if command -v k3s >/dev/null 2>&1; then
    ok "k3s command is installed."
    installed_version="$(k3s --version | awk 'NR == 1 { print $3 }')"
    if [[ "${installed_version}" == "${expected_k3s_version}" ]]; then
      ok "k3s version is ${expected_k3s_version}."
    else
      fail_check "k3s version is ${installed_version:-unknown}; expected ${expected_k3s_version}."
    fi
  else
    fail_check "k3s command is not installed."
    return
  fi

  if systemctl is-active --quiet k3s.service 2>/dev/null; then
    ok "k3s service is active."
  else
    fail_check "k3s service is not active."
  fi
}

check_config_files() {
  local kubeconfig_mode
  section "k3s configuration"

  if [[ -f "${target_config}" ]]; then
    ok "${target_config} exists."
    if cmp -s "${source_config}" "${target_config}"; then
      ok "${target_config} matches common k3s config."
    else
      fail_check "${target_config} differs from common k3s config."
    fi
  else
    fail_check "missing ${target_config}."
  fi

  if [[ -f "${kubeconfig}" ]]; then
    ok "${kubeconfig} exists."
    kubeconfig_mode="$(stat -c '%a' "${kubeconfig}")"
    if [[ "${kubeconfig_mode}" == "600" ]]; then
      ok "${kubeconfig} mode is 0600."
    else
      fail_check "${kubeconfig} mode is ${kubeconfig_mode}; expected 0600."
    fi
  else
    fail_check "missing kubeconfig: ${kubeconfig}."
  fi
}

check_node() {
  local node_count
  local node_names
  local ready_status
  section "Node"

  node_names="$(kubectl get nodes --no-headers 2>/dev/null | awk '{ print $1 }')"
  node_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"${node_names}")"

  if [[ "${node_count}" == "1" ]]; then
    ok "exactly one k3s node is registered."
  else
    fail_check "expected exactly one k3s node, found ${node_count}."
  fi

  if [[ "${node_names}" == "${expected_node_name}" ]]; then
    ok "node name matches host hostname: ${expected_node_name}."
  else
    fail_check "node name is ${node_names:-unknown}; expected host hostname ${expected_node_name}."
  fi

  ready_status="$(kubectl get node "${expected_node_name}" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "${ready_status}" == "True" ]]; then
    ok "node ${expected_node_name} is Ready."
  else
    fail_check "node ${expected_node_name} is not Ready."
  fi
}

check_system_workloads() {
  section "System workloads"

  if kubectl -n kube-system rollout status deployment/coredns --timeout=1s >/dev/null 2>&1; then
    ok "CoreDNS deployment is running."
  else
    fail_check "CoreDNS deployment is not running."
  fi

  if kubectl -n kube-system rollout status deployment/local-path-provisioner --timeout=1s >/dev/null 2>&1; then
    ok "local-path-provisioner deployment is running."
  else
    fail_check "local-path-provisioner deployment is not running."
  fi
}

check_disabled_embedded_components() {
  local embedded_traefik_resources
  local servicelb_resources
  section "Disabled embedded components"

  embedded_traefik_resources="$(kubectl get all -n kube-system --no-headers 2>/dev/null | awk 'tolower($1) ~ /traefik/ { print $1 }')"
  if [[ -z "${embedded_traefik_resources}" ]]; then
    ok "embedded k3s Traefik is absent."
  else
    fail_check "embedded k3s Traefik resources exist in kube-system."
  fi

  servicelb_resources="$(kubectl get daemonset,deploy,pods,svc -A --no-headers 2>/dev/null | awk 'tolower($0) ~ /servicelb|klipper-lb/ { print $1 }')"
  if [[ -z "${servicelb_resources}" ]]; then
    ok "ServiceLB resources are absent."
  else
    fail_check "ServiceLB resources exist."
  fi
}

check_secrets_encryption() {
  local secrets_encryption_status
  section "Secrets encryption"

  secrets_encryption_status="$(k3s secrets-encrypt status 2>&1 || true)"
  echo "${secrets_encryption_status}"

  if grep -qi 'enabled' <<<"${secrets_encryption_status}"; then
    ok "k3s secrets encryption is enabled."
  else
    fail_check "k3s secrets encryption is not enabled."
  fi
}

check_listening_ports() {
  section "Listening ports"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp | awk 'NR == 1 || $4 ~ /(:6443)$/ || $4 ~ /(:6443)[[:space:]]/'
    ok "displayed k3s API listener state."
  else
    warn "ss is not available; skipping listening port display."
  fi
}

check_k3s_binary_and_service
check_config_files

if command -v k3s >/dev/null 2>&1 && [[ -f "${kubeconfig}" ]]; then
  check_node
  check_system_workloads
  check_disabled_embedded_components
  check_secrets_encryption
  check_listening_ports
else
  warn "skipping cluster checks because k3s or kubeconfig is unavailable."
fi

section "Summary"
echo "OK: ${ok_count}"
echo "WARN: ${warn_count}"
echo "FAIL: ${fail_count}"

if [[ "${fail_count}" -gt 0 ]]; then
  exit 1
fi
