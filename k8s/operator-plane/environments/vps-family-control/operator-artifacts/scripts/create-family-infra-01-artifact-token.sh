#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="${script_dir}/../operator-artifacts.env"
env_template="${script_dir}/../operator-artifacts.env.example"
force="false"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

missing_env_file() {
  cat >&2 <<EOF
Missing operator artifacts environment file:
  ${env_file}

Create it from the template:
  cp ${env_template} ${env_file}

Then edit:
  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME

The real operator-artifacts.env file is intentionally gitignored and must not be committed.
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
    --force)
      force="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--force]"
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
[[ -f "${env_file}" ]] || missing_env_file

# shellcheck source=/dev/null
source "${env_file}"

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
  [[ ! -e "${token_file}" ]] || fail "Refusing to overwrite existing token file: ${token_file}"
  [[ ! -e "${htpasswd_file}" ]] || fail "Refusing to overwrite existing htpasswd file: ${htpasswd_file}"
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
