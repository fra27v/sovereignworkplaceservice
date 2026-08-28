#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
component_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_root="$(cd -- "${component_dir}/../../.." && pwd)"
tenant_file="${repo_root}/k8s/tenants/family-infra/tenant.yaml"
rendered_manifest="$(mktemp /tmp/openbao-component-test.XXXXXX.yaml)"

cleanup() {
  rm -f "${rendered_manifest}"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "Checking bash syntax."
bash -n "${component_dir}/scripts/lib.sh"
bash -n "${component_dir}/scripts/validate-tenant-config.sh"
bash -n "${component_dir}/scripts/render-bootstrap.sh"
bash -n "${component_dir}/scripts/reconcile-bootstrap.sh"
bash -n "${component_dir}/scripts/verify-ready-for-init.sh"

echo "Validating tenant configuration."
"${component_dir}/scripts/validate-tenant-config.sh" --tenant-file "${tenant_file}" >/dev/null

echo "Rendering bootstrap manifest."
"${component_dir}/scripts/render-bootstrap.sh" \
  --tenant-file "${tenant_file}" \
  --output "${rendered_manifest}" >/dev/null

grep -q 'kind: StatefulSet' "${rendered_manifest}" || fail "StatefulSet is missing"
grep -q 'replicas: 1' "${rendered_manifest}" || fail "replicas: 1 is missing"
grep -q 'address     = "127.0.0.1:8200"' "${rendered_manifest}" || fail "loopback listener is missing"
grep -q 'storage "raft"' "${rendered_manifest}" || fail "Raft storage is missing"
grep -q 'seal "transit"' "${rendered_manifest}" || fail "Transit seal is missing"
grep -q 'file_path = "stdout"' "${rendered_manifest}" || fail "stdout audit is missing"
grep -q 'storageClassName: local-path' "${rendered_manifest}" || fail "local-path storage class is missing"
grep -q 'storage: 1Gi' "${rendered_manifest}" || fail "1Gi storage request is missing"

if grep -q '0.0.0.0:8200' "${rendered_manifest}"; then
  fail "forbidden 0.0.0.0 bootstrap listener found"
fi

if grep -q 'tls_skip_verify' "${rendered_manifest}"; then
  fail "forbidden tls_skip_verify found"
fi

if grep -Eq '^kind: (Service|Ingress|IngressRoute|IngressRouteTCP)$' "${rendered_manifest}"; then
  fail "forbidden network exposure found"
fi

if grep -Eiq '(root_token|recovery_share|private_key|VAULT_TOKEN|BAO_TOKEN)[[:space:]]*[:=][[:space:]]*[^<[:space:]]' "${rendered_manifest}"; then
  fail "rendered manifest appears to contain secret material"
fi

echo "Tenant OpenBao static component test passed."
