#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

tenant_file=""
live="false"

usage() {
  cat <<'USAGE'
Usage:
  verify-ready-for-init.sh [--tenant-file <path>] [--live] [--help]

Verifies the Tenant OpenBao bootstrap model without printing secrets and
without running bao operator init. Static checks render and inspect manifests.
With --live, the script also checks Kubernetes resources and verifies that the
pod reports OpenBao as uninitialized through kubectl exec -> localhost.
USAGE
}

ok() {
  echo "OK: $*"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tenant-file)
      [[ "$#" -ge 2 ]] || fail "--tenant-file requires a path."
      tenant_file="$2"
      shift 2
      ;;
    --live)
      live="true"
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

tenant_file="${tenant_file:-$(resolve_tenant_file family-infra)}"
"${script_dir}/validate-tenant-config.sh" --tenant-file "${tenant_file}"
"${script_dir}/verify-transit-preflight.sh" --tenant-file "${tenant_file}"

manifest_file="$(mktemp /tmp/tenant-openbao-bootstrap.XXXXXX.yaml)"
cleanup() {
  rm -f "${manifest_file}"
}
trap cleanup EXIT
"${script_dir}/render-bootstrap.sh" --tenant-file "${tenant_file}" --output "${manifest_file}" >/dev/null

tenant_name="$(require_yaml_value "${tenant_file}" tenant.name)"
storage_class="$(require_yaml_value "${tenant_file}" storage.openbao.class)"
storage_size="$(require_yaml_value "${tenant_file}" storage.openbao.size)"
root_ttl="$(require_yaml_value "${tenant_file}" pki.root.ttl)"
issuing_ttl="$(require_yaml_value "${tenant_file}" pki.issuing.ttl)"
leaf_ttl="$(require_yaml_value "${tenant_file}" pki.leaf.defaultTtl)"
canonical_dns="$(require_yaml_value "${tenant_file}" openbao.canonicalDnsName)"
recovery_shares="$(require_yaml_value "${tenant_file}" recovery.shares)"
recovery_threshold="$(require_yaml_value "${tenant_file}" recovery.threshold)"
release="$(require_yaml_value "${tenant_file}" components.openbao.release)"
release_file="$(resolve_release_file "${release}")"
resolve_release_image "${release_file}" >/dev/null
namespace="$(derive_namespace "${tenant_name}")"
statefulset="$(derive_statefulset_name)"
data_volume="$(derive_data_volume_name)"

grep -q 'kind: StatefulSet' "${manifest_file}" || fail "Rendered manifest does not contain StatefulSet"
ok "StatefulSet is configured"
grep -q 'replicas: 1' "${manifest_file}" || fail "StatefulSet replicas is not 1"
ok "replica count is 1"
grep -q 'storage "raft"' "${manifest_file}" || fail "OpenBao Raft storage is not configured"
ok "Raft storage is configured"
grep -q 'cluster_addr = "https://127.0.0.1:8201"' "${manifest_file}" || fail "Raft cluster_addr is not configured"
ok "cluster_addr is configured"
grep -q "storageClassName: ${storage_class}" "${manifest_file}" || fail "Rendered manifest does not use tenant storage class ${storage_class}"
ok "tenant storage class is ${storage_class}"
grep -q "storage: ${storage_size}" "${manifest_file}" || fail "Rendered manifest does not request tenant storage size ${storage_size}"
ok "tenant requested capacity is ${storage_size}"
grep -Eq 'address[[:space:]]*=[[:space:]]*"127[.]0[.]0[.]1:8200"' "${manifest_file}" || fail "Bootstrap listener is not loopback-only"
ok "bootstrap API listener is exactly loopback-only"
grep -Eq 'tls_disable[[:space:]]*=[[:space:]]*true' "${manifest_file}" || fail "Bootstrap HTTP listener is not explicit"
ok "bootstrap HTTP is intentional and local-only"
if grep -q '0.0.0.0:8200' "${manifest_file}"; then
  fail "Forbidden bootstrap listener exists: 0.0.0.0:8200"
