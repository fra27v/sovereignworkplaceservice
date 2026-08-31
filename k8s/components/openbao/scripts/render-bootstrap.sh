#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

tenant_file=""
output_file=""
keep_output="false"
phase="all"

usage() {
  cat <<'USAGE'
Usage:
  render-bootstrap.sh [--tenant-file <path>] [--phase foundation|statefulset|all] [--output <path>] [--keep-output] [--help]

Renders Tenant OpenBao bootstrap manifests. Render mode does not apply
resources and does not mutate the cluster. Rendered manifests intentionally
contain no OpenBao Service, Ingress, IngressRoute, Traefik route, or Secret data
values. By default output is printed to stdout.

Phases:
  foundation
      Render only the bootstrap foundation Namespace.

  statefulset
      Render only the Tenant OpenBao bootstrap workload:
        - ServiceAccount
        - OpenBao bootstrap ConfigMap
        - StatefulSet
        - PVC template through volumeClaimTemplate

  all
      Render foundation + StatefulSet together for review and inspection. This
      is only a rendering convenience. It does not change the staged
      reconciliation workflow and is not accepted by reconcile-bootstrap.sh.
USAGE
}

replace_vars() {
  awk \
    -v TENANT_NAME="${TENANT_NAME}" \
    -v NAMESPACE="${NAMESPACE}" \
    -v SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}" \
    -v CONFIGMAP_NAME="${CONFIGMAP_NAME}" \
    -v STATEFULSET_NAME="${STATEFULSET_NAME}" \
    -v OPENBAO_IMAGE="${OPENBAO_IMAGE}" \
    -v DATA_VOLUME_NAME="${DATA_VOLUME_NAME}" \
    -v STORAGE_CLASS="${STORAGE_CLASS}" \
    -v STORAGE_SIZE="${STORAGE_SIZE}" \
    -v TRANSIT_CA_BUNDLE_PATH="${TRANSIT_CA_BUNDLE_PATH}" \
    -v TRANSIT_CA_BUNDLE_KEY="${TRANSIT_CA_BUNDLE_KEY}" \
    -v TRANSIT_CA_BUNDLE_CONFIGMAP_NAME="${TRANSIT_CA_BUNDLE_CONFIGMAP_NAME}" \
    -v TRANSIT_TOKEN_SECRET_NAME="${TRANSIT_TOKEN_SECRET_NAME}" \
    -v TRANSIT_TOKEN_SECRET_KEY="${TRANSIT_TOKEN_SECRET_KEY}" \
    -v OPENBAO_CONFIG="${OPENBAO_CONFIG}" '
      {
        gsub(/\$\{TENANT_NAME\}/, TENANT_NAME)
        gsub(/\$\{NAMESPACE\}/, NAMESPACE)
        gsub(/\$\{SERVICE_ACCOUNT_NAME\}/, SERVICE_ACCOUNT_NAME)
        gsub(/\$\{CONFIGMAP_NAME\}/, CONFIGMAP_NAME)
        gsub(/\$\{STATEFULSET_NAME\}/, STATEFULSET_NAME)
        gsub(/\$\{OPENBAO_IMAGE\}/, OPENBAO_IMAGE)
        gsub(/\$\{DATA_VOLUME_NAME\}/, DATA_VOLUME_NAME)
        gsub(/\$\{STORAGE_CLASS\}/, STORAGE_CLASS)
        gsub(/\$\{STORAGE_SIZE\}/, STORAGE_SIZE)
        gsub(/\$\{TRANSIT_CA_BUNDLE_PATH\}/, TRANSIT_CA_BUNDLE_PATH)
        gsub(/\$\{TRANSIT_CA_BUNDLE_KEY\}/, TRANSIT_CA_BUNDLE_KEY)
        gsub(/\$\{TRANSIT_CA_BUNDLE_CONFIGMAP_NAME\}/, TRANSIT_CA_BUNDLE_CONFIGMAP_NAME)
        gsub(/\$\{TRANSIT_TOKEN_SECRET_NAME\}/, TRANSIT_TOKEN_SECRET_NAME)
        gsub(/\$\{TRANSIT_TOKEN_SECRET_KEY\}/, TRANSIT_TOKEN_SECRET_KEY)
        if ($0 == "${OPENBAO_CONFIG}") {
          print OPENBAO_CONFIG
          next
        }
        print
      }
    ' "$1"
}

