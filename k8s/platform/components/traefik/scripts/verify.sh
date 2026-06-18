#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: verify.sh --env-file <path>

Verifies a Traefik Helm release using the supplied environment file.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../.." && pwd)"
component_env="${repo_root}/k8s/platform/components/traefik/component.env"

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

curl_status() {
  local url="$1"
  local status

  status="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 5 "${url}" || true)"

  if [[ ! "${status}" =~ ^[1-5][0-9][0-9]$ ]]; then
    fail "URL ${url} is not reachable. curl status was: ${status}"
  fi

  echo "${url} -> HTTP ${status}"
}

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

[[ -f "${component_env}" ]] || fail "Missing component env file: ${component_env}"

env_file="$(resolve_path "${env_file}")"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"

source "${component_env}"
source "${env_file}"

required_vars=(
  TRAEFIK_RELEASE_NAME
  TRAEFIK_NAMESPACE
  TRAEFIK_KUBECONFIG
  TRAEFIK_EXPECTED_HTTP_PORT
  TRAEFIK_EXPECTED_HTTPS_PORT
  TRAEFIK_EXPECT_LOADBALANCER_SERVICE
)

for var_name in "${required_vars[@]}"; do
  [[ -n "${!var_name:-}" ]] || fail "Missing required variable: ${var_name}"
done

[[ -f "${TRAEFIK_KUBECONFIG}" ]] || fail "Missing kubeconfig: ${TRAEFIK_KUBECONFIG}"
export KUBECONFIG="${TRAEFIK_KUBECONFIG}"

command -v helm >/dev/null 2>&1 || fail "helm is not installed."

if command -v kubectl >/dev/null 2>&1; then
  KUBECTL=(kubectl)
elif command -v k3s >/dev/null 2>&1; then
  KUBECTL=(k3s kubectl)
else
  fail "Neither kubectl nor k3s is available."
fi

section "Traefik target"
echo "Release:   ${TRAEFIK_RELEASE_NAME}"
echo "Namespace: ${TRAEFIK_NAMESPACE}"

section "Helm status"
helm status "${TRAEFIK_RELEASE_NAME}" -n "${TRAEFIK_NAMESPACE}"

section "Pods"
"${KUBECTL[@]}" get pods -n "${TRAEFIK_NAMESPACE}" -o wide --show-labels

section "Deployment"
"${KUBECTL[@]}" get deployment "${TRAEFIK_RELEASE_NAME}" -n "${TRAEFIK_NAMESPACE}" -o wide --show-labels

section "Deployment rollout"
"${KUBECTL[@]}" rollout status "deployment/${TRAEFIK_RELEASE_NAME}" \
  -n "${TRAEFIK_NAMESPACE}" \
  --timeout=120s

section "IngressClass"
"${KUBECTL[@]}" get ingressclass

section "Services"
"${KUBECTL[@]}" get services -n "${TRAEFIK_NAMESPACE}" -o wide || true

section "LoadBalancer service check"
load_balancer_services="$(
  "${KUBECTL[@]}" get services -n "${TRAEFIK_NAMESPACE}" \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}'
)"

if [[ "${TRAEFIK_EXPECT_LOADBALANCER_SERVICE}" == "false" && -n "${load_balancer_services}" ]]; then
  echo "${load_balancer_services}" >&2
  fail "Traefik LoadBalancer service exists but this environment does not expect one."
fi

echo "LoadBalancer service check passed."

section "hostPort declaration"
host_ports="$(
  "${KUBECTL[@]}" get deployment "${TRAEFIK_RELEASE_NAME}" -n "${TRAEFIK_NAMESPACE}" \
    -o jsonpath='{range .spec.template.spec.containers[*].ports[*]}{.hostPort}{"\n"}{end}' \
    | awk 'NF { print }' \
    | sort -n \
    | uniq
)"

section "Listening ports snapshot"
if command -v ss >/dev/null 2>&1; then
  ss -lntup | grep -E ':(80|443|6443)\s' || true
elif command -v netstat >/dev/null 2>&1; then
  netstat -lntup | grep -E ':(80|443|6443)\s' || true
else
  echo "Neither ss nor netstat is available."
fi

echo
echo "Traefik verification passed."