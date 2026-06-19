#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
artifacts_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/operator-artifacts"
env_file="${artifacts_dir}/operator-artifacts.env"
env_template="${artifacts_dir}/operator-artifacts.env.example"

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
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME
  OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

echo "Verifying operator-artifacts resources."
echo "Namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}"
echo "Service name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}"

pods_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get pods \
  -l "app.kubernetes.io/name=${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o json)"

running_pods="$(printf '%s\n' "${pods_json}" | jq -r '.items[]? | select(.status.phase == "Running") | .metadata.name')"
if [[ -z "${running_pods}" ]]; then
  kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get pods \
    -l "app.kubernetes.io/name=${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' \
    --no-headers
  fail "No operator-artifacts pod is Running."
fi

echo "Running pod metadata:"
printf '%s\n' "${running_pods}" | sed 's/^/  /'

service_type="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get service "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o jsonpath='{.spec.type}')"
[[ "${service_type}" = "ClusterIP" ]] || fail "Service type is ${service_type}, expected ClusterIP."
echo "Service type: ${service_type}"

kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get ingressroute "${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
echo "IngressRoute exists."

secret_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get secret "${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}" -o json)"
secret_type="$(printf '%s\n' "${secret_json}" | jq -r '.type')"
has_users_key="$(printf '%s\n' "${secret_json}" | jq -r 'if (.data.users // "") != "" then "yes" else "no" end')"

echo "BasicAuth Secret metadata:"
echo "  name: ${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}"
echo "  type: ${secret_type}"
echo "  expected key users present: ${has_users_key}"
[[ "${has_users_key}" = "yes" ]] || fail "BasicAuth Secret is missing the expected users key."

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

echo "Private artifact directory is not mounted."
echo "operator-artifacts verification completed."
echo
echo "Safe curl examples, using placeholders only:"
echo "  curl -fsS -u '${OPERATOR_ARTIFACTS_AUTH_USERNAME}:<token>' https://operator-artifacts.<domain>/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt"
echo "  curl -fsS -u '${OPERATOR_ARTIFACTS_AUTH_USERNAME}:<token>' https://operator-artifacts.<domain>/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt.sha256"
echo
echo "Do not paste real tokens, htpasswd contents, Kubernetes Secret data, or curl commands containing real credentials."
