#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="${script_dir}/../operator-artifacts.env"
env_template="${script_dir}/../operator-artifacts.env.example"

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

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root because it writes under /var/lib."
[[ -f "${env_file}" ]] || missing_env_file

# shellcheck source=/dev/null
source "${env_file}"

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
dummy_checksum="${dummy_artifact}.sha256"

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
sha256sum "${dummy_artifact}" > "${dummy_checksum}"
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
