#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
traefik_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/traefik"
env_file="${traefik_dir}/traefik-acme-dns01.env"
env_template="${traefik_dir}/traefik-acme-dns01.env.example"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

missing_env_file() {
  cat >&2 <<EOF
Missing Traefik ACME DNS-01 environment file:
  ${env_file}

Create it from the template:
  cp ${env_template} ${env_file}

Then edit all required placeholder values before rerunning this script.

The real env file is intentionally gitignored and must not be committed.
EOF
  exit 1
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || fail "Missing required variable: ${name}"
  [[ "${value}" != "<set-me>" ]] || fail "Variable still has placeholder value: ${name}"
}

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"
command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
[[ -f "${env_file}" ]] || missing_env_file

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  TRAEFIK_NAMESPACE
  TRAEFIK_HELMCHARTCONFIG_NAME
  TRAEFIK_ACME_CERT_RESOLVER
  TRAEFIK_ACME_DNS_PROVIDER
  TRAEFIK_OVH_DNS_SECRET_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

echo "Checking OVH DNS credential Secret metadata."
secret_json="$(kubectl -n "${TRAEFIK_NAMESPACE}" get secret "${TRAEFIK_OVH_DNS_SECRET_NAME}" -o json)"
secret_name="$(printf '%s\n' "${secret_json}" | jq -r '.metadata.name')"
secret_type="$(printf '%s\n' "${secret_json}" | jq -r '.type')"

echo "Namespace: ${TRAEFIK_NAMESPACE}"
echo "Secret name: ${secret_name}"
echo "Secret type: ${secret_type}"

expected_secret_keys=(
  OVH_ENDPOINT
  OVH_APPLICATION_KEY
  OVH_APPLICATION_SECRET
  OVH_CONSUMER_KEY
)

for key_name in "${expected_secret_keys[@]}"; do
  if printf '%s\n' "${secret_json}" | jq -e --arg key "${key_name}" '.data | has($key)' >/dev/null; then
    echo "Secret key present: ${key_name}"
  else
    echo "Secret key missing: ${key_name}" >&2
    missing_secret_key="true"
  fi
done

if [[ "${missing_secret_key:-false}" = "true" ]]; then
  fail "OVH DNS credential Secret is missing one or more expected keys."
fi

echo "Checking HelmChartConfig exists."
kubectl -n "${TRAEFIK_NAMESPACE}" get helmchartconfig "${TRAEFIK_HELMCHARTCONFIG_NAME}" \
  -o custom-columns='NAME:.metadata.name,NAMESPACE:.metadata.namespace' \
  --no-headers

echo "Checking Traefik Deployment ACME DNS-01 arguments."
deployment_yaml="$(kubectl -n "${TRAEFIK_NAMESPACE}" get deployment traefik -o yaml)"
printf '%s\n' "${deployment_yaml}" | grep -E 'certificatesresolvers|dnschallenge|acme|ovh'

if ! printf '%s\n' "${deployment_yaml}" | grep -Fq "certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge=true"; then
  fail "Traefik Deployment does not show DNS challenge enabled for resolver ${TRAEFIK_ACME_CERT_RESOLVER}."
fi

if ! printf '%s\n' "${deployment_yaml}" | grep -Fq "certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge.provider=${TRAEFIK_ACME_DNS_PROVIDER}"; then
  fail "Traefik Deployment does not show DNS provider ${TRAEFIK_ACME_DNS_PROVIDER}."
fi

echo "Checking Traefik pod phase."
kubectl -n "${TRAEFIK_NAMESPACE}" get pods -l app.kubernetes.io/name=traefik \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase' \
  --no-headers

running_count="$(kubectl -n "${TRAEFIK_NAMESPACE}" get pods -l app.kubernetes.io/name=traefik \
  -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -c '^Running$' || true)"

if [[ "${running_count}" -lt 1 ]]; then
  fail "No Traefik pod is Running."
fi

echo "Safe ACME-related Traefik log lines:"
kubectl -n "${TRAEFIK_NAMESPACE}" logs deploy/traefik --tail=300 \
  | grep -Ei 'acme|challenge|resolver|certificate|ovh' || true

echo "Traefik ACME DNS-01 OVH verification completed."
