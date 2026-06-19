#!/usr/bin/env bash
set -euo pipefail

OPENBAO_POD_GROUP_ID="1000"

base_dir="/var/lib/sovereignworkplaceservice/openbao"
seal_dir="${base_dir}/seal"
tls_dir="${base_dir}/tls"
audit_dir="${base_dir}/audit"
seal_key="${seal_dir}/unseal-20260618-1.key"
tls_key="${tls_dir}/tls.key"
tls_cert="${tls_dir}/tls.crt"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "Run this script as root, or install/configure sudo for the current user."
  fi
}

stat_size() {
  local path="$1"

  if stat -c '%s' "${path}" >/dev/null 2>&1; then
    stat -c '%s' "${path}"
  else
    stat -f '%z' "${path}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_command openssl

echo "Preparing local Global OpenBao file directories."
run_as_root install -d -o root -g "${OPENBAO_POD_GROUP_ID}" -m 0750 "${seal_dir}"
run_as_root install -d -o root -g "${OPENBAO_POD_GROUP_ID}" -m 0750 "${tls_dir}"
run_as_root install -d -o root -g root -m 0750 "${audit_dir}"

if [[ -e "${seal_key}" ]]; then
  echo "Static seal key already exists; leaving it unchanged."
else
  echo "Creating static seal key with 32 random bytes."
  run_as_root openssl rand -out "${seal_key}" 32
fi

run_as_root chown "root:${OPENBAO_POD_GROUP_ID}" "${seal_key}"
run_as_root chmod 0440 "${seal_key}"

if [[ -e "${tls_key}" && -e "${tls_cert}" ]]; then
  echo "TLS key and certificate already exist; leaving them unchanged."
elif [[ ! -e "${tls_key}" && ! -e "${tls_cert}" ]]; then
  echo "Creating local self-signed TLS key and certificate."
  tmp_config="$(mktemp)"
  cleanup() {
    rm -f "${tmp_config}"
  }
  trap cleanup EXIT

  cat > "${tmp_config}" <<'OPENSSL_CONFIG'
[req]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_req

[req_distinguished_name]
CN = openbao-global.openbao-operator.svc.cluster.local

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = openbao-global
DNS.2 = openbao-global.openbao-operator
DNS.3 = openbao-global.openbao-operator.svc
DNS.4 = openbao-global.openbao-operator.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
OPENSSL_CONFIG

  tmp_key="$(mktemp)"
  tmp_cert="$(mktemp)"
  run_as_root rm -f "${tmp_key}" "${tmp_cert}"
  openssl req -x509 -newkey rsa:4096 -sha256 -days 825 -nodes \
    -keyout "${tmp_key}" \
    -out "${tmp_cert}" \
    -config "${tmp_config}" >/dev/null 2>&1
  run_as_root install -o root -g "${OPENBAO_POD_GROUP_ID}" -m 0440 "${tmp_key}" "${tls_key}"
  run_as_root install -o root -g root -m 0444 "${tmp_cert}" "${tls_cert}"
  rm -f "${tmp_key}" "${tmp_cert}"
else
  fail "Only one TLS file exists. Remove the incomplete local TLS pair or restore the missing file, then rerun."
fi

run_as_root chown "root:${OPENBAO_POD_GROUP_ID}" "${tls_key}"
run_as_root chown root:root "${tls_cert}"
run_as_root chmod 0440 "${tls_key}"
run_as_root chmod 0444 "${tls_cert}"
run_as_root chown root:root "${audit_dir}"
run_as_root chmod 0750 "${audit_dir}"

echo "Verifying local file metadata without printing secret contents."
[[ -f "${seal_key}" ]] || fail "Missing static seal key: ${seal_key}"
seal_size="$(stat_size "${seal_key}")"
[[ "${seal_size}" = "32" ]] || fail "Static seal key must be exactly 32 bytes; found ${seal_size} bytes."
[[ -f "${tls_key}" ]] || fail "Missing TLS key: ${tls_key}"
[[ -f "${tls_cert}" ]] || fail "Missing TLS certificate: ${tls_cert}"

echo "Safe ownership and mode metadata:"
run_as_root stat -c '%U:%G %a %n' \
  "${seal_dir}" \
  "${seal_key}" \
  "${tls_dir}" \
  "${tls_key}" \
  "${tls_cert}" \
  "${audit_dir}"

echo "Safe static seal key size:"
run_as_root stat -c '%s %n' "${seal_key}"

echo "Safe TLS certificate metadata:"
openssl x509 -in "${tls_cert}" -noout -subject -issuer -dates

echo "Local Global OpenBao files are prepared."
