#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
openbao_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${openbao_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
runtime_tls_verify_script="${env_dir}/operator-pki/scripts/verify-operator-vault-tls-runtime.sh"

namespace="openbao-operator"
middleware_name="operator-vault-ip-allowlist"
ingressroute_name="operator-vault"
backend_service_name="openbao-global"
backend_service_port="8200"
entrypoint_name="websecure"

required_env_keys=(
  OPERATOR_DOMAIN
  OPERATOR_VAULT_ALLOWED_SOURCE_RANGES
  OPERATOR_PKI_PUBLIC_DIR
  OPENBAO_TLS_DIR
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_SERVICE_NAME
)

usage() {
  cat <<'USAGE'
Usage:
  verify-operator-vault-public-endpoint.sh [--env-file <path>] [--help]

Verifies the Traefik TCP passthrough endpoint for operator-vault without
printing secrets, PEM contents, or OpenBao token material.

Options:
  --env-file <path>  Path to operator-plane.env.
  --help             Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

ok() {
  echo "OK: $*"
}

warn() {
  echo "WARN: $*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

count_source_ranges() {
  local raw="$1"
  local item trimmed count=0

  IFS=',' read -r -a ranges <<< "${raw}"
  for item in "${ranges[@]}"; do
    trimmed="$(trim "${item}")"
    [[ -n "${trimmed}" ]] || continue
    count=$((count + 1))
  done

  printf '%s' "${count}"
}

verify_openbao_pod_ready() {
  local phase ready

  phase="$(kubectl -n "${OPENBAO_NAMESPACE}" get pod "${OPENBAO_POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Running" ]] || fail "OpenBao pod is not Running: ${OPENBAO_NAMESPACE}/${OPENBAO_POD_NAME}"

  ready="$(kubectl -n "${OPENBAO_NAMESPACE}" get pod "${OPENBAO_POD_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "${ready}" == "True" ]] || fail "OpenBao pod is not Ready: ${OPENBAO_NAMESPACE}/${OPENBAO_POD_NAME}"
  ok "OpenBao pod is Running and Ready"
}

verify_runtime_certificate_san() {
  local tls_cert_path="${OPENBAO_TLS_DIR}/tls.crt"

  [[ -s "${tls_cert_path}" ]] || fail "Missing operator-vault runtime TLS certificate: ${tls_cert_path}"
  if openssl x509 -in "${tls_cert_path}" -noout -ext subjectAltName | grep -F "DNS:${OPERATOR_VAULT_PUBLIC_HOSTNAME}" >/dev/null; then
    ok "runtime TLS certificate SAN includes ${OPERATOR_VAULT_PUBLIC_HOSTNAME}"
  else
    fail "runtime TLS certificate SAN does not include ${OPERATOR_VAULT_PUBLIC_HOSTNAME}"
  fi
}

verify_kubernetes_resources() {
  local middleware_json ingressroute_json service_json
  local has_ip_allowlist has_ip_whitelist source_range_count expected_count
  local host_sni middleware_ref_name middleware_ref_namespace tls_passthrough service_name service_port
  local has_forbidden_reference has_entrypoint service_port_exists http_ingressroute_exists

  middleware_json="$(kubectl -n "${namespace}" get middlewaretcp "${middleware_name}" -o json)"
  has_ip_allowlist="$(printf '%s\n' "${middleware_json}" | jq -r 'has("spec") and (.spec | has("ipAllowList"))')"
  has_ip_whitelist="$(printf '%s\n' "${middleware_json}" | jq -r 'has("spec") and (.spec | has("ipWhiteList"))')"
  [[ "${has_ip_allowlist}" == "true" ]] || fail "MiddlewareTCP does not use spec.ipAllowList."
  [[ "${has_ip_whitelist}" == "false" ]] || fail "MiddlewareTCP uses deprecated spec.ipWhiteList."

  source_range_count="$(printf '%s\n' "${middleware_json}" | jq -r '.spec.ipAllowList.sourceRange | length')"
  expected_count="$(count_source_ranges "${OPERATOR_VAULT_ALLOWED_SOURCE_RANGES}")"
  [[ "${source_range_count}" == "${expected_count}" ]] || fail "MiddlewareTCP sourceRange count is ${source_range_count}, expected ${expected_count}."
  ok "MiddlewareTCP ipAllowList exists with expected source range count"

  ingressroute_json="$(kubectl -n "${namespace}" get ingressroutetcp "${ingressroute_name}" -o json)"
  host_sni="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].match // ""')"
  [[ "${host_sni}" == "HostSNI(\`${OPERATOR_VAULT_PUBLIC_HOSTNAME}\`)" ]] || fail "IngressRouteTCP HostSNI does not match derived hostname."

  has_entrypoint="$(printf '%s\n' "${ingressroute_json}" | jq -r --arg entrypoint "${entrypoint_name}" 'any(.spec.entryPoints[]?; . == $entrypoint)')"
  [[ "${has_entrypoint}" == "true" ]] || fail "IngressRouteTCP does not use ${entrypoint_name} entryPoint."

  middleware_ref_name="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].middlewares[0].name // ""')"
  middleware_ref_namespace="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].middlewares[0].namespace // ""')"
  [[ "${middleware_ref_name}" == "${middleware_name}" ]] || fail "IngressRouteTCP middleware reference has wrong name."
  [[ "${middleware_ref_namespace}" == "${namespace}" ]] || fail "IngressRouteTCP middleware reference has wrong namespace."

  tls_passthrough="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.tls.passthrough // false')"
  [[ "${tls_passthrough}" == "true" ]] || fail "IngressRouteTCP does not enable TLS passthrough."

  service_name="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].services[0].name // ""')"
  service_port="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].services[0].port // ""')"
  [[ "${service_name}" == "${backend_service_name}" ]] || fail "IngressRouteTCP backend service is ${service_name}, expected ${backend_service_name}."
  [[ "${service_port}" == "${backend_service_port}" ]] || fail "IngressRouteTCP backend port is ${service_port}, expected ${backend_service_port}."

  has_forbidden_reference="$(printf '%s\n' "${ingressroute_json}" | grep -Eic 'certResolver|secretName|letsencrypt|domains' || true)"
  [[ "${has_forbidden_reference}" == "0" ]] || fail "IngressRouteTCP contains a forbidden TLS termination or Let's Encrypt reference."

  if kubectl -n "${namespace}" get ingressroute "${ingressroute_name}" >/dev/null 2>&1; then
    http_ingressroute_exists="true"
  else
    http_ingressroute_exists="false"
  fi
  [[ "${http_ingressroute_exists}" == "false" ]] || fail "HTTP IngressRoute must not exist for operator-vault."

  service_json="$(kubectl -n "${namespace}" get service "${backend_service_name}" -o json)"
  service_port_exists="$(printf '%s\n' "${service_json}" | jq -r --argjson port "${backend_service_port}" 'any(.spec.ports[]?; .port == $port or .targetPort == $port)')"
  [[ "${service_port_exists}" == "true" ]] || fail "Service ${namespace}/${backend_service_name} does not expose port ${backend_service_port}."

  ok "IngressRouteTCP uses HostSNI, TLS passthrough, MiddlewareTCP, and openbao-global:8200"
  echo "Safe endpoint metadata:"
  echo "  namespace: ${namespace}"
  echo "  public hostname: configured"
  echo "  backend service: ${backend_service_name}"
  echo "  backend port: ${backend_service_port}"
  echo "  TLS passthrough: true"
  echo "  network restriction: MiddlewareTCP ipAllowList"
  echo "  allowed source range count: ${expected_count}"
}

verify_external_tls() {
  local ca_bundle_path="${OPERATOR_PKI_PUBLIC_DIR}/operator-ca-bundle.pem"
  local output verify_code subject issuer
  local openssl_status

  [[ -s "${ca_bundle_path}" ]] || fail "Missing Operator CA bundle: ${ca_bundle_path}"

  set +e
  output="$(printf '' | openssl s_client \
    -connect "${OPERATOR_VAULT_PUBLIC_HOSTNAME}:443" \
    -servername "${OPERATOR_VAULT_PUBLIC_HOSTNAME}" \
    -CAfile "${ca_bundle_path}" \
    -verify_return_error \
    -brief 2>&1)"
  openssl_status="$?"
  set -e

  verify_code="$(printf '%s\n' "${output}" | sed -n 's/^.*Verify return code: \([0-9][0-9]*\).*$/\1/p' | tail -n 1)"
  subject="$(printf '%s\n' "${output}" | sed -n 's/^subject=//p' | tail -n 1)"
  issuer="$(printf '%s\n' "${output}" | sed -n 's/^issuer=//p' | tail -n 1)"

  echo "External TLS handshake safe metadata:"
  echo "  subject: ${subject:-unavailable}"
  echo "  issuer: ${issuer:-unavailable}"
  echo "  verify return code: ${verify_code:-unavailable}"

  if [[ "${openssl_status}" -eq 0 ]]; then
    ok "external TLS handshake verifies with Operator CA bundle"
    return 0
  fi

  if printf '%s\n' "${output}" | grep -Eiq 'verify error|certificate verify failed|hostname mismatch|unable to get|self-signed|Verify return code: [1-9]'; then
    fail "external TLS route is reachable but certificate verification failed"
  fi

  warn "external DNS or network reachability is not ready for ${OPERATOR_VAULT_PUBLIC_HOSTNAME}:443"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command kubectl
require_command jq
require_command openssl
require_command grep
require_command sed

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

OPERATOR_VAULT_PUBLIC_HOSTNAME="operator-vault.${OPERATOR_DOMAIN}"

echo "Verifying operator-vault public endpoint."
echo "Namespace: ${namespace}"
echo "Public hostname: configured"
echo "TLS mode: passthrough; OpenBao terminates TLS"
echo "Network restriction: MiddlewareTCP ipAllowList"

verify_kubernetes_resources

if [[ -x "${runtime_tls_verify_script}" ]]; then
  "${runtime_tls_verify_script}" --env-file "${env_file}"
else
  warn "operator-vault runtime TLS verifier is missing or not executable: ${runtime_tls_verify_script}"
fi

verify_runtime_certificate_san
verify_openbao_pod_ready
verify_external_tls

echo "operator-vault public endpoint verification completed without printing secrets or PEM contents."
