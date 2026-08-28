#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
component_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_root="$(cd -- "${component_dir}/../../.." && pwd)"
tenant_file="${repo_root}/k8s/tenants/family-infra/tenant.yaml"
rendered_manifest="$(mktemp /tmp/openbao-component-test.XXXXXX.yaml)"
fixture_root="$(mktemp -d /tmp/openbao-component-fixture.XXXXXX)"

cleanup() {
  rm -f "${rendered_manifest}"
  rm -rf "${fixture_root}"
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
bash -n "${component_dir}/scripts/verify-transit-preflight.sh"
bash -n "${component_dir}/scripts/verify-ready-for-init.sh"

echo "Checking reconcile requires an explicit mode."
if "${component_dir}/scripts/reconcile-bootstrap.sh" >/dev/null 2>&1; then
  fail "reconcile-bootstrap.sh without mode must fail"
fi

echo "Validating tenant configuration."
"${component_dir}/scripts/validate-tenant-config.sh" --tenant-file "${tenant_file}" >/dev/null

echo "Rendering bootstrap manifest."
"${component_dir}/scripts/render-bootstrap.sh" \
  --tenant-file "${tenant_file}" \
  --output "${rendered_manifest}" >/dev/null

grep -q 'kind: StatefulSet' "${rendered_manifest}" || fail "StatefulSet is missing"
grep -q 'replicas: 1' "${rendered_manifest}" || fail "replicas: 1 is missing"
grep -Eq 'address[[:space:]]*=[[:space:]]*"127[.]0[.]0[.]1:8200"' "${rendered_manifest}" || fail "loopback listener is missing"
grep -q 'storage "raft"' "${rendered_manifest}" || fail "Raft storage is missing"
grep -q 'cluster_addr = "https://127.0.0.1:8201"' "${rendered_manifest}" || fail "Raft cluster_addr is missing"
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

echo "Checking shared scripts resolve non-family fixture values."
mkdir -p "${fixture_root}/releases/7" "${fixture_root}/config" "${fixture_root}/manifests"
cp "${component_dir}/config/openbao-bootstrap.hcl.tpl" "${fixture_root}/config/openbao-bootstrap.hcl.tpl"
cp "${component_dir}/manifests/bootstrap.yaml.tpl" "${fixture_root}/manifests/bootstrap.yaml.tpl"
cp "${component_dir}/manifests/foundation.yaml.tpl" "${fixture_root}/manifests/foundation.yaml.tpl"
cat > "${fixture_root}/releases/7/release.yaml" <<'YAML'
component:
  name: openbao
  release: 7

runtime:
  image:
    repository: quay.io/openbao/openbao
    version: "9.8.7"
    digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

configuration:
  schemaVersion: 1
YAML

fixture_tenant="${fixture_root}/tenant.yaml"
cat > "${fixture_tenant}" <<'YAML'
schemaVersion: 1

tenant:
  name: example-tenant
  node: example-node-03

components:
  openbao:
    release: 7

storage:
  openbao:
    class: example-storage
    size: 9Gi

pki:
  root:
    ttl: 100h
  issuing:
    ttl: 50h
  leaf:
    defaultTtl: 10h

openbao:
  canonicalDnsName: vault.example.internal
  transit:
    address: https://operator-vault.example.org

recovery:
  shares: 5
  threshold: 3
YAML

OPENBAO_COMPONENT_DIR_OVERRIDE="${fixture_root}" \
  "${component_dir}/scripts/validate-tenant-config.sh" --tenant-file "${fixture_tenant}" >/dev/null
OPENBAO_COMPONENT_DIR_OVERRIDE="${fixture_root}" \
  "${component_dir}/scripts/render-bootstrap.sh" --tenant-file "${fixture_tenant}" --output "${rendered_manifest}" >/dev/null
grep -q 'storageClassName: example-storage' "${rendered_manifest}" || fail "fixture storage class was not rendered"
grep -q 'storage: 9Gi' "${rendered_manifest}" || fail "fixture storage size was not rendered"
grep -q 'quay.io/openbao/openbao:9.8.7@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "${rendered_manifest}" || fail "fixture image was not rendered"
grep -q 'key_name        = "example-node-03-autounseal"' "${rendered_manifest}" || fail "fixture transit key was not derived"
grep -q 'tls_server_name = "operator-vault.example.org"' "${rendered_manifest}" || fail "fixture TLS server name was not derived"

echo "Checking invalid operator-cluster Transit endpoint is rejected."
bad_tenant="${fixture_root}/bad-tenant.yaml"
cp "${fixture_tenant}" "${bad_tenant}"
sed -i 's#https://operator-vault.example.org#https://openbao-global.openbao-operator.svc.cluster.local:8200#' "${bad_tenant}"
if OPENBAO_COMPONENT_DIR_OVERRIDE="${fixture_root}" \
  "${component_dir}/scripts/validate-tenant-config.sh" --tenant-file "${bad_tenant}" >/dev/null 2>&1; then
  fail "operator-cluster .svc.cluster.local Transit endpoint must be rejected"
fi

echo "Tenant OpenBao static component test passed."
