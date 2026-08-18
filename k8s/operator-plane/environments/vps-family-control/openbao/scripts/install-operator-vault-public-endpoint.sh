#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
openbao_dir="$(cd -- "${script_dir}/.." && pwd)"
env_dir="$(cd -- "${openbao_dir}/.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_loader="${env_dir}/scripts/lib/load-operator-plane-env.sh"
rendered_file=""
dry_run="false"

namespace="openbao-operator"
middleware_name="operator-vault-ip-allowlist"
ingressroute_name="operator-vault"
backend_service_name="openbao-global"
backend_service_port="8200"
entrypoint_name="websecure"

required_env_keys=(
  OPERATOR_DOMAIN
  OPERATOR_VAULT_ALLOWED_SOURCE_RANGES
)

usage() {
  cat <<'USAGE'
Usage:
  install-operator-vault-public-endpoint.sh [--env-file <path>] [--dry-run] [--help]

Renders and reconciles the Traefik TCP passthrough endpoint for operator-vault.
TLS remains terminated by OpenBao. Access is restricted by MiddlewareTCP
ipAllowList.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Render and run kubectl server-side dry-run only.
  --help             Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

cleanup() {
  if [[ -n "${rendered_file}" && -f "${rendered_file}" ]]; then
    rm -f "${rendered_file}"
  fi
}
trap cleanup EXIT

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

render_source_ranges_yaml() {
  local raw="$1"
  local item trimmed count=0

  IFS=',' read -r -a ranges <<< "${raw}"
  for item in "${ranges[@]}"; do
    trimmed="$(trim "${item}")"
    [[ -n "${trimmed}" ]] || continue
    printf '      - "%s"\n' "${trimmed}"
    count=$((count + 1))
  done

  [[ "${count}" -gt 0 ]] || fail "OPERATOR_VAULT_ALLOWED_SOURCE_RANGES must contain at least one CIDR."
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

render_manifest() {
  local source_ranges_yaml="$1"

  cat > "${rendered_file}" <<EOF
apiVersion: traefik.io/v1alpha1
kind: MiddlewareTCP
metadata:
  name: ${middleware_name}
  namespace: ${namespace}
spec:
  ipAllowList:
    sourceRange:
${source_ranges_yaml}
---
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: ${ingressroute_name}
  namespace: ${namespace}
spec:
  entryPoints:
    - ${entrypoint_name}
  routes:
    - match: HostSNI(\`${OPERATOR_VAULT_PUBLIC_HOSTNAME}\`)
      middlewares:
        - name: ${middleware_name}
          namespace: ${namespace}
      services:
        - name: ${backend_service_name}
          port: ${backend_service_port}
  tls:
    passthrough: true
EOF
}

validate_manifest() {
  if grep -Eq 'certResolver|secretName|letsencrypt|ipWhiteList|kind:[[:space:]]*IngressRoute$|kind:[[:space:]]*Middleware$|domains:' "${rendered_file}"; then
    fail "Rendered manifest contains a forbidden operator-vault exposure field or resource kind."
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
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
require_command grep

[[ -f "${env_loader}" ]] || fail "Missing env loader: ${env_loader}"
# shellcheck source=../../scripts/lib/load-operator-plane-env.sh
source "${env_loader}"
[[ -f "${env_file}" ]] || fail "Missing env file: ${env_file}"
load_operator_plane_env "${env_file}" "true" "${required_env_keys[@]}"

OPERATOR_VAULT_PUBLIC_HOSTNAME="operator-vault.${OPERATOR_DOMAIN}"
allowed_source_range_count="$(count_source_ranges "${OPERATOR_VAULT_ALLOWED_SOURCE_RANGES}")"
source_ranges_yaml="$(render_source_ranges_yaml "${OPERATOR_VAULT_ALLOWED_SOURCE_RANGES}")"

rendered_file="$(mktemp /tmp/operator-vault-public-endpoint.XXXXXX.yaml)"
chmod 0600 "${rendered_file}"
render_manifest "${source_ranges_yaml}"
validate_manifest

echo "Prepared operator-vault public endpoint reconciliation."
echo "Namespace: ${namespace}"
echo "Public hostname: configured"
echo "Backend service name: ${backend_service_name}"
echo "Backend service port: ${backend_service_port}"
echo "TLS passthrough enabled: true"
echo "TLS termination: OpenBao"
echo "Access restriction mode: MiddlewareTCP ipAllowList"
echo "Allowed source range count: ${allowed_source_range_count}"
echo "Allowed source range values were not printed."

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: running kubectl server-side apply dry-run."
  kubectl apply --dry-run=server -f "${rendered_file}" >/dev/null
  echo "DRY-RUN: operator-vault public endpoint passed server-side validation."
  exit 0
fi

echo "Applying operator-vault public endpoint manifest."
kubectl apply -f "${rendered_file}"
echo "operator-vault public endpoint reconciliation completed."
echo "Temporary rendered manifest will be removed."