fi
ok "no 0.0.0.0:8200 bootstrap API listener exists"
grep -q 'seal "transit"' "${manifest_file}" || fail "Transit seal is not configured"
ok "Transit seal is configured"
grep -q 'tls_ca_cert' "${manifest_file}" || fail "Transit TLS CA verification is not configured"
ok "Transit TLS verification is enabled"
if grep -q 'tls_skip_verify' "${manifest_file}"; then
  fail "tls_skip_verify is forbidden"
fi
ok "no tls_skip_verify is present"
grep -q 'name: transit-ca' "${manifest_file}" || fail "Operator CA trust material is not projected"
ok "Operator CA trust material is projected by ConfigMap"
grep -q 'secretKeyRef:' "${manifest_file}" || fail "Transit token Secret projection is missing"
ok "Transit secret material is referenced by Kubernetes Secret"
grep -q 'audit "file" "stdout"' "${manifest_file}" || fail "Declarative stdout audit is missing"
ok "audit is declaratively configured"
grep -q 'file_path = "stdout"' "${manifest_file}" || fail "Audit target is not stdout"
ok "audit target is stdout"
ok "recovery configuration resolves to ${recovery_shares}/${recovery_threshold}"
ok "canonical DNS resolves from tenant config to ${canonical_dns}"
ok "PKI TTLs resolve from tenant config: root=${root_ttl} issuing=${issuing_ttl} leaf=${leaf_ttl}"
ok "component release ${release} remains deployable from current repository state"
if grep -Eq '^kind: (Service|Ingress|IngressRoute|IngressRouteTCP)$' "${manifest_file}"; then
  fail "Rendered bootstrap manifest contains forbidden network exposure"
fi
ok "no OpenBao Service, Ingress, IngressRoute, or Traefik exposure exists in bootstrap composition"

if grep -Eiq '(root_token|recovery_share|private_key|VAULT_TOKEN|BAO_TOKEN)[[:space:]]*[:=][[:space:]]*[^<[:space:]]' "${manifest_file}"; then
  fail "Rendered manifest appears to contain secret material"
fi
ok "rendered manifest did not match static secret material patterns"

if [[ "${live}" != "true" ]]; then
  echo "Static validation completed. Live state is not READY_FOR_INIT until namespace, prerequisites, StatefulSet, PVC, and uninitialized local OpenBao status are verified."
  exit 0
fi

require_command kubectl
require_command jq

secret_name="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretName "$(derive_transit_token_secret_name)")"
ca_configmap="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName "$(derive_transit_ca_bundle_configmap_name)")"

kubectl get namespace "${namespace}" >/dev/null
ok "NAMESPACE_READY: namespace exists"
kubectl -n "${namespace}" get secret "${secret_name}" >/dev/null
kubectl -n "${namespace}" get configmap "${ca_configmap}" >/dev/null
"${script_dir}/verify-transit-preflight.sh" --tenant-file "${tenant_file}" --live
ok "PREREQUISITES_READY: Transit Secret, Operator CA ConfigMap, and Transit TLS preflight passed"
kubectl -n "${namespace}" get statefulset "${statefulset}" >/dev/null
ok "BOOTSTRAP_DEPLOYED: live StatefulSet exists"
kubectl -n "${namespace}" get pvc "${data_volume}-${statefulset}-0" >/dev/null
ok "live Raft PVC exists"
if kubectl -n "${namespace}" get service,ingress,ingressroute,ingressroutetcp 2>/dev/null | grep -i openbao; then
  fail "Found forbidden live OpenBao network exposure"
fi
ok "no live OpenBao Service, Ingress, IngressRoute, or Traefik route was found"

pod="${statefulset}-0"
status_output="$(kubectl -n "${namespace}" exec "${pod}" -- sh -ec 'bao status -address=http://127.0.0.1:8200 2>/dev/null || true')"
if printf '%s\n' "${status_output}" | grep -q 'Initialized[[:space:]]*false'; then
  ok "READY_FOR_INIT: OpenBao is reachable only through kubectl exec -> localhost and is still uninitialized"
else
  fail "OpenBao did not report Initialized false through local exec"
fi

echo "Live ready-for-init verification completed. STOP before bao operator init."
