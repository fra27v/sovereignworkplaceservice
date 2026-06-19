#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
traefik_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/traefik"
env_file="${traefik_dir}/traefik-acme-dns01.env"
env_template="${traefik_dir}/traefik-acme-dns01.env.example"
template_file="${traefik_dir}/manifests/traefik-helmchartconfig-acme-dns01-ovh.yaml.tpl"
keep_output="false"
requested_output_file=""
output_file=""

cleanup() {
  if [[ "${keep_output}" != "true" && -n "${output_file}" && -f "${output_file}" ]]; then
    rm -f "${output_file}"
  fi
}
trap cleanup EXIT

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-output)
      keep_output="true"
      requested_output_file="/tmp/traefik-helmchartconfig-acme-dns01-ovh.yaml"
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output requires a path."
      keep_output="true"
      requested_output_file="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: render-traefik-acme-dns01-ovh.sh [--keep-output] [--output <path>]

Renders the Traefik HelmChartConfig to a temporary file and deletes it by
default. Use --keep-output to keep /tmp/traefik-helmchartconfig-acme-dns01-ovh.yaml,
or --output to keep a specific output path.
USAGE
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

render_template() {
  sed \
    -e "s|\${TRAEFIK_HELMCHARTCONFIG_NAME}|${TRAEFIK_HELMCHARTCONFIG_NAME}|g" \
    -e "s|\${TRAEFIK_NAMESPACE}|${TRAEFIK_NAMESPACE}|g" \
    -e "s|\${TRAEFIK_OVH_DNS_SECRET_NAME}|${TRAEFIK_OVH_DNS_SECRET_NAME}|g" \
    -e "s|\${TRAEFIK_ACME_CERT_RESOLVER}|${TRAEFIK_ACME_CERT_RESOLVER}|g" \
    -e "s|\${TRAEFIK_ACME_EMAIL}|${TRAEFIK_ACME_EMAIL}|g" \
    -e "s|\${TRAEFIK_ACME_STORAGE_PATH}|${TRAEFIK_ACME_STORAGE_PATH}|g" \
    -e "s|\${TRAEFIK_ACME_DNS_PROVIDER}|${TRAEFIK_ACME_DNS_PROVIDER}|g" \
    -e "s|\${TRAEFIK_ACME_DNS_RESOLVERS}|${TRAEFIK_ACME_DNS_RESOLVERS}|g" \
    -e "s|\${TRAEFIK_ACME_DNS_DELAY_BEFORE_CHECK}|${TRAEFIK_ACME_DNS_DELAY_BEFORE_CHECK}|g" \
    -e "s|\${TRAEFIK_ACME_CA_SERVER_ARGUMENT}|${TRAEFIK_ACME_CA_SERVER_ARGUMENT}|g" \
    "${template_file}"
}

[[ -f "${env_file}" ]] || missing_env_file
[[ -f "${template_file}" ]] || fail "Missing template file: ${template_file}"

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  TRAEFIK_NAMESPACE
  TRAEFIK_HELMCHARTCONFIG_NAME
  TRAEFIK_ACME_CERT_RESOLVER
  TRAEFIK_ACME_EMAIL
  TRAEFIK_ACME_STORAGE_PATH
  TRAEFIK_ACME_DNS_PROVIDER
  TRAEFIK_ACME_DNS_RESOLVERS
  TRAEFIK_ACME_DNS_DELAY_BEFORE_CHECK
  TRAEFIK_OVH_DNS_SECRET_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

if [[ "${TRAEFIK_ACME_DNS_PROVIDER}" != "ovh" ]]; then
  fail "TRAEFIK_ACME_DNS_PROVIDER must be ovh for this script."
fi

if [[ -n "${TRAEFIK_ACME_CA_SERVER:-}" && "${TRAEFIK_ACME_CA_SERVER}" != "<empty-for-production-or-set-staging-url>" ]]; then
  TRAEFIK_ACME_CA_SERVER_ARGUMENT="      - \"--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.caserver=${TRAEFIK_ACME_CA_SERVER}\""
else
  TRAEFIK_ACME_CA_SERVER_ARGUMENT=""
fi

if [[ "${keep_output}" = "true" ]]; then
  output_file="${requested_output_file}"
  rm -f "${output_file}"
else
  output_file="$(mktemp /tmp/traefik-helmchartconfig-acme-dns01-ovh.XXXXXX.yaml)"
fi

render_template > "${output_file}"

echo "Rendered Traefik HelmChartConfig template."
echo "Output file: ${output_file}"
echo "Namespace: ${TRAEFIK_NAMESPACE}"
echo "HelmChartConfig name: ${TRAEFIK_HELMCHARTCONFIG_NAME}"
echo "ACME resolver: ${TRAEFIK_ACME_CERT_RESOLVER}"
echo "DNS provider: ${TRAEFIK_ACME_DNS_PROVIDER}"
echo "OVH Secret name: ${TRAEFIK_OVH_DNS_SECRET_NAME}"
echo "No manifest was applied."
if [[ "${keep_output}" != "true" ]]; then
  echo "Temporary output will be removed after script completion. Use --keep-output to keep it for inspection."
fi