render_openbao_config() {
  awk \
    -v TENANT_NODE="${TENANT_NODE}" \
    -v TRANSIT_ADDRESS="${TRANSIT_ADDRESS}" \
    -v TRANSIT_KEY_NAME="${TRANSIT_KEY_NAME}" \
    -v TRANSIT_MOUNT_PATH="${TRANSIT_MOUNT_PATH}" \
    -v TRANSIT_CA_BUNDLE_PATH="${TRANSIT_CA_BUNDLE_PATH}" \
    -v TRANSIT_TLS_SERVER_NAME="${TRANSIT_TLS_SERVER_NAME}" '
      {
        gsub(/\$\{TENANT_NODE\}/, TENANT_NODE)
        gsub(/\$\{TRANSIT_ADDRESS\}/, TRANSIT_ADDRESS)
        gsub(/\$\{TRANSIT_KEY_NAME\}/, TRANSIT_KEY_NAME)
        gsub(/\$\{TRANSIT_MOUNT_PATH\}/, TRANSIT_MOUNT_PATH)
        gsub(/\$\{TRANSIT_CA_BUNDLE_PATH\}/, TRANSIT_CA_BUNDLE_PATH)
        gsub(/\$\{TRANSIT_TLS_SERVER_NAME\}/, TRANSIT_TLS_SERVER_NAME)
        print
      }
    ' "${openbao_component_dir}/config/openbao-bootstrap.hcl.tpl"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tenant-file)
      [[ "$#" -ge 2 ]] || fail "--tenant-file requires a path."
      tenant_file="$2"
      shift 2
      ;;
    --output)
      [[ "$#" -ge 2 ]] || fail "--output requires a path."
      output_file="$2"
      shift 2
      ;;
    --phase)
      [[ "$#" -ge 2 ]] || fail "--phase requires a value."
      phase="$2"
      shift 2
      ;;
    --keep-output)
      keep_output="true"
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
[[ -f "${tenant_file}" ]] || fail "Missing tenant file: ${tenant_file}"

"${script_dir}/validate-tenant-config.sh" --tenant-file "${tenant_file}" >/dev/null

TENANT_NAME="$(require_yaml_value "${tenant_file}" tenant.name)"
TENANT_NODE="$(require_yaml_value "${tenant_file}" tenant.node)"
release="$(require_yaml_value "${tenant_file}" components.openbao.release)"
release_file="$(resolve_release_file "${release}")"
OPENBAO_IMAGE="$(resolve_release_image "${release_file}")"
NAMESPACE="$(derive_namespace "${TENANT_NAME}")"
SERVICE_ACCOUNT_NAME="$(derive_service_account_name)"
CONFIGMAP_NAME="$(derive_configmap_name)"
STATEFULSET_NAME="$(derive_statefulset_name)"
DATA_VOLUME_NAME="$(derive_data_volume_name)"
STORAGE_CLASS="$(require_yaml_value "${tenant_file}" storage.openbao.class)"
STORAGE_SIZE="$(require_yaml_value "${tenant_file}" storage.openbao.size)"
TRANSIT_ADDRESS="$(require_yaml_value "${tenant_file}" openbao.transit.address)"
TRANSIT_TLS_SERVER_NAME="$(validate_transit_address "${TRANSIT_ADDRESS}")"
TRANSIT_KEY_NAME="$(optional_yaml_value "${tenant_file}" openbao.transit.keyName "$(derive_transit_key_name "${TENANT_NODE}")")"
TRANSIT_MOUNT_PATH="$(optional_yaml_value "${tenant_file}" openbao.transit.mountPath "$(derive_transit_mount_path)")"
TRANSIT_CA_BUNDLE_CONFIGMAP_NAME="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName "$(derive_transit_ca_bundle_configmap_name)")"
TRANSIT_CA_BUNDLE_KEY="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleKey "$(derive_transit_ca_bundle_key)")"
TRANSIT_CA_BUNDLE_PATH="$(optional_yaml_value "${tenant_file}" openbao.transit.caBundleMountPath "$(derive_transit_ca_bundle_mount_path)")"
TRANSIT_TOKEN_SECRET_NAME="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretName "$(derive_transit_token_secret_name)")"
TRANSIT_TOKEN_SECRET_KEY="$(optional_yaml_value "${tenant_file}" openbao.transit.tokenSecretKey "$(derive_transit_token_secret_key)")"

if rendered_config="$(render_openbao_config | sed 's/^/    /')"; then
  OPENBAO_CONFIG="${rendered_config}"
else
  fail "Could not render OpenBao bootstrap config"
fi

case "${phase}" in
  foundation)
    template_file="${openbao_component_dir}/manifests/foundation.yaml.tpl"
    ;;
  statefulset)
    template_file="${openbao_component_dir}/manifests/bootstrap.yaml.tpl"
    ;;
  all)
    template_file=""
    ;;
  *)
    fail "Unknown phase: ${phase}"
    ;;
esac

render_phase() {
  if [[ "${phase}" = "all" ]]; then
    replace_vars "${openbao_component_dir}/manifests/foundation.yaml.tpl"
    echo "---"
    replace_vars "${openbao_component_dir}/manifests/bootstrap.yaml.tpl"
  else
    replace_vars "${template_file}"
  fi
}

if [[ -n "${output_file}" ]]; then
  render_phase > "${output_file}"
  chmod 0600 "${output_file}"
  echo "Rendered Tenant OpenBao bootstrap manifest (${phase}): ${output_file}" >&2
  echo "No Secret data was rendered." >&2
elif [[ "${keep_output}" = "true" ]]; then
  output_file="$(mktemp /tmp/tenant-openbao-bootstrap.XXXXXX.yaml)"
  render_phase > "${output_file}"
  chmod 0600 "${output_file}"
  echo "Rendered Tenant OpenBao bootstrap manifest (${phase}): ${output_file}" >&2
  echo "No Secret data was rendered." >&2
else
  render_phase
fi
