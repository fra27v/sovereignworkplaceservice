#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
env_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control"
env_file="${env_dir}/operator-plane.env"
env_helper="${script_dir}/lib/load-operator-artifacts-config.sh"
image_helper="${script_dir}/lib/resolve-operator-artifacts-image.sh"
lock_file="${env_dir}/dependencies.lock.json"
render_script="${script_dir}/render-operator-artifacts.sh"
rendered_file="$(mktemp /tmp/operator-artifacts.install.XXXXXX.yaml)"
dry_run="false"
wait_for_rollout="false"
chmod 0600 "${rendered_file}"

cleanup() {
  if [[ -n "${rendered_file}" && -f "${rendered_file}" ]]; then
    rm -f "${rendered_file}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: install-operator-artifacts.sh [--env-file <path>] [--dry-run] [--wait] [--help]

Renders and reconciles the operator-artifacts Kubernetes manifest.

Options:
  --env-file <path>  Path to operator-plane.env.
  --dry-run          Render and run kubectl server-side dry-run only.
  --wait             Wait for the operator-artifacts Deployment rollout after apply.
  --help             Show this help.

Safety:
  - Does not print rendered Secret material or htpasswd contents.
  - Refuses rendered nginx images that are not digest-pinned.
  - Removes the temporary rendered manifest on exit.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || fail "Missing required variable: ${name}"
  [[ "${value}" != "<set-me>" ]] || fail "Variable still has placeholder value: ${name}"
}

rendered_nginx_image() {
  awk '
    $0 ~ /^[[:space:]]*-[[:space:]]*name:[[:space:]]*nginx[[:space:]]*$/ { in_nginx = 1; next }
    in_nginx && $0 ~ /^[[:space:]]*image:[[:space:]]*/ {
      sub(/^[[:space:]]*image:[[:space:]]*/, "")
      gsub(/"/, "")
      print
      exit
    }
  ' "${rendered_file}"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ "$#" -ge 2 ]] || fail "--env-file requires a path."
      env_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --wait)
      wait_for_rollout="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command kubectl
require_command jq
require_command awk

[[ -f "${env_file}" ]] || fail "Missing central operator-plane env file: ${env_file}"
[[ -f "${env_helper}" ]] || fail "Missing operator-artifacts config helper: ${env_helper}"
[[ -f "${image_helper}" ]] || fail "Missing operator-artifacts image resolver: ${image_helper}"
[[ -x "${render_script}" ]] || fail "Missing executable render script: ${render_script}"

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
  OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME
  OPERATOR_ARTIFACTS_IP_ALLOWLIST_MIDDLEWARE_NAME
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

expected_container_image="$(resolve_operator_artifacts_image "${lock_file}")"

"${render_script}" --env-file "${env_file}" --output "${rendered_file}"

container_image="$(rendered_nginx_image)"
[[ -n "${container_image}" ]] || fail "Rendered manifest does not contain the nginx container image."
[[ "${container_image}" = *@sha256:* ]] || fail "Rendered nginx image is not digest-pinned: ${container_image}"
[[ "${container_image}" = "${expected_container_image}" ]] || fail "Rendered nginx image does not match dependency lock: ${container_image}"

echo "Prepared operator-artifacts reconciliation."
echo "Namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}"
echo "Service name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}"
echo "Public hostname: configured"
echo "Public directory: ${OPERATOR_ARTIFACTS_PUBLIC_DIR}"
echo "Nginx image: ${container_image}"
echo "BasicAuth Secret name: ${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}"
echo "Rendered manifest path: ${rendered_file}"
echo "Rendered Secret material and htpasswd contents were not printed."

if [[ "${dry_run}" = "true" ]]; then
  echo "DRY-RUN: running kubectl server-side apply dry-run."
  kubectl apply --dry-run=server -f "${rendered_file}" >/dev/null
  echo "DRY-RUN: operator-artifacts reconciliation passed server-side validation."
  exit 0
fi

echo "Applying operator-artifacts manifest."
kubectl apply -f "${rendered_file}"

if [[ "${wait_for_rollout}" = "true" ]]; then
  echo "Waiting for operator-artifacts Deployment rollout."
  kubectl -n "${OPERATOR_ARTIFACTS_NAMESPACE}" rollout status deployment/"${OPERATOR_ARTIFACTS_SERVICE_NAME}" --timeout=180s
else
  echo "Apply completed. Rollout wait was not requested."
fi

echo "operator-artifacts reconciliation completed."
echo "Temporary rendered manifest will be removed."
