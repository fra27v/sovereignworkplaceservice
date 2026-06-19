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

print_rollout_troubleshooting() {
  cat <<EOF
Rollout did not complete successfully. Safe troubleshooting commands:
  kubectl -n ${OPERATOR_ARTIFACTS_NAMESPACE} get pods -o wide
  kubectl -n ${OPERATOR_ARTIFACTS_NAMESPACE} logs deploy/${OPERATOR_ARTIFACTS_SERVICE_NAME} --tail=120
  kubectl -n ${OPERATOR_ARTIFACTS_NAMESPACE} describe pod -l app.kubernetes.io/name=${OPERATOR_ARTIFACTS_SERVICE_NAME}

Do not print or paste token values, htpasswd contents, Kubernetes Secret data, or rendered Secret material.
EOF
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
  OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

"${render_script}" --output "${rendered_file}"

kubectl apply -f "${rendered_file}"

echo "Waiting for operator-artifacts Deployment rollout."
if ! kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" rollout status deployment/"${OPERATOR_ARTIFACTS_SERVICE_NAME}" --timeout=180s; then
  print_rollout_troubleshooting
  exit 1
fi

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
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get middleware "${OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get middleware "${OPERATOR_ARTIFACTS_SERVICE_NAME}-basicauth" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers
kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get ingressroute "${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o custom-columns='NAME:.metadata.name' \
  --no-headers

deployment_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get deployment "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
service_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get service "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
ingressroute_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get ingressroute "${OPERATOR_ARTIFACTS_SERVICE_NAME}" -o json)"
pods_json="$(kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" get pods \
  -l "app.kubernetes.io/name=${OPERATOR_ARTIFACTS_SERVICE_NAME}" \
  -o json)"

container_image="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.containers[]? | select(.name == "nginx") | .image')"
[[ "${container_image}" = "nginxinc/nginx-unprivileged:stable-alpine" ]] || fail "Unexpected nginx container image: ${container_image}"
echo "Container image: ${container_image}"

container_port="$(printf '%s\n' "${deployment_json}" | jq -r '.spec.template.spec.containers[]? | select(.name == "nginx") | .ports[]? | select(.name == "http") | .containerPort')"
[[ "${container_port}" = "8080" ]] || fail "Unexpected nginx http container port: ${container_port}"
echo "Container http port: ${container_port}"

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
[[ -z "${bad_pods}" ]] || fail "One or more operator-artifacts pods are not healthy."

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

echo "operator-artifacts resources are installed and hostPath mounts are limited to the public directory."
cleanup
echo "Temporary rendered manifest was removed."
echo "Secret data and htpasswd contents were not printed."
