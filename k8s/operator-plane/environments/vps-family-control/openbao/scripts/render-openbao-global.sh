#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
versions_file="${script_dir}/../openbao-global.versions.env"
values_file="${script_dir}/../values/openbao-global.values.yaml"
output_file="/tmp/openbao-global.dry-run.yaml"

count_statefulset_env_name() {
  local env_name="$1"

  awk -v env_name="${env_name}" '
    /^kind: StatefulSet$/ { in_statefulset = 1; next }
    in_statefulset && /^---$/ { in_statefulset = 0 }
    in_statefulset && $0 ~ "^[[:space:]]*- name: " env_name "$" { count++ }
    END { print count + 0 }
  ' "${output_file}"
}

if [[ ! -f "${versions_file}" ]]; then
  echo "ERROR: missing versions file: ${versions_file}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${versions_file}"

if [[ -z "${OPENBAO_HELM_CHART_VERSION:-}" ]]; then
  echo "ERROR: OPENBAO_HELM_CHART_VERSION must be set in ${versions_file}." >&2
  exit 1
fi

if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: missing values file: ${values_file}" >&2
  exit 1
fi

helm upgrade --install openbao-global openbao/openbao \
  --namespace openbao-operator \
  --create-namespace \
  --version "${OPENBAO_HELM_CHART_VERSION}" \
  --values "${values_file}" \
  --dry-run \
  > "${output_file}"

echo "Rendered dry-run output: ${output_file}"

echo "Expected rendered resources and mounts:"
grep -n "kind: StatefulSet" "${output_file}"
grep -n "hostPath:" "${output_file}"
grep -n "openbao-static-seal" "${output_file}"
grep -n "openbao-local-tls" "${output_file}"
grep -Fn 'audit "file" "file"' "${output_file}"
grep -Fn 'file_path = "/openbao/audit/audit.log"' "${output_file}"
grep -En 'log_raw[[:space:]]*=[[:space:]]*"false"' "${output_file}"
grep -Fn "/openbao/audit" "${output_file}"
grep -Fn 'value: "https://127.0.0.1:8200"' "${output_file}"
grep -Fn 'value: "https://$(POD_IP):8200"' "${output_file}"

echo "Expected absent resources:"
if grep -n "kind: Ingress" "${output_file}"; then
  echo "ERROR: Ingress rendered unexpectedly." >&2
  exit 1
else
  echo "OK: no Ingress rendered."
fi

if grep -n "kind: MutatingWebhookConfiguration" "${output_file}"; then
  echo "ERROR: MutatingWebhookConfiguration rendered unexpectedly." >&2
  exit 1
else
  echo "OK: no MutatingWebhookConfiguration rendered."
fi

if grep -Fn 'value: "http://127.0.0.1:8200"' "${output_file}"; then
  echo "ERROR: HTTP localhost OpenBao address rendered unexpectedly." >&2
  exit 1
else
  echo "OK: no HTTP localhost OpenBao address rendered."
fi

if grep -Fn 'value: "http://$(POD_IP):8200"' "${output_file}"; then
  echo "ERROR: HTTP pod OpenBao address rendered unexpectedly." >&2
  exit 1
else
  echo "OK: no HTTP pod OpenBao address rendered."
fi

bao_addr_count="$(count_statefulset_env_name "BAO_ADDR")"
if [[ "${bao_addr_count}" -gt 1 ]]; then
  echo "ERROR: duplicate BAO_ADDR entries rendered in StatefulSet env: ${bao_addr_count}" >&2
  exit 1
else
  echo "OK: BAO_ADDR entries rendered in StatefulSet env: ${bao_addr_count}"
fi

bao_api_addr_count="$(count_statefulset_env_name "BAO_API_ADDR")"
if [[ "${bao_api_addr_count}" -gt 1 ]]; then
  echo "ERROR: duplicate BAO_API_ADDR entries rendered in StatefulSet env: ${bao_api_addr_count}" >&2
  exit 1
else
  echo "OK: BAO_API_ADDR entries rendered in StatefulSet env: ${bao_api_addr_count}"
fi
