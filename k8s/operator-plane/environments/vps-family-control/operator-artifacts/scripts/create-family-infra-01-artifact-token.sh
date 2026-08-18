#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_helper="${script_dir}/lib/load-operator-artifacts-config.sh"
force="false"

fail() {
  echo "ERROR: $*" >&2
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
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--env-file <path>] [--force]"
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root because it writes under /var/lib."
command -v htpasswd >/dev/null 2>&1 || fail "Missing required command: htpasswd"
command -v openssl >/dev/null 2>&1 || fail "Missing required command: openssl"

[[ -f "${env_file}" ]] || fail "Missing central operator-plane env file: ${env_file}"
[[ -f "${env_helper}" ]] || fail "Missing operator-artifacts config helper: ${env_helper}"
# shellcheck source=lib/load-operator-artifacts-config.sh
source "${env_helper}"
load_operator_artifacts_env "${env_file}" "true"

required_vars=(
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

[[ "${OPERATOR_ARTIFACTS_TENANT_NAME}" = "family-infra-01" ]] || fail "This script is only for family-infra-01."

tokens_dir="${OPERATOR_ARTIFACTS_PRIVATE_DIR}/tokens"
token_file="${tokens_dir}/family-infra-01.token"
htpasswd_file="${tokens_dir}/family-infra-01.htpasswd"

install -d -o root -g root -m 0700 "${tokens_dir}"

if [[ "${force}" != "true" ]]; then
  token_exists="false"
  htpasswd_exists="false"
  [[ ! -e "${token_file}" ]] || token_exists="true"
  [[ ! -e "${htpasswd_file}" ]] || htpasswd_exists="true"

  if [[ "${token_exists}" = "true" && "${htpasswd_exists}" = "true" ]]; then
    [[ -s "${token_file}" ]] || fail "Existing token file is empty: ${token_file}"
    [[ -s "${htpasswd_file}" ]] || fail "Existing htpasswd file is empty: ${htpasswd_file}"

    echo "Artifact token material for tenant family-infra-01 already exists; leaving it unchanged."
    echo "Token file: ${token_file}"
    echo "BasicAuth file: ${htpasswd_file}"
    echo "Safe file metadata:"
    ls -l "${token_file}" "${htpasswd_file}"
    echo "The token value and htpasswd contents were not printed."
    exit 0
  fi

  if [[ "${token_exists}" = "true" ]]; then
    fail "Refusing partial token material state: token file exists but htpasswd file is missing: ${token_file}"
  fi

  if [[ "${htpasswd_exists}" = "true" ]]; then
    fail "Refusing partial token material state: htpasswd file exists but token file is missing: ${htpasswd_file}"
  fi
fi

token="$(openssl rand -base64 48 | tr -d '\n')"
tmp_token="$(mktemp)"
tmp_htpasswd="$(mktemp)"
trap 'rm -f "${tmp_token}" "${tmp_htpasswd}"' EXIT

printf '%s\n' "${token}" > "${tmp_token}"
htpasswd -Bbn "${OPERATOR_ARTIFACTS_AUTH_USERNAME}" "${token}" > "${tmp_htpasswd}"

install -o root -g root -m 0600 "${tmp_token}" "${token_file}"
install -o root -g root -m 0600 "${tmp_htpasswd}" "${htpasswd_file}"

echo "Created artifact token material for tenant family-infra-01."
echo "Token file: ${token_file}"
echo "BasicAuth file: ${htpasswd_file}"
echo "Safe file metadata:"
ls -l "${token_file}" "${htpasswd_file}"
echo "The token value was not printed."
