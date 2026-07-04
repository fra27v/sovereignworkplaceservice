#!/usr/bin/env bash

operator_plane_env_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
operator_plane_env_root="$(cd -- "${operator_plane_env_lib_dir}/../.." && pwd)"
operator_plane_default_env_file="${operator_plane_env_root}/operator-plane.env"

operator_plane_allowed_env_keys=(
  OPERATOR_DOMAIN
  KUBERNETES_CLUSTER_DNS_SUFFIX
  OPENBAO_NAMESPACE
  OPENBAO_POD_NAME
  OPENBAO_SERVICE_NAME
  OPENBAO_BOOTSTRAP_INIT_FILE
  OPENBAO_PKI_MOUNT
  OPENBAO_OPERATOR_CA_COMMON_NAME
  OPENBAO_OPERATOR_CA_TTL
  OPENBAO_OPERATOR_VAULT_ROLE
  OPENBAO_OPERATOR_VAULT_TTL
  OPENBAO_OPERATOR_VAULT_IP_SANS
  OPERATOR_PKI_PUBLIC_DIR
  OPENBAO_TLS_DIR
)

operator_plane_env_fail() {
  echo "ERROR: $*" >&2
  exit 1
}

operator_plane_env_file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

operator_plane_env_check_private_file_permissions() {
  local path="$1"
  local mode mode_value

  mode="$(operator_plane_env_file_mode "${path}")"
  mode_value=$((8#${mode}))
  if (( (mode_value & 077) != 0 || (mode_value & 100) != 0 )); then
    operator_plane_env_fail "File permissions are too open (${mode}); expected 0600 or 0400: ${path}"
  fi
}

operator_plane_env_sudo_user_home() {
  local sudo_user="${SUDO_USER:-}"
  local passwd_entry

  [[ -n "${sudo_user}" ]] || return 1
  [[ "${sudo_user}" != "root" ]] || return 1

  command -v getent >/dev/null 2>&1 || operator_plane_env_fail "Missing required command for sudo user home lookup: getent"
  passwd_entry="$(getent passwd "${sudo_user}")" || operator_plane_env_fail "Could not resolve home directory for sudo user: ${sudo_user}"
  printf '%s' "${passwd_entry}" | awk -F: '{print $6}'
}

operator_plane_env_default_openbao_bootstrap_init_file() {
  local sudo_home

  if sudo_home="$(operator_plane_env_sudo_user_home)"; then
    printf '%s/openbao-bootstrap/openbao-global/openbao-global-init.json' "${sudo_home}"
    return 0
  fi

  printf '%s/openbao-bootstrap/openbao-global/openbao-global-init.json' "${HOME}"
}

operator_plane_env_resolve_openbao_bootstrap_init_file() {
  local path="${OPENBAO_BOOTSTRAP_INIT_FILE:-}"

  if [[ -z "${path}" ]]; then
    path="$(operator_plane_env_default_openbao_bootstrap_init_file)"
  fi

  [[ -f "${path}" ]] || operator_plane_env_fail "Missing OpenBao bootstrap init file: ${path}"
  operator_plane_env_check_private_file_permissions "${path}"
  printf '%s' "${path}"
}

operator_plane_env_openbao_operator_ca_bundle_in_pod() {
  printf '%s' "/openbao/tls/operator-ca-bundle.pem"
}

operator_plane_env_openbao_bootstrap_cacert_in_pod() {
  printf '%s' "/openbao/tls/tls.crt"
}

operator_plane_env_openbao_client_cacert_in_pod() {
  # During bootstrap, tls.crt is the self-signed leaf and may be usable as a
  # trust anchor. After Operator PKI rotation, tls.crt is only the leaf
  # certificate and operator-ca-bundle.pem is the correct client CA bundle.
  # Callers that run inside the OpenBao pod should prefer this path and fall
  # back to operator_plane_env_openbao_bootstrap_cacert_in_pod only when the
  # bundle is not present yet.
  operator_plane_env_openbao_operator_ca_bundle_in_pod
}

operator_plane_env_key_allowed() {
  local key="$1"
  local allowed

  for allowed in "${operator_plane_allowed_env_keys[@]}"; do
    [[ "${key}" == "${allowed}" ]] && return 0
  done

  return 1
}

operator_plane_env_parse_value() {
  local value="$1"

  if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "${value}"
}

load_operator_plane_env() {
  local path="$1"
  local require_private_permissions="${2:-true}"
  shift
  if [[ "$#" -gt 0 ]]; then
    shift
  fi
  local required_keys=("$@")
  local line key value parsed_value
  declare -A seen_keys=()

  [[ -f "${path}" ]] || operator_plane_env_fail "Missing env file: ${path}"
  if [[ "${require_private_permissions}" = "true" ]]; then
    operator_plane_env_check_private_file_permissions "${path}"
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" != *"="* ]] && operator_plane_env_fail "Invalid env line without '=': ${line}"
    [[ "${line}" =~ ^[[:space:]]*export[[:space:]]+ ]] && operator_plane_env_fail "Do not use export in ${path}."
    [[ "${line}" == *'$('* || "${line}" == *'`'* ]] && operator_plane_env_fail "Command substitution is not allowed in ${path}."

    key="${line%%=*}"
    value="${line#*=}"
    [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || operator_plane_env_fail "Invalid env key: ${key}"
    operator_plane_env_key_allowed "${key}" || operator_plane_env_fail "Unknown key in env file: ${key}"
    [[ -z "${seen_keys[${key}]+x}" ]] || operator_plane_env_fail "Duplicate env key: ${key}"
    seen_keys["${key}"]=1
    parsed_value="$(operator_plane_env_parse_value "${value}")"
    printf -v "${key}" '%s' "${parsed_value}"
  done < "${path}"

  for key in "${required_keys[@]}"; do
    [[ -n "${!key:-}" ]] || operator_plane_env_fail "Missing or empty required env key: ${key}"
  done

  derive_operator_plane_env
}

derive_operator_plane_env() {
  [[ -n "${OPERATOR_DOMAIN:-}" ]] || return 0
  [[ -n "${OPENBAO_SERVICE_NAME:-}" ]] || return 0
  [[ -n "${OPENBAO_NAMESPACE:-}" ]] || return 0
  [[ -n "${KUBERNETES_CLUSTER_DNS_SUFFIX:-}" ]] || return 0

  OPERATOR_VAULT_HOSTNAME="operator-vault.${OPERATOR_DOMAIN}"
  OPERATOR_ARTIFACTS_HOSTNAME="operator-artifacts.${OPERATOR_DOMAIN}"
  OPENBAO_INTERNAL_DNS_NAMES="${OPENBAO_SERVICE_NAME},${OPENBAO_SERVICE_NAME}.${OPENBAO_NAMESPACE},${OPENBAO_SERVICE_NAME}.${OPENBAO_NAMESPACE}.svc,${OPENBAO_SERVICE_NAME}.${OPENBAO_NAMESPACE}.svc.${KUBERNETES_CLUSTER_DNS_SUFFIX}"
  OPENBAO_OPERATOR_VAULT_COMMON_NAME="${OPERATOR_VAULT_HOSTNAME}"
  OPENBAO_OPERATOR_VAULT_ALT_NAMES="${OPERATOR_VAULT_HOSTNAME},${OPENBAO_INTERNAL_DNS_NAMES},localhost"
}
