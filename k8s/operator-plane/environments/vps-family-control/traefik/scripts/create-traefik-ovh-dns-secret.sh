#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
traefik_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/traefik"
acme_env_file="${traefik_dir}/traefik-acme-dns01.env"
acme_env_template="${traefik_dir}/traefik-acme-dns01.env.example"
ovh_env_file="${traefik_dir}/traefik-ovh-credentials.env"
ovh_env_template="${traefik_dir}/traefik-ovh-credentials.env.example"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

missing_env_file() {
  local env_file="$1"
  local env_template="$2"

  cat >&2 <<EOF
Missing Traefik environment file:
  ${env_file}

Create it from the template:
  cp ${env_template} ${env_file}

Then edit all required placeholder values before rerunning this script.

The real env file is intentionally gitignored and must not be committed.
EOF
  exit 1
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || fail "Missing required variable: ${name}"
  [[ "${value}" != "<set-me>" ]] || fail "Variable still has placeholder value: ${name}"
}

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"
[[ -f "${acme_env_file}" ]] || missing_env_file "${acme_env_file}" "${acme_env_template}"
[[ -f "${ovh_env_file}" ]] || missing_env_file "${ovh_env_file}" "${ovh_env_template}"

# shellcheck source=/dev/null
source "${acme_env_file}"
# shellcheck source=/dev/null
source "${ovh_env_file}"

required_vars=(
  TRAEFIK_NAMESPACE
  TRAEFIK_OVH_DNS_SECRET_NAME
  OVH_ENDPOINT
  OVH_APPLICATION_KEY
  OVH_APPLICATION_SECRET
  OVH_CONSUMER_KEY
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

kubectl -n "${TRAEFIK_NAMESPACE}" create secret generic "${TRAEFIK_OVH_DNS_SECRET_NAME}" \
  --from-literal=OVH_ENDPOINT="${OVH_ENDPOINT}" \
  --from-literal=OVH_APPLICATION_KEY="${OVH_APPLICATION_KEY}" \
  --from-literal=OVH_APPLICATION_SECRET="${OVH_APPLICATION_SECRET}" \
  --from-literal=OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

echo "Traefik OVH DNS Secret created or updated."
echo "Namespace: ${TRAEFIK_NAMESPACE}"
echo "Secret name: ${TRAEFIK_OVH_DNS_SECRET_NAME}"
echo "Secret keys:"
echo "  OVH_ENDPOINT"
echo "  OVH_APPLICATION_KEY"
echo "  OVH_APPLICATION_SECRET"
echo "  OVH_CONSUMER_KEY"
