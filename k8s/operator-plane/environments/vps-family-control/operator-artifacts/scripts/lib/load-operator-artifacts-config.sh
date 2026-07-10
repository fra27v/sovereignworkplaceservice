#!/usr/bin/env bash

operator_artifacts_env_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_artifacts_env_root="$(cd -- "${operator_artifacts_env_lib_dir}/../../.." && pwd)"
operator_artifacts_env_loader="${operator_artifacts_env_root}/scripts/lib/load-operator-plane-env.sh"
operator_artifacts_default_env_file="${operator_artifacts_env_root}/operator-plane.env"

operator_artifacts_required_env_keys=(
  OPERATOR_DOMAIN
  OPERATOR_ARTIFACTS_LOCAL_ROOT
  OPERATOR_ARTIFACTS_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES
)

load_operator_artifacts_env() {
  local env_file="${1:-${operator_artifacts_default_env_file}}"
  local require_private_permissions="${2:-true}"

  [[ -f "${operator_artifacts_env_loader}" ]] || {
    echo "ERROR: Missing operator-plane env loader: ${operator_artifacts_env_loader}" >&2
    return 1
  }

  # shellcheck source=../../scripts/lib/load-operator-plane-env.sh
  source "${operator_artifacts_env_loader}"
  load_operator_plane_env "${env_file}" "${require_private_permissions}" "${operator_artifacts_required_env_keys[@]}"

  : "${OPERATOR_ARTIFACTS_NAMESPACE:=operator-artifacts}"
  : "${OPERATOR_ARTIFACTS_SERVICE_NAME:=operator-artifacts}"
  : "${OPERATOR_ARTIFACTS_TLS_CERT_RESOLVER:=letsencrypt}"
  : "${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME:=operator-artifacts-basicauth}"
  : "${OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME:=operator-artifacts-ip-allowlist}"

  [[ -n "${OPERATOR_DOMAIN:-}" ]] || {
    echo "ERROR: OPERATOR_DOMAIN must be set in operator-plane.env." >&2
    return 1
  }
  [[ -n "${OPERATOR_ARTIFACTS_TENANT_NAME:-}" ]] || {
    echo "ERROR: OPERATOR_ARTIFACTS_TENANT_NAME must be set in operator-plane.env." >&2
    return 1
  }

  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME="operator-artifacts.${OPERATOR_DOMAIN}"
  OPERATOR_ARTIFACTS_AUTH_USERNAME="${OPERATOR_ARTIFACTS_TENANT_NAME}"
}
