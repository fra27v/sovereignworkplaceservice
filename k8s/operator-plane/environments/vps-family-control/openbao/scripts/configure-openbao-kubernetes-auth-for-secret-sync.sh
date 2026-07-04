#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"

namespace="openbao-operator"
auth_path="kubernetes"
role_name="operator-plane-secret-sync"
policy_name="operator-plane-secret-sync"
policy_file="${repo_root}/k8s/operator-plane/openbao/policies/operator-plane-secret-sync.hcl"
bound_service_account_name="operator-plane-secret-sync"
bound_service_account_namespace="operator-secret-sync"
role_ttl="15m"
init_file="${HOME}/openbao-bootstrap/openbao-global/openbao-global-init.json"
vault_addr="https://127.0.0.1:8200"
vault_cacert="/openbao/tls/tls.crt"
bao_addr="${vault_addr}"
bao_cacert="${vault_cacert}"

usage() {
  cat <<EOF
Usage: $0 [--init-file <path>]

Configure Global OpenBao Kubernetes auth for the in-cluster operator-plane
secret sync Job.

Options:
  --init-file <path>  OpenBao init JSON containing a bootstrap/admin token.
                     Defaults to ${init_file}
  --help             Show this help.

Safety:
  - Does not print OpenBao tokens or Kubernetes ServiceAccount tokens.
  - Does not create long-lived reviewer tokens.
  - Does not store OpenBao tokens in Kubernetes Secrets.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

file_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

discover_openbao_pod() {
  kubectl -n "${namespace}" get pods -o json | jq -r '
    .items[]
    | select(.metadata.name | startswith("openbao-global"))
    | select(.status.phase == "Running")
    | .metadata.name
  ' | head -n 1
}

discover_openbao_service_account() {
  local pod_name="$1"
  kubectl -n "${namespace}" get pod "${pod_name}" -o jsonpath='{.spec.serviceAccountName}'
}

token_exec() {
  local token="$1"
  shift

  printf '%s' "${token}" | kubectl -n "${namespace}" exec -i "${openbao_pod}" -- \
    sh -c 'IFS= read -r BAO_TOKEN; export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"; shift 4; "$@"' \
    sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "$@"
}

token_exec_with_policy_file() {
  local token="$1"
  local policy_path="$2"
  local target_policy_name="$3"

  {
    printf '%s\n' "${token}"
    cat "${policy_path}"
  } | kubectl -n "${namespace}" exec -i "${openbao_pod}" -- \
    sh -c '
      IFS= read -r BAO_TOKEN
      export BAO_TOKEN VAULT_TOKEN="$BAO_TOKEN" VAULT_ADDR="$1" VAULT_CACERT="$2" BAO_ADDR="$3" BAO_CACERT="$4"
      shift 4
      policy_file="$(mktemp)"
      trap "rm -f \"${policy_file}\"" EXIT
      cat > "${policy_file}"
      bao policy write "$1" "${policy_file}" >/dev/null
    ' sh "${vault_addr}" "${vault_cacert}" "${bao_addr}" "${bao_cacert}" "${target_policy_name}"
}

apply_tokenreview_binding() {
  local service_account="$1"

  echo "Ensuring TokenReview permission for the OpenBao ServiceAccount."
  kubectl create clusterrolebinding openbao-global-tokenreview-auth-delegator \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${namespace}:${service_account}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

configure_kubernetes_auth() {
  echo "Configuring Kubernetes auth using the in-cluster Kubernetes service host."
  token_exec "${root_token}" sh -c '
    set -eu
    kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
    bao write auth/kubernetes/config "kubernetes_host=${kubernetes_host}" >/dev/null
  '
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --init-file)
      [[ "$#" -ge 2 ]] || fail "Missing value for --init-file."
      init_file="$2"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

require_command kubectl
require_command jq

[[ -s "${policy_file}" ]] || fail "Missing or empty policy file: ${policy_file}"
[[ -f "${init_file}" ]] || fail "Missing init file: ${init_file}"

mode="$(file_mode "${init_file}")"
case "${mode}" in
  600|400) ;;
  *) fail "Init file permissions are too open (${mode}); expected 0600 or 0400: ${init_file}" ;;
esac

root_token="$(jq -r '.root_token // empty' "${init_file}")"
[[ -n "${root_token}" ]] || fail "Could not read root token from init file."

openbao_pod="$(discover_openbao_pod)"
[[ -n "${openbao_pod}" ]] || fail "Could not discover a Running openbao-global pod in namespace ${namespace}."

openbao_service_account="$(discover_openbao_service_account "${openbao_pod}")"
[[ -n "${openbao_service_account}" ]] || fail "Could not discover ServiceAccount for pod ${openbao_pod}."

echo "Discovered Global OpenBao pod: ${openbao_pod}"
echo "Discovered Global OpenBao ServiceAccount: ${openbao_service_account}"

apply_tokenreview_binding "${openbao_service_account}"

echo "Writing OpenBao policy ${policy_name}."
token_exec_with_policy_file "${root_token}" "${policy_file}" "${policy_name}"

echo "Checking Kubernetes auth method at ${auth_path}/."
auth_list_output="$(token_exec "${root_token}" bao auth list -format=json)"
if printf '%s\n' "${auth_list_output}" | jq -e --arg path "${auth_path}/" 'has($path)' >/dev/null; then
  echo "Kubernetes auth method already exists."
else
  echo "Enabling Kubernetes auth method."
  token_exec "${root_token}" bao auth enable -path="${auth_path}" kubernetes >/dev/null
fi

configure_kubernetes_auth

echo "Writing Kubernetes auth role ${role_name}."
token_exec "${root_token}" bao write "auth/${auth_path}/role/${role_name}" \
  "bound_service_account_names=${bound_service_account_name}" \
  "bound_service_account_namespaces=${bound_service_account_namespace}" \
  "policies=${policy_name}" \
  "ttl=${role_ttl}" >/dev/null

echo "Verifying Kubernetes auth method exists."
token_exec "${root_token}" bao auth list -format=json \
  | jq -e --arg path "${auth_path}/" 'has($path)' >/dev/null

echo "Verifying policy exists."
token_exec "${root_token}" bao policy read "${policy_name}" >/dev/null

echo "Verifying role binding metadata without printing tokens."
role_json="$(token_exec "${root_token}" bao read -format=json "auth/${auth_path}/role/${role_name}")"
role_sa_names="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_names[]?')"
role_sa_namespaces="$(printf '%s\n' "${role_json}" | jq -r '.data.bound_service_account_namespaces[]?')"
role_policies="$(printf '%s\n' "${role_json}" | jq -r '.data.policies[]?')"
role_ttl_live="$(printf '%s\n' "${role_json}" | jq -r '.data.ttl')"

printf '%s\n' "${role_sa_names}" | grep -Fxq "${bound_service_account_name}" || fail "Role is not bound to ServiceAccount ${bound_service_account_name}."
printf '%s\n' "${role_sa_namespaces}" | grep -Fxq "${bound_service_account_namespace}" || fail "Role is not bound to namespace ${bound_service_account_namespace}."
printf '%s\n' "${role_policies}" | grep -Fxq "${policy_name}" || fail "Role does not attach policy ${policy_name}."
[[ "${role_ttl_live}" = "${role_ttl}" || "${role_ttl_live}" = "900" ]] || fail "Role TTL is ${role_ttl_live}, expected ${role_ttl}."

echo "OpenBao Kubernetes auth for operator-plane secret sync is configured."
echo "No OpenBao or Kubernetes token values were printed."
