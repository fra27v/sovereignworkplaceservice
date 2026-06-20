#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${BAO_ADDR:=https://openbao-global.openbao-operator.svc:8200}"
: "${BAO_AUTH_PATH:=kubernetes}"
: "${BAO_ROLE:=operator-plane-secret-sync}"
: "${BAO_KV_MOUNT:=operator-kv}"
: "${BAO_CACERT:=/var/run/openbao-ca/ca.crt}"

service_account_token_file="/var/run/secrets/kubernetes.io/serviceaccount/token"
traefik_path="operator-plane/traefik/ovh-dns01"
artifacts_path="operator-plane/operator-artifacts/family-infra-01"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command in image: $1"
}

require_command curl
require_command jq
require_command kubectl
require_command openssl

[[ -f "${service_account_token_file}" ]] || fail "Missing mounted ServiceAccount token."
[[ -f "${BAO_CACERT}" ]] || fail "Missing OpenBao CA bundle: ${BAO_CACERT}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

login_payload="${tmp_dir}/openbao-login.json"
SA_JWT="$(cat "${service_account_token_file}")"
export SA_JWT
jq -n --arg role "${BAO_ROLE}" '{role: $role, jwt: env.SA_JWT}' > "${login_payload}"
chmod 0600 "${login_payload}"
unset SA_JWT

login_response="${tmp_dir}/openbao-login-response.json"
curl -fsS \
  --cacert "${BAO_CACERT}" \
  --request POST \
  --data @"${login_payload}" \
  "${BAO_ADDR}/v1/auth/${BAO_AUTH_PATH}/login" \
  > "${login_response}"

bao_token="$(jq -r '.auth.client_token // empty' "${login_response}")"
[[ -n "${bao_token}" ]] || fail "OpenBao Kubernetes auth login did not return a client token."
curl_token_config="${tmp_dir}/curl-openbao-token.conf"
{
  printf 'header = "X-Vault-Token: %s"\n' "${bao_token}"
} > "${curl_token_config}"
chmod 0600 "${curl_token_config}"
unset bao_token

read_kv() {
  local logical_path="$1"
  local output_file="$2"

  curl -fsS \
    --config "${curl_token_config}" \
    --cacert "${BAO_CACERT}" \
    "${BAO_ADDR}/v1/${BAO_KV_MOUNT}/data/${logical_path}" \
    | jq '.data.data' > "${output_file}"
  chmod 0600 "${output_file}"
}

traefik_json="${tmp_dir}/traefik.json"
artifacts_json="${tmp_dir}/operator-artifacts.json"
read_kv "${traefik_path}" "${traefik_json}"
read_kv "${artifacts_path}" "${artifacts_json}"

traefik_env="${tmp_dir}/traefik.env"
jq -r '
  [
    "OVH_ENDPOINT=" + .OVH_ENDPOINT,
    "OVH_APPLICATION_KEY=" + .OVH_APPLICATION_KEY,
    "OVH_APPLICATION_SECRET=" + .OVH_APPLICATION_SECRET,
    "OVH_CONSUMER_KEY=" + .OVH_CONSUMER_KEY
  ][]
' "${traefik_json}" > "${traefik_env}"
chmod 0600 "${traefik_env}"

username="$(jq -r '.username // empty' "${artifacts_json}")"
token="$(jq -r '.token // empty' "${artifacts_json}")"
[[ -n "${username}" ]] || fail "operator-artifacts username is missing from OpenBao KV."
[[ -n "${token}" ]] || fail "operator-artifacts token is missing from OpenBao KV."

users_file="${tmp_dir}/users"
# Apache MD5 is chosen because openssl is small and commonly available in
# purpose-built sync images. Do not echo the generated htpasswd line.
password_hash="$(printf '%s' "${token}" | openssl passwd -apr1 -stdin)"
printf '%s:%s\n' "${username}" "${password_hash}" > "${users_file}"
chmod 0600 "${users_file}"
unset token password_hash

echo "Applying runtime Secret projection: kube-system/traefik-ovh-dns-credentials"
kubectl -n kube-system create secret generic traefik-ovh-dns-credentials \
  --from-env-file="${traefik_env}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Applying runtime Secret projection: operator-artifacts/operator-artifacts-basicauth"
kubectl -n operator-artifacts create secret generic operator-artifacts-basicauth \
  --from-file=users="${users_file}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Operator-plane runtime Secret projections were synchronized."
echo "Secret values and htpasswd contents were not printed."
