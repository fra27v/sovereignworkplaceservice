#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

tenant_file=""

usage() {
  cat <<'USAGE'
Usage:
  validate-tenant-config.sh [--tenant-file <path>] [--help]

Validates the Tenant OpenBao release selection and non-secret tenant
configuration. This script is static and does not read Kubernetes Secrets.
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
[[ -f "${tenant_file}" ]] || fail "Missing tenant file: ${tenant_file}"

schema_version="$(require_yaml_value "${tenant_file}" schemaVersion)"
tenant_name="$(require_yaml_value "${tenant_file}" tenant.name)"
tenant_node="$(require_yaml_value "${tenant_file}" tenant.node)"
release="$(require_yaml_value "${tenant_file}" components.openbao.release)"
storage_class="$(require_yaml_value "${tenant_file}" storage.openbao.class)"
storage_size="$(require_yaml_value "${tenant_file}" storage.openbao.size)"
root_ttl="$(require_yaml_value "${tenant_file}" pki.root.ttl)"
issuing_ttl="$(require_yaml_value "${tenant_file}" pki.issuing.ttl)"
leaf_ttl="$(require_yaml_value "${tenant_file}" pki.leaf.defaultTtl)"
canonical_dns="$(require_yaml_value "${tenant_file}" openbao.canonicalDnsName)"
recovery_shares="$(require_yaml_value "${tenant_file}" recovery.shares)"
recovery_threshold="$(require_yaml_value "${tenant_file}" recovery.threshold)"
transit_key="$(require_yaml_value "${tenant_file}" openbao.transit.keyName)"
transit_mount="$(require_yaml_value "${tenant_file}" openbao.transit.mountPath)"
transit_ca_cm="$(require_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName)"
transit_token_secret="$(require_yaml_value "${tenant_file}" openbao.transit.tokenSecretName)"

[[ "${schema_version}" = "1" ]] || fail "Expected tenant schemaVersion 1, got ${schema_version}"
ok "tenant schemaVersion is 1"
[[ "${tenant_name}" = "family-infra" ]] || fail "Expected tenant name family-infra, got ${tenant_name}"
ok "tenant name is family-infra"
[[ "${tenant_node}" = "family-infra-01" ]] || fail "Expected tenant node family-infra-01, got ${tenant_node}"
ok "tenant node is family-infra-01"
[[ "${release}" = "1" ]] || fail "Expected OpenBao release 1, got ${release}"
ok "selected OpenBao release is 1"

release_file="$(resolve_release_file "${release}")"
[[ -f "${release_file}" ]] || fail "Missing OpenBao release metadata: ${release_file}"
ok "component release exists: ${release_file}"

release_component="$(require_yaml_value "${release_file}" component.name)"
release_number="$(require_yaml_value "${release_file}" component.release)"
release_schema="$(require_yaml_value "${release_file}" configuration.schemaVersion)"
release_version="$(require_yaml_value "${release_file}" runtime.image.version)"
release_digest="$(require_yaml_value "${release_file}" runtime.image.digest)"
release_image="$(resolve_release_image "${release_file}")"

[[ "${release_component}" = "openbao" ]] || fail "Release component name must be openbao"
ok "release component name is openbao"
[[ "${release_number}" = "1" ]] || fail "Release number must be 1"
ok "release number is 1"
[[ "${release_schema}" = "1" ]] || fail "Release config schemaVersion must be 1"
ok "release config schemaVersion is 1"
[[ "${release_version}" = "2.5.5" ]] || fail "Expected OpenBao upstream version 2.5.5, got ${release_version}"
ok "OpenBao upstream version is 2.5.5"
[[ "${release_digest}" = "sha256:6150c4a6b62067db6141c8da7a6a6b5763f4f47c315343d0c848b40fecdfd452" ]] || fail "Unexpected OpenBao digest"
ok "OpenBao image digest is immutable and expected"

[[ "${storage_class}" = "local-path" ]] || fail "Expected storage class local-path, got ${storage_class}"
ok "tenant storage class is local-path"
[[ "${storage_size}" = "1Gi" ]] || fail "Expected storage size 1Gi, got ${storage_size}"
ok "tenant storage request is 1Gi"
[[ "${root_ttl}" = "87600h" ]] || fail "Expected root TTL 87600h, got ${root_ttl}"
ok "Root CA TTL is 87600h"
[[ "${issuing_ttl}" = "26280h" ]] || fail "Expected issuing TTL 26280h, got ${issuing_ttl}"
ok "Issuing CA TTL is 26280h"
[[ "${leaf_ttl}" = "2160h" ]] || fail "Expected default leaf TTL 2160h, got ${leaf_ttl}"
ok "default leaf TTL is 2160h"
[[ "${canonical_dns}" = "vault.internal" ]] || fail "Expected canonical DNS vault.internal, got ${canonical_dns}"
ok "canonical DNS is vault.internal"
[[ "${recovery_shares}" = "3" ]] || fail "Expected recovery shares 3, got ${recovery_shares}"
ok "recovery shares is 3"
[[ "${recovery_threshold}" = "2" ]] || fail "Expected recovery threshold 2, got ${recovery_threshold}"
ok "recovery threshold is 2"
[[ "${transit_key}" = "family-infra-01-autounseal" ]] || fail "Unexpected transit key: ${transit_key}"
ok "Transit key contract is family-infra-01-autounseal"
[[ "${transit_mount}" = "transit/" ]] || fail "Unexpected transit mount: ${transit_mount}"
ok "Transit mount is transit/"
[[ -n "${transit_ca_cm}" ]] || fail "Missing Operator CA bundle ConfigMap name"
ok "Operator CA trust projection is configured"
[[ -n "${transit_token_secret}" ]] || fail "Missing Transit token Secret name"
ok "Transit secret projection is configured by Secret reference only"

if grep -Eiq '(root_token|recovery_share|recovery_key|private_key|transit_token|VAULT_TOKEN|BAO_TOKEN)[[:space:]]*[:=][[:space:]]*[^<[:space:]]' "${tenant_file}"; then
  fail "Tenant file appears to contain secret material"
fi
ok "tenant file did not match static secret material patterns"

echo "Resolved OpenBao image: ${release_image}"
echo "Tenant OpenBao configuration validation completed."
