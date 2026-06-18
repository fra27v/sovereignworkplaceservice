#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: verify.sh --env-file <path>

Verifies a Traefik Helm release using the supplied environment file.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

resolve_path() {
  local path="$1"

  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  elif [[ -f "${path}" ]]; then
    local path_dir
    local path_base
    path_dir="$(cd -- "$(dirname -- "${path}")" && pwd)"
    path_base="$(basename -- "${path}")"
    printf '%s/%s\n' "${path_dir}" "${path_base}"
  else
    printf '%s/%s\n' "${repo_root}" "${path}"
  fi
}

port_is_listening() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :${port} )" | awk 'NR > 1 { found = 1 } END { exit found ? 0 : 1 }'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn | awk -v port=":${port}" '$4 ~ port "$" { found = 1 } END { exit found ? 0 : 1 }'
  else
    fail "Neither ss nor netstat is available to verify listening ports."
  fi
}

get_release_deployments() {
  kubectl get deployment -n "${TRAEFIK_NAMESPACE}" \
    -l "app.kubernetes.io/instance=${TRAEFIK_RELEASE_NAME}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
env_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${env_file}" ]] || {
  usage
  fail "Missing required --env-file argument."
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root, for example with sudo."
fi

env_file="$(resolve_path "${env_file}")"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  TRAEFIK_RELEASE_NAME
  TRAEFIK_NAMESPACE
  TRAEFIK_KUBECONFIG
)

for var_name in "${required_vars[@]}"; do
  [[ -n "${!var_name:-}" ]] || fail "Missing required variable: ${var_name}"
done

[[ -f "${TRAEFIK_KUBECONFIG}" ]] || fail "Missing kubeconfig: ${TRAEFIK_KUBECONFIG}"
export KUBECONFIG="${TRAEFIK_KUBECONFIG}"

command -v helm >/dev/null 2>&1 || fail "helm is not installed."
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed."

section "Helm status"
helm status "${TRAEFIK_RELEASE_NAME}" -n "${TRAEFIK_NAMESPACE}"

section "Pods"
kubectl get pods -n "${TRAEFIK_NAMESPACE}" -o wide

section "Deployment"
kubectl get deployment -n "${TRAEFIK_NAMESPACE}" -l "app.kubernetes.io/instance=${TRAEFIK_RELEASE_NAME}" -o wide

section "IngressClass"
kubectl get ingressclass

section "Services"
kubectl get services -n "${TRAEFIK_NAMESPACE}" -o wide

deployments="$(get_release_deployments)"
[[ -n "${deployments}" ]] || fail "No deployment found for release ${TRAEFIK_RELEASE_NAME}."

while IFS= read -r deployment_name; do
  [[ -n "${deployment_name}" ]] || continue
  kubectl rollout status deployment/"${deployment_name}" -n "${TRAEFIK_NAMESPACE}" --timeout=120s
done <<<"${deployments}"

host_ports="$(kubectl get deployment -n "${TRAEFIK_NAMESPACE}" \
  -l "app.kubernetes.io/instance=${TRAEFIK_RELEASE_NAME}" \
  -o jsonpath='{range .items[*].spec.template.spec.containers[*].ports[*]}{.hostPort}{"\n"}{end}' \
  | awk 'NF { print }' \
  | sort -n \
  | uniq)"

[[ -n "${host_ports}" ]] || fail "No hostPort values found on Traefik deployment."

section "hostPort listeners"
while IFS= read -r host_port; do
  [[ -n "${host_port}" ]] || continue
  echo "Checking hostPort ${host_port}"
  port_is_listening "${host_port}" || fail "Port ${host_port} is not listening."
done <<<"${host_ports}"

load_balancer_services="$(kubectl get services -n "${TRAEFIK_NAMESPACE}" -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}')"
if [[ -n "${load_balancer_services}" ]]; then
  echo "${load_balancer_services}" >&2
  fail "Traefik LoadBalancer service exists but runtime Traefik is configured for hostPort."
fi

echo
echo "Traefik verification passed."
