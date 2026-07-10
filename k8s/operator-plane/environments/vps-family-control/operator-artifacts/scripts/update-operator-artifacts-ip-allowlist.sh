#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_helper="${script_dir}/lib/load-operator-artifacts-config.sh"
install_script="${script_dir}/install-operator-artifacts.sh"
verify_script="${script_dir}/verify-operator-artifacts.sh"

home_ip=""
set_ranges=""
dry_run="false"
show_masked="false"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: update-operator-artifacts-ip-allowlist.sh [options]

Options:
  --home-ip <ipv4-or-cidr>              Replace the non-loopback home allowlist entry.
  --set-ranges <comma-separated-cidrs>  Replace the full allowlist.
  --env-file <path>                     Path to central operator-plane.env.
  --dry-run                            Show safe planned actions only.
  --show-masked                        Print current/proposed ranges with IPs masked.
  --help                               Show this help.

Examples:
  update-operator-artifacts-ip-allowlist.sh --home-ip <home-public-ip>
  update-operator-artifacts-ip-allowlist.sh --home-ip <home-public-ip>/32 --dry-run --show-masked
  update-operator-artifacts-ip-allowlist.sh --set-ranges '127.0.0.1/32,::1/128,<home-public-ip>/32'

Do not paste real public IPs, tokens, htpasswd contents, Secret data, or rendered manifests into chat, logs, tickets, or Git.
USAGE
}

normalize_ranges() {
  local raw="$1"

  printf '%s' "${raw}" | tr -d '[:space:]'
}

validate_ranges() {
  local ranges="$1"
  local entry
  local count=0

  [[ -n "${ranges}" ]] || fail "Allowlist ranges must not be empty."
  [[ "${ranges}" != *"<set-me>"* ]] || fail "Allowlist ranges must not contain <set-me>."

  IFS=',' read -r -a entries <<< "${ranges}"
  for entry in "${entries[@]}"; do
    [[ -n "${entry}" ]] || fail "Allowlist ranges contain an empty entry."
    [[ "${entry}" == */* ]] || fail "Every allowlist entry must include CIDR prefix syntax."
    count=$((count + 1))
  done

  [[ "${count}" -gt 0 ]] || fail "Allowlist ranges must contain at least one entry."
}

mask_range() {
  local entry="$1"
  local prefix="${entry##*/}"
  local address="${entry%/*}"

  if [[ "${address}" == *:* ]]; then
    printf '<ipv6>/%s' "${prefix}"
  else
    printf '<ipv4>/%s' "${prefix}"
  fi
}

mask_ranges() {
  local ranges="$1"
  local entry
  local separator=""

  IFS=',' read -r -a entries <<< "${ranges}"
  for entry in "${entries[@]}"; do
    printf '%s%s' "${separator}" "$(mask_range "${entry}")"
    separator=","
  done
}

normalize_home_ip() {
  local value="$1"

  [[ -n "${value}" ]] || fail "--home-ip requires a value."
  [[ "${value}" != "<set-me>" ]] || fail "--home-ip must not be <set-me>."

  if [[ "${value}" == */* ]]; then
    printf '%s' "${value}"
  else
    printf '%s/32' "${value}"
  fi
}

build_home_ranges() {
  local current_ranges="$1"
  local new_home_range="$2"

  validate_ranges "${current_ranges}"
  [[ "${new_home_range}" == */* ]] || fail "New home range must include CIDR prefix syntax."

  printf '127.0.0.1/32,::1/128,%s' "${new_home_range}"
}

update_env_file() {
  local new_ranges="$1"
  local timestamp
  local backup_file
  local temp_file

  if ! grep -q '^OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES=' "${env_file}"; then
    fail "OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES is missing from ${env_file}."
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_file="${env_file}.${timestamp}.bak"
  temp_file="$(mktemp "${env_file}.XXXXXX")"

  cp -p "${env_file}" "${backup_file}"
  awk -v new_value="OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES=\"${new_ranges}\"" '
    /^OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES=/ {
      print new_value
      next
    }
    { print }
  ' "${env_file}" > "${temp_file}"

  mv "${temp_file}" "${env_file}"
  chmod 0600 "${env_file}"

  echo "Updated operator-artifacts IP allowlist in the local env file."
  echo "Backup file: ${backup_file}"
  echo "Env file permissions set to 0600."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --home-ip)
      [[ $# -ge 2 ]] || fail "--home-ip requires a value."
      home_ip="$2"
      shift 2
      ;;
    --set-ranges)
      [[ $# -ge 2 ]] || fail "--set-ranges requires a value."
      set_ranges="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --show-masked)
      show_masked="true"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -f "${env_file}" ]] || fail "Missing central operator-plane env file: ${env_file}"
[[ -f "${env_helper}" ]] || fail "Missing operator-artifacts config helper: ${env_helper}"

if [[ -n "${home_ip}" && -n "${set_ranges}" ]]; then
  fail "Use either --home-ip or --set-ranges, not both."
fi

if [[ -z "${home_ip}" && -z "${set_ranges}" ]]; then
  fail "Specify --home-ip or --set-ranges."
fi

# shellcheck source=lib/load-operator-artifacts-config.sh
source "${env_helper}"
load_operator_artifacts_env "${env_file}" "true"

current_ranges="$(normalize_ranges "${OPERATOR_ARTIFACTS_ALLOWED_SOURCE_RANGES:-}")"
validate_ranges "${current_ranges}"

if [[ -n "${set_ranges}" ]]; then
  proposed_ranges="$(normalize_ranges "${set_ranges}")"
else
  new_home_range="$(normalize_home_ip "${home_ip}")"
  proposed_ranges="$(build_home_ranges "${current_ranges}" "${new_home_range}")"
fi

validate_ranges "${proposed_ranges}"

echo "Prepared operator-artifacts IP allowlist update."
echo "Real IP ranges are not printed by default."

if [[ "${show_masked}" = "true" ]]; then
  echo "Current ranges, masked: $(mask_ranges "${current_ranges}")"
  echo "Proposed ranges, masked: $(mask_ranges "${proposed_ranges}")"
fi

if [[ "${dry_run}" = "true" ]]; then
  echo "Dry run only. No files were changed and install/verify were not run."
else
  update_env_file "${proposed_ranges}"
  echo "Applying operator-artifacts deployment with updated allowlist."
  "${install_script}" --env-file "${env_file}"
  echo "Verifying operator-artifacts deployment after allowlist update."
  "${verify_script}" --env-file "${env_file}"
fi

cat <<'EOF'
Safe next-step test examples, using placeholders only:
  Allowed home IP without credentials should return HTTP 401.
  Allowed home IP with valid BasicAuth should download successfully.
  Non-allowed public path should return HTTP 403.

Do not paste real tokens, htpasswd contents, Kubernetes Secret data, rendered manifests, or curl commands containing real credentials.
EOF
