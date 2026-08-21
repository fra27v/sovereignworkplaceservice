#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install.sh --env-file <path>

Installs or upgrades a Traefik Helm release using the platform component
settings and the supplied environment file.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../.." && pwd)"
component_env="${script_dir}/../component.env"
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

# shellcheck source=/dev/null
source "${component_env}"
# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  TRAEFIK_HELM_REPO_NAME
  TRAEFIK_HELM_REPO_URL
  TRAEFIK_HELM_CHART
  TRAEFIK_HELM_CHART_VERSION
  TRAEFIK_RELEASE_NAME
  TRAEFIK_NAMESPACE
  TRAEFIK_KUBECONFIG
  TRAEFIK_VALUES_FILES
)

for var_name in "${required_vars[@]}"; do
  [[ -n "${!var_name:-}" ]] || fail "Missing required variable: ${var_name}"
done

[[ -f "${TRAEFIK_KUBECONFIG}" ]] || fail "Missing kubeconfig: ${TRAEFIK_KUBECONFIG}"
export KUBECONFIG="${TRAEFIK_KUBECONFIG}"

IFS=':' read -r -a values_files <<<"${TRAEFIK_VALUES_FILES}"
[[ "${#values_files[@]}" -gt 0 ]] || fail "TRAEFIK_VALUES_FILES must contain at least one file."

helm_values_args=()
for values_file in "${values_files[@]}"; do
  [[ -n "${values_file}" ]] || fail "TRAEFIK_VALUES_FILES contains an empty path."
  resolved_values_file="$(resolve_path "${values_file}")"
  [[ -f "${resolved_values_file}" ]] || fail "Missing values file: ${resolved_values_file}"
  helm_values_args+=(--values "${resolved_values_file}")
done

if ! command -v helm >/dev/null 2>&1; then
  command -v curl >/dev/null 2>&1 || fail "curl is required to install Helm."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add "${TRAEFIK_HELM_REPO_NAME}" "${TRAEFIK_HELM_REPO_URL}" --force-update
helm repo update "${TRAEFIK_HELM_REPO_NAME}"

helm upgrade --install "${TRAEFIK_RELEASE_NAME}" "${TRAEFIK_HELM_CHART}" \
  --namespace "${TRAEFIK_NAMESPACE}" \
  --create-namespace \
  --version "${TRAEFIK_HELM_CHART_VERSION}" \
  "${helm_values_args[@]}"
