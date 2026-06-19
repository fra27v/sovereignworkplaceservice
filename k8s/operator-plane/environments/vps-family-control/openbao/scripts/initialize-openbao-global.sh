#!/usr/bin/env bash
set -euo pipefail

namespace="openbao-operator"
pod_name="openbao-global-0"
bootstrap_dir="${HOME}/openbao-bootstrap/openbao-global"
init_file="${bootstrap_dir}/openbao-global-init.json"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

mkdir -p "${bootstrap_dir}"
chmod 0700 "${bootstrap_dir}"

if [[ -e "${init_file}" ]]; then
  fail "Refusing to continue because init file already exists: ${init_file}"
fi

echo "Checking Global OpenBao initialization status."
status_output="$(
  set +e
  kubectl -n "${namespace}" exec "${pod_name}" -- bao status -tls-skip-verify 2>&1
  status_code="$?"
  set -e
  printf '\n__BAO_STATUS_EXIT_CODE__=%s\n' "${status_code}"
)"

bao_status_exit_code="$(printf '%s\n' "${status_output}" | awk -F= '/^__BAO_STATUS_EXIT_CODE__=/{print $2}')"
status_body="$(printf '%s\n' "${status_output}" | sed '/^__BAO_STATUS_EXIT_CODE__=/d')"

if [[ -z "${bao_status_exit_code}" ]]; then
  fail "Could not determine bao status exit code."
fi

if printf '%s\n' "${status_body}" | grep -q 'Initialized[[:space:]]*true'; then
  fail "Global OpenBao is already initialized. No init file was written."
fi

if ! printf '%s\n' "${status_body}" | grep -q 'Initialized[[:space:]]*false'; then
  echo "bao status output did not contain the expected uninitialized state." >&2
  echo "Safe status output follows; it must not contain init JSON:" >&2
  printf '%s\n' "${status_body}" >&2
  exit 1
fi

echo "Global OpenBao is not initialized. Initializing now."
kubectl -n "${namespace}" exec "${pod_name}" -- \
  bao operator init -format=json -tls-skip-verify > "${init_file}"
chmod 0600 "${init_file}"

if [[ ! -s "${init_file}" ]]; then
  fail "Init file was not written or is empty: ${init_file}"
fi

echo "Initialization output was written to: ${init_file}"
echo "WARNING: this file contains the root token and recovery material."
echo "Never commit it, paste it into chat, or print it in logs."

echo "Final Global OpenBao status:"
kubectl -n "${namespace}" exec "${pod_name}" -- bao status -tls-skip-verify
