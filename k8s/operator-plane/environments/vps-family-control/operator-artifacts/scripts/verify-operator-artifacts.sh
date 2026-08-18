#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
env_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control"
artifacts_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/operator-artifacts"
env_file="${env_dir}/operator-plane.env"
env_helper="${script_dir}/lib/load-operator-artifacts-config.sh"
image_helper="${script_dir}/lib/resolve-operator-artifacts-image.sh"
lock_file="${env_dir}/dependencies.lock.json"

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

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"
command -v jq >/dev/null 2>&1 || fail "Missing required command: jq"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: verify-operator-artifacts.sh [--env-file <path>]"
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -f "${env_file}" ]] || fail "Missing central operator-plane env file: ${env_file}"
[[ -f "${env_helper}" ]] || fail "Missing operator-artifacts config helper: ${env_helper}"
[[ -f "${image_helper}" ]] || fail "Missing operator-artifacts image resolver: ${image_helper}"
# shellcheck source=lib/load-operator-artifacts-config.sh
source "${env_helper}"
# shellcheck source=lib/resolve-operator-artifacts-image.sh
source "${image_helper}"
load_operator_artifacts_env "${env_file}" "true"

required_vars=(
  OPERATOR_ARTIFACTS_NAMESPACE
  OPERATOR_ARTIFACTS_SERVICE_NAME
  OPERATOR_ARTIFACTS_PUBLIC_DIR
  OPERATOR_ARTIFACTS_PRIVATE_DIR
  OPERATOR_ARTIFACTS_TENANT_NAME
  OPERATOR_ARTIFACTS_AUTH_USERNAME
  OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME
  OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done
expected_container_image="$(resolve_operator_artifacts_image "${lock_file}")"

echo "Verifying operator-artifacts resources."
echo "Namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}"
echo "Service name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}"

deployment_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get deployment "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
service_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get service "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
ingressroute_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get ingressroute "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
pods_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get pods \
  -l "app.kubernetes.io/name=${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o json)"

container_image="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.containers[]? | select(.name == "nginx") | .image')"
[[ "${container_image}" = *@sha256:* ]] || fail "Nginx container image is not digest-pinned: ${container_image}"
[[ "${container_image}" = "${expected_container_image}" ]] || fail "Unexpected nginx container image: ${container_image}"
echo "Container image: ${container_image}"

container_port="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.containers[]? | select(.name == "nginx") | .ports[]? | select(.name == "http") | .containerPort')"
[[ "${container_port}" = "8080" ]] || fail "Unexpected nginx http container port: ${container_port}"
echo "Container http port: ${container_port}"

service_type="$(printf '%s\n' "${service_json}" | jq -r '.spec.type')"
[[ "${service_type}" = "ClusterIP" ]] || fail "Service type is ${service_type}, expected ClusterIP."
echo "Service type: ${service_type}"

service_port="$(printf '%s\n' "${service_json}" | jq -r '.spec.ports[]? | select(.name == "http") | .port')"
[[ "${service_port}" = "80" ]] || fail "Unexpected Service http port: ${service_port}"
echo "Service http port: ${service_port}"

basicauth_middleware_name="${OPERATOR_ARTIFACTS_SERVICE_NAME}-basicauth"
first_middleware="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].middlewares[0].name // ""')"
second_middleware="$(printf '%s\n' "${ingressroute_json}" | jq -r '.spec.routes[0].middlewares[1].name // ""')"
[[ "${first_middleware}" = "${OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME}" ]] || fail "IngressRoute does not apply IPAllowList before BasicAuth."
[[ "${second_middleware}" = "${basicauth_middleware_name}" ]] || fail "IngressRoute does not apply BasicAuth after IPAllowList."
echo "IngressRoute middleware order: IPAllowList before BasicAuth."

deployment_available="$(printf '%s\n' "${deployment_json}" | jq -r 'any(.status.conditions[]?; .type == "Available" and .status == "True")')"
[[ "${deployment_available}" = "true" ]] || fail "Deployment is not Available."
echo "Deployment is Available."

echo "Safe pod metadata:"
printf '%s\n' "${pods_json}" | jq -r '
  .items[]?
  | {
      name: .metadata.name,
      phase: .status.phase,
      ready: ((.status.conditions[]? | select(.type == "Ready") | .status) // "Unknown"),
      restarts: ([.status.containerStatuses[]?.restartCount] | add // 0),
      waiting_reason: ((.status.containerStatuses[]?.state.waiting.reason) // "")
    }
  | "  name=\(.name) phase=\(.phase) ready=\(.ready) restarts=\(.restarts)"
'

ready_pods="$(printf '%s\n' "${pods_json}" | jq -r '.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .metadata.name')"
[[ -n "${ready_pods}" ]] || fail "No matching operator-artifacts pod has Ready=True."

bad_pods="$(printf '%s\n' "${pods_json}" | jq -r '
  .items[]?
  | {
      name: .metadata.name,
      phase: .status.phase,
      ready: ((.status.conditions[]? | select(.type == "Ready") | .status) // "Unknown"),
      waiting_reason: ((.status.containerStatuses[]?.state.waiting.reason) // "")
    }
  | select(.phase != "Running" or .phase == "Error" or .phase == "Pending" or .ready != "True" or .waiting_reason == "CrashLoopBackOff")
  | .name
')"
[[ -z "${bad_pods}" ]] || fail "One or more operator-artifacts pods are not Running, Error, Pending, CrashLoopBackOff, or not Ready."

kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get middleware "${OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
echo "IPAllowList Middleware exists."

kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get middleware "${basicauth_middleware_name}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
echo "BasicAuth Middleware exists."

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

host_paths="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.volumes[]? | select(.hostPath != null) | .hostPath.path')"
runtime_empty_dir_mounts="$(printf '%s\n' "${deployment_json}" | jq -r '
  .spec.template.spec as $pod
  | $pod.containers[]?
  | select(.name == "nginx")
  | .volumeMounts[]?
  | . as $mount
  | select($mount.mountPath == "/var/cache/nginx" or $mount.mountPath == "/var/run" or $mount.mountPath == "/tmp" or $mount.mountPath == "/var/log/nginx")
  | select(any($pod.volumes[]?; .name == $mount.name and .emptyDir != null))
  | $mount.mountPath
')"

echo "Safe Deployment hostPath metadata:"
printf '%s\n' "${host_paths}" | sed 's/^/  /'

if printf '%s\n' "${host_paths}" | grep -Fxq "${OPERATOR_ARTIFACTS_PRIVATE_DIR}"; then
  fail "Deployment mounts the private artifact directory, which is not allowed."
fi

if ! printf '%s\n' "${host_paths}" | grep -Fxq "${OPERATOR_ARTIFACTS_PUBLIC_DIR}"; then
  fail "Deployment does not mount the expected public artifact directory."
fi

public_mount_read_only="$(printf '%s\n' "${deployment_json}" | jq -r --arg public_dir "${OPERATOR_ARTIFACTS_PUBLIC_DIR}" '
  .spec.template.spec as $pod
  | ($pod.volumes[]? | select(.hostPath.path == $public_dir) | .name) as $public_volume
  | if $public_volume == null then "false"
    else
      any($pod.containers[]? | select(.name == "nginx") | .volumeMounts[]?;
        .name == $public_volume and .mountPath == "/usr/share/nginx/html" and .readOnly == true)
    end
')"
[[ "${public_mount_read_only}" = "true" ]] || fail "Public artifact hostPath is not mounted read-only at /usr/share/nginx/html."
echo "Public artifact hostPath is mounted read-only."

unexpected_host_paths="$(printf '%s\n' "${host_paths}" | grep -Fxv "${OPERATOR_ARTIFACTS_PUBLIC_DIR}" || true)"
if [[ -n "${unexpected_host_paths}" ]]; then
  echo "Unexpected hostPath mounts:" >&2
  printf '%s\n' "${unexpected_host_paths}" >&2
  exit 1
fi

required_runtime_mounts=(
  /var/cache/nginx
  /var/run
  /tmp
  /var/log/nginx
)

echo "Nginx writable runtime emptyDir mounts:"
for mount_path in "${required_runtime_mounts[@]}"; do
  if ! printf '%s\n' "${runtime_empty_dir_mounts}" | grep -Fxq "${mount_path}"; then
    fail "Missing nginx emptyDir runtime mount: ${mount_path}"
  fi
  echo "  ${mount_path}"
done

echo "Private artifact directory is not mounted."
echo "operator-artifacts verification completed."
echo
echo "Safe curl examples, using placeholders only:"
echo "  From an allowed IP without credentials, expect HTTP 401:"
echo "  curl -o /dev/null -s -w '%{http_code}\n' https://${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt"
echo "  From a non-allowed IP, expect HTTP 403:"
echo "  curl -o /dev/null -s -w '%{http_code}\n' https://${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt"
echo "  From an allowed IP with valid BasicAuth, expect HTTP 200:"
echo "  curl -fsS -u '${OPERATOR_ARTIFACTS_AUTH_USERNAME}:<token>' https://${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt"
echo "  curl -fsS -u '${OPERATOR_ARTIFACTS_AUTH_USERNAME}:<token>' https://${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}/tenants/${OPERATOR_ARTIFACTS_TENANT_NAME}/README.txt.sha256"
echo
echo "Do not paste real tokens, htpasswd contents, Kubernetes Secret data, or curl commands containing real credentials."
