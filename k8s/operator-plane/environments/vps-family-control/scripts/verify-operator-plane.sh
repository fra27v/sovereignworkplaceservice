#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"

summary_ok=()
summary_warn=()
summary_fail=()

declare -A verify_status=()

usage() {
  cat <<EOF
Usage: $0 [--env-file <path>] [--help]

Verify the vps-family-control operator plane without printing secrets.

Options:
  --env-file <path>  Path to the central operator-plane.env file.
  --help            Show this help.
EOF
}

ok() {
  summary_ok+=("$1")
  echo "OK: $1"
}

warn() {
  summary_warn+=("$1")
  echo "WARN: $1" >&2
}

fail_component() {
  summary_fail+=("$1")
  echo "FAIL: $1" >&2
}

run_verify_script() {
  local label="$1"
  local path="$2"
  shift 2

  local failure_mode="fail"
  if [[ "$#" -gt 0 && ( "$1" == "warn" || "$1" == "fail" ) ]]; then
    failure_mode="$1"
    shift
  fi
  local args=("$@")

  if [[ ! -f "${path}" ]]; then
      if [[ "${failure_mode}" = "warn" ]]; then
        warn "${label} verification script is missing: ${path}"
      else
        fail_component "${label} verification script is missing: ${path}"
      fi
      return 0
  fi

  if [[ ! -x "${path}" ]]; then
      if [[ "${failure_mode}" = "warn" ]]; then
        warn "${label} verification script is not executable: ${path}"
      else
        fail_component "${label} verification script is not executable: ${path}"
      fi
      return 0
  fi

  echo
  echo "== ${label} verification script =="
  echo "+ ${path}${args[*]:+ ${args[*]}}"
  if "${path}" "${args[@]}"; then
    ok "${label} verification script passed"
    verify_status["${label}"]="pass"
  else
    if [[ "${failure_mode}" = "warn" ]]; then
      warn "${label} verification script did not pass; treat as TODO until the corresponding explicit phase is complete"
      verify_status["${label}"]="warn"
    else
      fail_component "${label} verification script failed"
      verify_status["${label}"]="fail"
    fi
  fi
}

kubectl_safe() {
  kubectl "$@" 2>/dev/null
}

kubectl_available() {
  command -v kubectl >/dev/null 2>&1
}

check_k3s_node_ready() {
  echo
  echo "== k3s node =="
  if ! kubectl_available; then
    fail_component "kubectl is required for direct checks"
    return 0
  fi

  kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' --no-headers || true

  local ready_count
  ready_count="$(kubectl_safe get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c '^True$' || true)"
  if [[ "${ready_count}" -ge 1 ]]; then
    ok "at least one k3s node is Ready"
  else
    fail_component "no k3s node is Ready"
  fi
}

check_trading_namespace() {
  echo
  echo "== trading namespace =="
  if ! kubectl_available; then
    warn "kubectl is unavailable; skipping trading namespace scope check"
    return 0
  fi

  if kubectl_safe get namespace trading >/dev/null; then
    warn "trading namespace exists and is intentionally not managed by this script"
  else
    ok "trading namespace is absent from operator-plane verification scope"
  fi
}

check_traefik_pod() {
  echo
  echo "== Traefik pod =="
  if ! kubectl_available; then
    warn "kubectl is unavailable; skipping Traefik pod check"
    return 0
  fi

  if ! kubectl_safe get namespace kube-system >/dev/null; then
    fail_component "kube-system namespace is not readable"
    return 0
  fi

  kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status' \
    --no-headers || true

  local running_count
  running_count="$(kubectl_safe -n kube-system get pods -l app.kubernetes.io/name=traefik -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -c '^Running$' || true)"
  if [[ "${running_count}" -ge 1 ]]; then
    ok "Traefik pod is Running"
  else
    fail_component "no Traefik pod is Running"
  fi
}

