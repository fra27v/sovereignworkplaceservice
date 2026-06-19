#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_name="openbao-global"
namespace="openbao-operator"
values_file="${script_dir}/../values/openbao-global.values.yaml"
versions_file="${script_dir}/../openbao-global.versions.env"

if [[ ! -f "${values_file}" ]]; then
  echo "ERROR: missing values file: ${values_file}" >&2
  exit 1
fi

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

helm upgrade --install "${release_name}" openbao/openbao \
  --namespace "${namespace}" \
  --create-namespace \
  --version "${OPENBAO_HELM_CHART_VERSION}" \
  --values "${values_file}"

cat <<'FOLLOW_UP'

Safe follow-up checks:
kubectl -n openbao-operator get pods,svc,pvc
kubectl -n openbao-operator logs openbao-global-0 --tail=120

This script does not initialize OpenBao.
FOLLOW_UP
