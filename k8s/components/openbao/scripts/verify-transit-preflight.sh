#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

tenant_file=""
live="false"

usage() {
  cat <<'USAGE'
Usage:
  verify-transit-preflight.sh [--tenant-file <path>] [--live] [--help]

Verifies Tenant OpenBao Transit prerequisites without printing secrets. Static
mode validates the resolved external endpoint and derived names. Live mode also
checks namespace, Operator CA ConfigMap, Transit token Secret, DNS, TLS, and a
minimal Transit encrypt call when curl is available.
USAGE
}

ok() {
  echo "OK: $*"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tenant-file)
      [[ "$#" -ge 2 ]] || fail "--tenant-file requires a path."
      tenant_file="$2"
      shift 2
      ;;
    --live)
      live="true"
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

tenant_file="${tenant_file:-$(resolve_tenant_file family-infra)}"
[[ -f "${tenant_file}" ]] || fail "Missing tenant file: ${tenant_file}"

tenant_name="$(require_yaml_value "${tenant_file}" tenant.name)"
tenant_node="$(require_yaml_value "${tenant_file}" tenant.node)"
namespace="$(derive_namespace "${tenant_name}")"
transit_address="$(require_yaml_value "${tenant_file}" openbao.transit.address)"
transit_host="$(validate_transit_address "${transit_address}")"
transit_key="$(optional_yaml_value "${tenant_file}" openbao.transit.keyName "$(derive_transit_key_name "${tenant_node}")")"
transit_mount="$(optional_yaml_value "${tenant_file}" openbao.transit.mountPath "$(derive_transit_mount_path)")"
ca_configmap="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName "$(derive_transit_ca_bundle_configmap_name)")"
ca_key="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleKey "$(derive_transit_ca_bundle_key)")"
secret_name="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretName "$(derive_transit_token_secret_name)")"
secret_key="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretKey "$(derive_transit_token_secret_key)")"

[[ "${transit_key}" = "$(derive_transit_key_name "${tenant_node}")" ]] || fail "Transit key must derive from tenant node: ${tenant_node}-autounseal"
ok "Transit endpoint is external HTTPS: ${transit_address}"
ok "Transit TLS server name is derived from endpoint host: ${transit_host}"
ok "Transit key is ${transit_key}"
ok "Transit mount is ${transit_mount}"
ok "Operator CA ConfigMap reference is ${namespace}/${ca_configmap}:${ca_key}"
ok "Transit token Secret reference is ${namespace}/${secret_name}:${secret_key}"

if [[ "${live}" != "true" ]]; then
  echo "Static Transit preflight completed."
  exit 0
fi

require_command kubectl
require_command jq
require_command openssl

kubectl get namespace "${namespace}" >/dev/null
ok "namespace exists: ${namespace}"

cm_json="$(kubectl -n "${namespace}" get configmap "${ca_configmap}" -o json)"
if ! printf '%s\n' "${cm_json}" | jq -e --arg key "${ca_key}" '(.data[$key] // "") != ""' >/dev/null; then
  fail "Operator CA ConfigMap is missing key ${ca_key}"
fi
ok "Operator CA ConfigMap key exists; CA data was not printed"

secret_json="$(kubectl -n "${namespace}" get secret "${secret_name}" -o json)"
if ! printf '%s\n' "${secret_json}" | jq -e --arg key "${secret_key}" '(.data[$key] // "") != ""' >/dev/null; then
  fail "Transit token Secret is missing key ${secret_key}"
fi
ok "Transit token Secret key exists; Secret data was not printed"

if command -v getent >/dev/null 2>&1; then
  getent hosts "${transit_host}" >/dev/null
  ok "Transit DNS resolves: ${transit_host}"
elif command -v nslookup >/dev/null 2>&1; then
  nslookup "${transit_host}" >/dev/null
  ok "Transit DNS resolves: ${transit_host}"
else
  echo "WARN: getent/nslookup not available; skipping DNS resolution check" >&2
fi

ca_file="$(mktemp /tmp/openbao-transit-ca.XXXXXX.pem)"
token_file="$(mktemp /tmp/openbao-transit-token.XXXXXX.txt)"
cleanup() {
  rm -f "${ca_file}" "${token_file}"
}
trap cleanup EXIT

printf '%s\n' "${cm_json}" | jq -r --arg key "${ca_key}" '.data[$key]' > "${ca_file}"
kubectl -n "${namespace}" get secret "${secret_name}" -o "jsonpath={.data.${secret_key}}" \
  | base64 -d > "${token_file}"
chmod 0600 "${ca_file}" "${token_file}"

printf '' | openssl s_client \
  -connect "${transit_host}:443" \
  -servername "${transit_host}" \
  -CAfile "${ca_file}" \
  -verify_return_error >/dev/null 2>&1
ok "Transit TLS certificate validates against Operator CA bundle"

if command -v curl >/dev/null 2>&1; then
  token="$(cat "${token_file}")"
  payload='{"plaintext":"cHJlZmxpZ2h0"}'
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --cacert "${ca_file}" \
    -H "X-Vault-Token: ${token}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "${payload}" \
    "${transit_address%/}/v1/${transit_mount%/}/encrypt/${transit_key}")"
  unset token
  [[ "${http_code}" = "200" ]] || fail "Transit encrypt preflight returned HTTP ${http_code}"
  ok "Transit token can perform encrypt preflight; response body and token were not printed"
else
  echo "WARN: curl not available; skipping Transit encrypt preflight" >&2
fi

echo "Live Transit preflight completed."