check_operator_artifacts_pod() {
  echo
  echo "== operator-artifacts pod =="
  if ! kubectl_available; then
    warn "kubectl is unavailable; skipping operator-artifacts pod check"
    return 0
  fi

  if ! kubectl_safe get namespace operator-artifacts >/dev/null; then
    fail_component "operator-artifacts namespace is missing"
    return 0
  fi

  kubectl -n operator-artifacts get pods -l app.kubernetes.io/name=operator-artifacts \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status' \
    --no-headers || true

  local ready_count
  ready_count="$(kubectl_safe -n operator-artifacts get pods -l app.kubernetes.io/name=operator-artifacts -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c '^True$' || true)"
  if [[ "${ready_count}" -ge 1 ]]; then
    ok "operator-artifacts pod is Ready"
  else
    fail_component "no operator-artifacts pod is Ready"
  fi
}

check_openbao_pod() {
  echo
  echo "== Global OpenBao pod =="
  if ! kubectl_available; then
    warn "kubectl is unavailable; skipping OpenBao pod check"
    return 0
  fi

  if ! kubectl_safe get namespace openbao-operator >/dev/null; then
    warn "openbao-operator namespace is absent; skipping OpenBao pod check"
    return 0
  fi

  kubectl -n openbao-operator get pods \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status' \
    --no-headers || true

  local running_count
  running_count="$(kubectl_safe -n openbao-operator get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' | awk '$1 ~ /^openbao-global/ && $2 == "Running" { count++ } END { print count + 0 }')"
  if [[ "${running_count}" -ge 1 ]]; then
    ok "Global OpenBao pod is Running"
  else
    fail_component "no Global OpenBao pod is Running in openbao-operator"
  fi
}

print_todos() {
  echo
  echo "== TODO =="
  if [[ "${verify_status["operator-vault TLS runtime"]:-unknown}" != "pass" ]]; then
    warn "operator-vault TLS rotation is explicit and may not have been run yet"
  fi
  warn "operator-vault public endpoint is not implemented yet"
}

print_summary() {
  echo
  echo "== Final summary =="
  echo "OK components:"
  if [[ "${#summary_ok[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_ok[@]}"
  fi

  echo "WARN components:"
  if [[ "${#summary_warn[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_warn[@]}"
  fi

  echo "FAIL components:"
  if [[ "${#summary_fail[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_fail[@]}"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || {
        echo "--env-file requires a path." >&2
        exit 1
      }
      env_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run_verify_script "Traefik" "${env_dir}/traefik/scripts/verify-traefik-acme-dns01-ovh.sh"
run_verify_script "OpenBao CA bundle projection" "${env_dir}/operator-secret-sync/scripts/verify-openbao-ca-bundle-configmap.sh" --env-file "${env_file}"
run_verify_script "operator-secret-sync" "${env_dir}/operator-secret-sync/scripts/verify-operator-secret-sync.sh" "warn"
run_verify_script "operator-artifacts" "${env_dir}/operator-artifacts/scripts/verify-operator-artifacts.sh"
run_verify_script "Global OpenBao audit" "${env_dir}/openbao/scripts/verify-openbao-global-audit.sh"
run_verify_script "Global OpenBao transit" "${env_dir}/openbao/scripts/verify-openbao-global-transit.sh" --env-file "${env_file}"
run_verify_script "Operator PKI" "${env_dir}/operator-pki/scripts/verify-openbao-operator-pki.sh" "warn" --env-file "${env_file}"
run_verify_script "operator-vault TLS runtime" "${env_dir}/operator-pki/scripts/verify-operator-vault-tls-runtime.sh" "warn" --env-file "${env_file}"

check_k3s_node_ready
check_trading_namespace
check_traefik_pod
check_operator_artifacts_pod
check_openbao_pod
print_todos
print_summary

if [[ "${#summary_fail[@]}" -gt 0 ]]; then
  exit 1
fi
