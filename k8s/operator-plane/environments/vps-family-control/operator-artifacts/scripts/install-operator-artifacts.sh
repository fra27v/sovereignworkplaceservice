#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
artifacts_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/operator-artifacts"
env_file="${artifacts_dir}/operator-artifacts.env"
env_template="${artifacts_dir}/operator-artifacts.env.example"
render_script="${script_dir}/render-operator-artifacts.sh"
rendered_file="$(mktemp /tmp/operator-artifacts.install.XXXXXX.yaml)"
chmod 0600 "${rendered_file}"

cleanup() {
  if [[ -n "${rendered_file}" && -f "${rendered_file}" ]]; then
    rm -f "${rendered_file}"
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

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"
command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"
[[ -f "${env_file}" ]] || missing_env_file

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  OPERATOR_ARTIFACTS_NAMESPACE
  OPERATOR_ARTIFACTS_SERVICE_NAME
  OPERATOR_ARTIFACTS_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

"${render_script}" --output "${rendered_file}"

kubectl apply -f "${rendered_file}"

echo "Verifying operator-artifacts resources."
kubectl get namespace "${OPERATOR_ARTIFACTS_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get deployment "${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get service "${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,PORT:.spec.ports[0].port' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get middleware "${OPERATOR_ARTIFACTS_SERVICE_NAME}-basicauth" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get ingressroute "${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers

deployment_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get deployment "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
host_paths="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.volumes[]? | select(.hostPath != null) | .hostPath.path')"

echo "Safe Deployment hostPath metadata:"
printf '%s\n' "${host_paths}" | sed 's/^/  /'

if printf '%s\n' "${host_paths}" | grep -Fxq "${OPERATOR_ARTIFACTS_PRIVATE_DIR}"; then
  fail "Deployment mounts the private artifact directory, which is not allowed."
fi

if ! printf '%s\n' "${host_paths}" | grep -Fxq "${OPERATOR_ARTIFACTS_PUBLIC_DIR}"; then
  fail "Deployment does not mount the expected public artifact directory."
fi

unexpected_host_paths="$(printf '%s\n' "${host_paths}" | grep -Fxv "${OPERATOR_ARTIFACTS_PUBLIC_DIR}" || true)"
if [[ -n "${unexpected_host_paths}" ]]; then
  echo "Unexpected hostPath mounts:" >&2
  printf '%s\n' "${unexpected_host_paths}" >&2
  exit 1
fi

echo "operator-artifacts resources are installed and hostPath mounts are limited to the public directory."
cleanup
echo "Temporary rendered manifest was removed."
echo "Secret data and htpasswd contents were not printed."
