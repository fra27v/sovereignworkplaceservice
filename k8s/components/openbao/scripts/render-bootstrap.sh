#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

tenant_file=""
output_file=""
keep_output="false"

usage() {
  cat <<'USAGE'
Usage:
  render-bootstrap.sh [--tenant-file <path>] [--output <path>] [--keep-output] [--help]

Renders the Tenant OpenBao bootstrap manifest. The manifest intentionally
contains no OpenBao Service, Ingress, IngressRoute, Traefik route, or Secret
data values. By default the output is printed to stdout.
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
    ' "${openbao_component_dir}/manifests/bootstrap.yaml.tpl"
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
NAMESPACE="$(require_yaml_value "${tenant_file}" openbao.namespace)"
SERVICE_ACCOUNT_NAME="$(require_yaml_value "${tenant_file}" openbao.serviceAccountName)"
CONFIGMAP_NAME="$(require_yaml_value "${tenant_file}" openbao.configMapName)"
STATEFULSET_NAME="$(require_yaml_value "${tenant_file}" openbao.statefulSetName)"
DATA_VOLUME_NAME="$(require_yaml_value "${tenant_file}" openbao.dataVolumeName)"
STORAGE_CLASS="$(require_yaml_value "${tenant_file}" storage.openbao.class)"
STORAGE_SIZE="$(require_yaml_value "${tenant_file}" storage.openbao.size)"
TRANSIT_ADDRESS="$(require_yaml_value "${tenant_file}" openbao.transit.address)"
TRANSIT_KEY_NAME="$(require_yaml_value "${tenant_file}" openbao.transit.keyName)"
TRANSIT_MOUNT_PATH="$(require_yaml_value "${tenant_file}" openbao.transit.mountPath)"
TRANSIT_TLS_SERVER_NAME="$(require_yaml_value "${tenant_file}" openbao.transit.tlsServerName)"
TRANSIT_CA_BUNDLE_CONFIGMAP_NAME="$(require_yaml_value "${tenant_file}" openbao.transit.caBundleConfigMapName)"
TRANSIT_CA_BUNDLE_KEY="$(require_yaml_value "${tenant_file}" openbao.transit.caBundleKey)"
TRANSIT_CA_BUNDLE_PATH="$(require_yaml_value "${tenant_file}" openbao.transit.caBundleMountPath)"
TRANSIT_TOKEN_SECRET_NAME="$(require_yaml_value "${tenant_file}" openbao.transit.tokenSecretName)"
TRANSIT_TOKEN_SECRET_KEY="$(require_yaml_value "${tenant_file}" openbao.transit.tokenSecretKey)"

if [[ "${TRANSIT_ADDRESS}" != https://* ]]; then
  fail "Transit address must use HTTPS: ${TRANSIT_ADDRESS}"
fi

if rendered_config="$(render_openbao_config | sed 's/^/    /')"; then
  OPENBAO_CONFIG="${rendered_config}"
else
  fail "Could not render OpenBao bootstrap config"
fi

if [[ -n "${output_file}" ]]; then
  replace_vars > "${output_file}"
  chmod 0600 "${output_file}"
  echo "Rendered Tenant OpenBao bootstrap manifest: ${output_file}" >&2
  echo "No Secret data was rendered." >&2
elif [[ "${keep_output}" = "true" ]]; then
  output_file="$(mktemp /tmp/tenant-openbao-bootstrap.XXXXXX.yaml)"
  replace_vars > "${output_file}"
  chmod 0600 "${output_file}"
  echo "Rendered Tenant OpenBao bootstrap manifest: ${output_file}" >&2
  echo "No Secret data was rendered." >&2
else
  replace_vars
fi
