#!/usr/bin/env bash
set -euo pipefail

ok_count=0
warn_count=0
fail_count=0
convergence_timeout_seconds=300
poll_interval_seconds=5
convergence_deadline=$((SECONDS + convergence_timeout_seconds))

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

remaining_convergence_seconds() {
  local remaining

  remaining=$((convergence_deadline - SECONDS))
  if [[ "${remaining}" -lt 0 ]]; then
    remaining=0
  fi

  echo "${remaining}"
}

wait_until() {
  local description="$1"
  shift

  while [[ "$(remaining_convergence_seconds)" -gt 0 ]]; do
    if "$@"; then
      return 0
    fi
    sleep "${poll_interval_seconds}"
  done

  if "$@"; then
    return 0
  fi

  echo "Timed out waiting for ${description} after ${convergence_timeout_seconds}s." >&2
  return 1
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
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

get_prefixed_resource_names() {
  local namespace="$1"
  local resource_type="$2"
  local prefix="$3"
  local line
  local resource_names

  resource_names="$(kubectl -n "${namespace}" get "${resource_type}" -o name 2>/dev/null || true)"
  while IFS= read -r line; do
    if [[ "${line}" == "${prefix}"* ]]; then
      printf '%s\n' "${line}"
    fi
  done <<<"${resource_names}"
}

check_k3s_binary_and_service() {
  local installed_version
  local version_output
  section "k3s binary and service"

  if command -v k3s >/dev/null 2>&1; then
    ok "k3s command is installed."
    version_output="$(k3s --version 2>/dev/null || true)"
    installed_version="$(awk 'NR == 1 { print $3 }' <<<"${version_output}")"
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
  local nodes_output
  local ready_status
  section "Node"

  nodes_output="$(kubectl get nodes --no-headers 2>/dev/null || true)"
  node_names="$(awk '{ print $1 }' <<<"${nodes_output}")"
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

traefik_helmchart_exists() {
  kubectl -n kube-system get helmchart.helm.cattle.io traefik >/dev/null 2>&1
}

traefik_deployment_ready() {
  local available_status
  local desired_replicas
  local ready_replicas

  available_status="$(kubectl -n kube-system get deployment.apps/traefik -o 'jsonpath={.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
  desired_replicas="$(kubectl -n kube-system get deployment.apps/traefik -o 'jsonpath={.spec.replicas}' 2>/dev/null || true)"
  ready_replicas="$(kubectl -n kube-system get deployment.apps/traefik -o 'jsonpath={.status.readyReplicas}' 2>/dev/null || true)"
  desired_replicas="${desired_replicas:-1}"
  ready_replicas="${ready_replicas:-0}"

  is_uint "${desired_replicas}" || return 1
  is_uint "${ready_replicas}" || return 1
  [[ "${available_status}" == "True" && "${desired_replicas}" -gt 0 && "${ready_replicas}" -ge "${desired_replicas}" ]]
}

traefik_service_exists() {
  kubectl -n kube-system get service/traefik >/dev/null 2>&1
}

traefik_loadbalancer_status_ready() {
  local ingress

  ingress="$(kubectl -n kube-system get service/traefik -o 'jsonpath={.status.loadBalancer.ingress[*].ip}{.status.loadBalancer.ingress[*].hostname}' 2>/dev/null || true)"
  [[ -n "${ingress}" ]]
}

servicelb_daemonsets_ready() {
  local current_scheduled
  local daemonset_ref
  local daemonset_refs
  local desired_scheduled
  local found=false
  local ready_scheduled

  daemonset_refs="$(get_prefixed_resource_names kube-system daemonset daemonset.apps/svclb-traefik-)"
  while IFS= read -r daemonset_ref; do
    [[ -n "${daemonset_ref}" ]] || continue
    found=true

    desired_scheduled="$(kubectl -n kube-system get "${daemonset_ref}" -o 'jsonpath={.status.desiredNumberScheduled}' 2>/dev/null || true)"
    current_scheduled="$(kubectl -n kube-system get "${daemonset_ref}" -o 'jsonpath={.status.currentNumberScheduled}' 2>/dev/null || true)"
    ready_scheduled="$(kubectl -n kube-system get "${daemonset_ref}" -o 'jsonpath={.status.numberReady}' 2>/dev/null || true)"
    desired_scheduled="${desired_scheduled:-0}"
    current_scheduled="${current_scheduled:-0}"
    ready_scheduled="${ready_scheduled:-0}"

    is_uint "${desired_scheduled}" || return 1
    is_uint "${current_scheduled}" || return 1
    is_uint "${ready_scheduled}" || return 1
    [[ "${desired_scheduled}" -gt 0 ]] || return 1
    [[ "${current_scheduled}" -ge "${desired_scheduled}" ]] || return 1
    [[ "${ready_scheduled}" -ge "${desired_scheduled}" ]] || return 1
  done <<<"${daemonset_refs}"

  [[ "${found}" == true ]]
}

servicelb_pods_ready() {
  local found=false
  local phase
  local pod_ref
  local pod_refs
  local ready_status

  pod_refs="$(get_prefixed_resource_names kube-system pod pod/svclb-traefik-)"
  while IFS= read -r pod_ref; do
    [[ -n "${pod_ref}" ]] || continue
    found=true

    phase="$(kubectl -n kube-system get "${pod_ref}" -o 'jsonpath={.status.phase}' 2>/dev/null || true)"
    ready_status="$(kubectl -n kube-system get "${pod_ref}" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    [[ "${phase}" == "Running" ]] || return 1
    [[ "${ready_status}" == "True" ]] || return 1
  done <<<"${pod_refs}"

  [[ "${found}" == true ]]
}

check_packaged_traefik_and_servicelb() {
  local daemonset_refs
  local service_json
  local service_type
  section "Packaged Traefik and ServiceLB"

  if wait_until "k3s packaged Traefik HelmChart" traefik_helmchart_exists; then
    ok "k3s packaged Traefik HelmChart exists."
  else
    fail_check "missing kube-system HelmChart traefik."
    return
  fi

  if wait_until "Traefik deployment readiness" traefik_deployment_ready; then
    ok "deployment.apps/traefik is Available with ready replicas."
  else
    fail_check "deployment.apps/traefik is not Available/Ready in kube-system."
  fi

  if wait_until "Traefik LoadBalancer service" traefik_service_exists; then
    ok "service/traefik exists in kube-system."
  else
    fail_check "service/traefik is missing in kube-system."
    return
  fi

  if ! service_json="$(kubectl -n kube-system get service/traefik -o json 2>/dev/null)"; then
    fail_check "failed to query service/traefik JSON from the Kubernetes API."
    return
  fi

  if ! jq -e '.spec.ports | type == "array"' >/dev/null <<<"${service_json}"; then
    fail_check "service/traefik JSON does not contain a valid spec.ports array."
    return
  fi

  service_type="$(jq -r '.spec.type // ""' <<<"${service_json}")"
  if [[ "${service_type}" == "LoadBalancer" ]]; then
    ok "service/traefik type is LoadBalancer."
  else
    fail_check "service/traefik type is ${service_type:-unknown}; expected LoadBalancer."
  fi

  if jq -e 'any(.spec.ports[]?; .port == 80 and .protocol == "TCP")' >/dev/null <<<"${service_json}"; then
    ok "service/traefik exposes 80/TCP."
  else
    fail_check "service/traefik does not expose 80/TCP."
  fi

  if jq -e 'any(.spec.ports[]?; .port == 443 and .protocol == "TCP")' >/dev/null <<<"${service_json}"; then
    ok "service/traefik exposes 443/TCP."
  else
    fail_check "service/traefik does not expose 443/TCP."
  fi

  if wait_until "Traefik LoadBalancer status" traefik_loadbalancer_status_ready; then
    ok "service/traefik has LoadBalancer ingress status."
  else
    warn "service/traefik LoadBalancer ingress status is not populated yet."
  fi

  daemonset_refs="$(get_prefixed_resource_names kube-system daemonset daemonset.apps/svclb-traefik-)"
  if [[ -n "${daemonset_refs}" ]]; then
    ok "ServiceLB daemonset for Traefik exists."
  else
    fail_check "ServiceLB daemonset for Traefik is missing."
  fi

  if wait_until "ServiceLB daemonset readiness" servicelb_daemonsets_ready; then
    ok "ServiceLB daemonset desired/current/ready state is healthy."
  else
    fail_check "ServiceLB daemonset for Traefik is not healthy."
  fi

  if wait_until "ServiceLB pod readiness" servicelb_pods_ready; then
    ok "ServiceLB pod for Traefik is Running and Ready."
  else
    fail_check "ServiceLB pod for Traefik is not Running/Ready."
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
  local listening_sockets
  section "Listening ports"

  if command -v ss >/dev/null 2>&1; then
    listening_sockets="$(ss -ltnp 2>/dev/null || true)"
    awk 'NR == 1 || $4 ~ /(:6443)$/ || $4 ~ /(:6443)[[:space:]]/' <<<"${listening_sockets}"
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
  check_packaged_traefik_and_servicelb
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
