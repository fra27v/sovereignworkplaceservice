#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
artifacts_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/operator-artifacts"
env_file="${artifacts_dir}/operator-artifacts.env"
env_template="${artifacts_dir}/operator-artifacts.env.example"
template_file="${artifacts_dir}/manifests/operator-artifacts.yaml.tpl"
keep_output="false"
explicit_output="false"
requested_output_file=""
output_file=""

cleanup() {
  if [[ "${keep_output}" != "true" && "${explicit_output}" != "true" && -n "${output_file}" && -f "${output_file}" ]]; then
    rm -f "${output_file}"
  fi
}
trap cleanup EXIT

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

Then edit all required placeholder values before rerunning this script.

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

yaml_escape_double_quoted() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/&/\\\&/g'
}

render_template() {
  sed \
    -e "s|\${OPERATOR_ARTIFACTS_NAMESPACE}|${OPERATOR_ARTIFACTS_NAMESPACE}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_SERVICE_NAME}|${OPERATOR_ARTIFACTS_SERVICE_NAME}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}|${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_PUBLIC_DIR}|${OPERATOR_ARTIFACTS_PUBLIC_DIR}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_TLS_CERT_RESOLVER}|${OPERATOR_ARTIFACTS_TLS_CERT_RESOLVER}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}|${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}|g" \
    -e "s|\${OPERATOR_ARTIFACTS_BASICAUTH_USERS_PLACEHOLDER}|${OPERATOR_ARTIFACTS_BASICAUTH_USERS}|g" \
    "${template_file}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-output)
      keep_output="true"
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output requires a path."
      explicit_output="true"
      requested_output_file="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: render-operator-artifacts.sh [--keep-output] [--output <path>]

Renders the operator-artifacts manifest to a temporary file and deletes it by
default. Use --keep-output to keep a non-predictable mktemp output file, or
--output to write a specific output path for a caller such as the install script.

Rendered manifests can contain BasicAuth Secret material. Do not print or paste
their contents.
USAGE
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -f "${env_file}" ]] || missing_env_file
[[ -f "${template_file}" ]] || fail "Missing template file: ${template_file}"

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  OPERATOR_ARTIFACTS_NAMESPACE
  OPERATOR_ARTIFACTS_SERVICE_NAME
  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME
  OPERATOR_ARTIFACTS_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME
  OPERATOR_ARTIFACTS_TLS_CERT_RESOLVER
  OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

htpasswd_file="${OPERATOR_ARTIFACTS_PRIVATE_DIR}/tokens/${OPERATOR_ARTIFACTS_TENANT_NAME}.htpasswd"
[[ -s "${htpasswd_file}" ]] || fail "Missing or empty htpasswd file: ${htpasswd_file}"

OPERATOR_ARTIFACTS_BASICAUTH_USERS="$(yaml_escape_double_quoted < "${htpasswd_file}")"

if [[ "${explicit_output}" = "true" ]]; then
  output_file="${requested_output_file}"
  rm -f "${output_file}"
else
  output_file="$(mktemp /tmp/operator-artifacts.XXXXXX.yaml)"
fi

render_template > "${output_file}"
chmod 0600 "${output_file}"

echo "Rendered operator-artifacts manifest."
echo "Output file: ${output_file}"
echo "Namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}"
echo "Service name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}"
echo "Public hostname: configured"
echo "Public directory: ${OPERATOR_ARTIFACTS_PUBLIC_DIR}"
echo "BasicAuth Secret name: ${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}"
echo "The htpasswd contents were not printed."
echo "Rendered Secret material was not printed."
echo "No manifest was applied."
if [[ "${keep_output}" = "true" ]]; then
  echo "WARNING: This rendered manifest may contain sensitive BasicAuth Secret material."
  echo "WARNING: Delete ${output_file} immediately after local inspection."
  echo "Kept rendered manifest permissions: 0600"
elif [[ "${explicit_output}" = "true" ]]; then
  echo "Output file permissions: 0600"
else
  echo "Temporary output will be removed after script completion. Use --keep-output to keep it for local inspection."
fi
