#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
parser_lib="${script_dir}/../scripts/lib/bootstrap-secrets-parser.sh"

# shellcheck source=../scripts/lib/bootstrap-secrets-parser.sh
source "${parser_lib}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

write_valid_file() {
  local path="$1"

  cat > "${path}" <<'EOF'
# Placeholder test values only.
OVH_ENDPOINT=placeholder-endpoint
OVH_APPLICATION_KEY=placeholder-application-key
OVH_APPLICATION_SECRET=placeholder-application-secret
OVH_CONSUMER_KEY=placeholder-consumer-key
OPERATOR_ARTIFACTS_FAMILY_INFRA_01_USERNAME=placeholder-user
OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN=placeholder-token
OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME=placeholder-hostname
OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES=placeholder-ranges
EOF
}

expect_success() {
  local name="$1"
  local path="$2"

  if parse_bootstrap_secrets_file "${path}" >/dev/null 2>&1; then
    echo "OK: ${name}"
  else
    echo "FAIL: ${name}" >&2
    exit 1
  fi
}

expect_failure() {
  local name="$1"
  local path="$2"

  if parse_bootstrap_secrets_file "${path}" >/dev/null 2>&1; then
    echo "FAIL: ${name}" >&2
    exit 1
  fi

  echo "OK: ${name}"
}

valid_file="${tmp_dir}/valid.env"
write_valid_file "${valid_file}"
expect_success "valid file with placeholder values" "${valid_file}"

duplicate_file="${tmp_dir}/duplicate.env"
write_valid_file "${duplicate_file}"
printf '%s\n' 'OVH_ENDPOINT=another-placeholder' >> "${duplicate_file}"
expect_failure "duplicate key rejection" "${duplicate_file}"

unknown_file="${tmp_dir}/unknown.env"
write_valid_file "${unknown_file}"
printf '%s\n' 'UNKNOWN_KEY=placeholder' >> "${unknown_file}"
expect_failure "unknown key rejection" "${unknown_file}"

derived_users_file="${tmp_dir}/derived-users.env"
write_valid_file "${derived_users_file}"
printf '%s\n' 'OPERATOR_ARTIFACTS_FAMILY_INFRA_01_USERS=placeholder-users-line' >> "${derived_users_file}"
expect_failure "derived users key rejection" "${derived_users_file}"

export_file="${tmp_dir}/export.env"
write_valid_file "${export_file}"
printf '%s\n' 'export OVH_ENDPOINT=placeholder' >> "${export_file}"
expect_failure "export syntax rejection" "${export_file}"

command_substitution_file="${tmp_dir}/command-substitution.env"
write_valid_file "${command_substitution_file}"
printf '%s\n' 'OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN=$(placeholder-command)' >> "${command_substitution_file}"
expect_failure "command substitution rejection" "${command_substitution_file}"

backtick_file="${tmp_dir}/backtick.env"
write_valid_file "${backtick_file}"
printf '%s\n' 'OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN=`placeholder-command`' >> "${backtick_file}"
expect_failure "backtick rejection" "${backtick_file}"

missing_required_file="${tmp_dir}/missing-required.env"
grep -v '^OVH_CONSUMER_KEY=' "${valid_file}" > "${missing_required_file}"
expect_failure "missing required key rejection" "${missing_required_file}"

empty_required_file="${tmp_dir}/empty-required.env"
write_valid_file "${empty_required_file}"
sed -i 's/^OVH_CONSUMER_KEY=.*/OVH_CONSUMER_KEY=/' "${empty_required_file}"
expect_failure "empty required key rejection" "${empty_required_file}"

echo "bootstrap secrets parser tests passed."
