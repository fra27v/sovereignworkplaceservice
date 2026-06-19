#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
versions_file="${script_dir}/../openbao-global.versions.env"
values_file="${script_dir}/../values/openbao-global.values.yaml"
output_file="/tmp/openbao-global.dry-run.yaml"

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
