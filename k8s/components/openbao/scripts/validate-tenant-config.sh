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
transit_address="$(require_yaml_value "${tenant_file}" openbao.transit.address)"
transit_key="$(optional_yaml_value "${tenant_file}" openbao.transit.keyName "$(derive_transit_key_name "${tenant_node}")")"
transit_mount="$(optional_yaml_value "${tenant_file}" openbao.transit.mountPath "$(derive_transit_mount_path)")"
transit_ca_cm="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName "$(derive_transit_ca_bundle_configmap_name)")"
transit_token_secret="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretName "$(derive_transit_token_secret_name)")"
transit_host="$(validate_transit_address "${transit_address}")"

[[ "${schema_version}" = "1" ]] || fail "Expected tenant schemaVersion 1, got ${schema_version}"
ok "tenant schemaVersion is 1"
[[ "${tenant_name}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || fail "Invalid tenant name: ${tenant_name}"
ok "tenant name is valid: ${tenant_name}"
[[ "${tenant_node}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || fail "Invalid tenant node: ${tenant_node}"
ok "tenant node is valid: ${tenant_node}"
[[ "${release}" =~ ^[0-9]+$ ]] || fail "OpenBao release must be a positive integer, got ${release}"
ok "selected OpenBao release is ${release}"

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
[[ "${release_number}" = "${release}" ]] || fail "Release number ${release_number} does not match tenant selection ${release}"
ok "release number matches tenant selection"
[[ "${release_schema}" = "${schema_version}" ]] || fail "Release config schemaVersion ${release_schema} does not match tenant schemaVersion ${schema_version}"
ok "release config schemaVersion matches tenant schemaVersion"
[[ "${release_version}" =~ ^v?[0-9]+([.][0-9]+){1,2}([-+][A-Za-z0-9.-]+)?$ ]] || fail "Invalid OpenBao upstream version: ${release_version}"
ok "OpenBao upstream version is ${release_version}"
[[ "${release_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "OpenBao image digest is not immutable sha256: ${release_digest}"
ok "OpenBao image digest is immutable"

[[ -n "${storage_class}" ]] || fail "Storage class must not be empty"
ok "tenant storage class is ${storage_class}"
[[ "${storage_size}" =~ ^[0-9]+(Mi|Gi|Ti)$ ]] || fail "Invalid storage size: ${storage_size}"
ok "tenant storage request is ${storage_size}"
[[ "${root_ttl}" =~ ^[0-9]+h$ ]] || fail "Invalid Root CA TTL: ${root_ttl}"
ok "Root CA TTL is ${root_ttl}"
[[ "${issuing_ttl}" =~ ^[0-9]+h$ ]] || fail "Invalid Issuing CA TTL: ${issuing_ttl}"
ok "Issuing CA TTL is ${issuing_ttl}"
[[ "${leaf_ttl}" =~ ^[0-9]+h$ ]] || fail "Invalid default leaf TTL: ${leaf_ttl}"
ok "default leaf TTL is ${leaf_ttl}"
[[ -n "${canonical_dns}" ]] || fail "Canonical DNS must not be empty"
ok "canonical DNS is ${canonical_dns}"
[[ "${recovery_shares}" =~ ^[0-9]+$ ]] || fail "Recovery shares must be an integer"
[[ "${recovery_threshold}" =~ ^[0-9]+$ ]] || fail "Recovery threshold must be an integer"
(( recovery_shares >= recovery_threshold )) || fail "Recovery shares must be >= threshold"
ok "recovery configuration is ${recovery_shares}/${recovery_threshold}"
ok "Transit address is externally reachable configuration: ${transit_address}"
ok "Transit TLS server name resolves to ${transit_host}"
[[ "${transit_key}" = "$(derive_transit_key_name "${tenant_node}")" ]] || fail "Transit key must follow tenant node convention ${tenant_node}-autounseal"
ok "Transit key contract is ${transit_key}"
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
