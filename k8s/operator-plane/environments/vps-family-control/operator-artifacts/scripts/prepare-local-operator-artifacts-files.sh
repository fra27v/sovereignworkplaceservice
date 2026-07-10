#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/../.." && pwd)"
env_file="${env_dir}/operator-plane.env"
env_helper="${script_dir}/lib/load-operator-artifacts-config.sh"

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
    --help|-h)
      echo "Usage: prepare-local-operator-artifacts-files.sh [--env-file <path>]"
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root because it writes under /var/lib."
[[ -f "${env_file}" ]] || fail "Missing central operator-plane env file: ${env_file}"
[[ -f "${env_helper}" ]] || fail "Missing operator-artifacts config helper: ${env_helper}"
# shellcheck source=lib/load-operator-artifacts-config.sh
source "${env_helper}"
load_operator_artifacts_env "${env_file}" "true"

required_vars=(
  OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME
  OPERATOR_ARTIFACTS_NAMESPACE
  OPERATOR_ARTIFACTS_LOCAL_ROOT
  OPERATOR_ARTIFACTS_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

tenant_public_dir="${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}"
tokens_dir="${OPERATOR_ARTIFACTS_PRIVATE_DIR}/tokens"
dummy_artifact="${tenant_public_dir}/README.txt"
dummy_checksum="${tenant_public_dir}/README.txt.sha256"

echo "Preparing local operator artifact directories."
install -d -o root -g root -m 0755 "${OPERATOR_ARTIFACTS_PUBLIC_DIR}"
install -d -o root -g root -m 0755 "${OPERATOR_ARTIFACTS_PUBLIC_DIR}/tenants"
install -d -o root -g root -m 0755 "${tenant_public_dir}"
install -d -o root -g root -m 0700 "${OPERATOR_ARTIFACTS_PRIVATE_DIR}"
install -d -o root -g root -m 0700 "${tokens_dir}"

if [[ ! -e "${dummy_artifact}" ]]; then
  cat > "${dummy_artifact}" <<'README'
This is a non-secret placeholder artifact for the operator artifact repository.
README
fi

chown root:root "${dummy_artifact}"
chmod 0644 "${dummy_artifact}"
(
  cd "${tenant_public_dir}"
  sha256sum README.txt > README.txt.sha256
)
chown root:root "${dummy_checksum}"
chmod 0644 "${dummy_checksum}"

echo "Safe directory metadata:"
find "${OPERATOR_ARTIFACTS_LOCAL_ROOT}" -maxdepth 4 -type d -ls

echo "Safe public tenant artifact metadata:"
ls -l "${tenant_public_dir}"

echo "Safe private token directory metadata:"
ls -ld "${tokens_dir}"

echo "Local operator artifact storage is prepared."
echo "No certificates or tokens were created by this script."
