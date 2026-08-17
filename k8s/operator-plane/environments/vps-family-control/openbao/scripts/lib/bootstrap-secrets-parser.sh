#!/usr/bin/env bash

bootstrap_secret_allowed_keys=(
  OVH_ENDPOINT
  OVH_APPLICATION_KEY
  OVH_APPLICATION_SECRET
  OVH_CONSUMER_KEY
  OPERATOR_ARTIFACTS_FAMILY_INFRA_01_TOKEN
)

bootstrap_secret_required_keys=("${bootstrap_secret_allowed_keys[@]}")

bootstrap_secrets_parser_fail() {
  echo "ERROR: $*" >&2
  return 1
}

bootstrap_secret_is_allowed_key() {
  local key="$1"
  local allowed_key

  for allowed_key in "${bootstrap_secret_allowed_keys[@]}"; do
    [[ "${key}" = "${allowed_key}" ]] && return 0
  done

  return 1
}

parse_bootstrap_secrets_file() {
  local env_file="$1"
  local line
  local line_number=0
  local key
  local value
  local required_key

  declare -gA BOOTSTRAP_SECRETS=()
  declare -ga BOOTSTRAP_SECRET_ACCEPTED_KEYS=()

  [[ -f "${env_file}" ]] || bootstrap_secrets_parser_fail "Missing env file: ${env_file}" || return 1

  # This parser intentionally does not source the env file. The bootstrap file
  # is data, not shell code, so parsing must not execute commands or expansion.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))

    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue

    case "${line}" in
      export\ *)
        bootstrap_secrets_parser_fail "Line ${line_number}: export syntax is not allowed." || return 1
        ;;
      *'$('*)
        bootstrap_secrets_parser_fail "Line ${line_number}: command substitution is not allowed." || return 1
        ;;
      *'`'*)
        bootstrap_secrets_parser_fail "Line ${line_number}: backticks are not allowed." || return 1
        ;;
      *$'\r'*)
        bootstrap_secrets_parser_fail "Line ${line_number}: carriage returns or multiline values are not allowed." || return 1
        ;;
    esac

    [[ "${line}" == *=* ]] || bootstrap_secrets_parser_fail "Line ${line_number}: expected KEY=VALUE." || return 1

    key="${line%%=*}"
    value="${line#*=}"

    [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || bootstrap_secrets_parser_fail "Line ${line_number}: invalid key name." || return 1
    bootstrap_secret_is_allowed_key "${key}" || bootstrap_secrets_parser_fail "Line ${line_number}: unknown key ${key}." || return 1
    [[ -z "${BOOTSTRAP_SECRETS[$key]+x}" ]] || bootstrap_secrets_parser_fail "Line ${line_number}: duplicate key ${key}." || return 1

    BOOTSTRAP_SECRETS["${key}"]="${value}"
    BOOTSTRAP_SECRET_ACCEPTED_KEYS+=("${key}")
  done < "${env_file}"

  for required_key in "${bootstrap_secret_required_keys[@]}"; do
    [[ -n "${BOOTSTRAP_SECRETS[$required_key]+x}" ]] || bootstrap_secrets_parser_fail "Missing required key: ${required_key}" || return 1
    [[ -n "${BOOTSTRAP_SECRETS[$required_key]}" ]] || bootstrap_secrets_parser_fail "Required key is empty: ${required_key}" || return 1
  done
}
