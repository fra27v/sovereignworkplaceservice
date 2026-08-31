#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Fetch verified public Operator trust material for the family-infra tenant.

This script is tenant-specific. It reads tenant.node and
operatorPlane.artifacts.address from ../tenant.yaml, then downloads:

  /tenants/<tenant.node>/trust/operator-ca-bundle.pem
  /tenants/<tenant.node>/trust/operator-ca-bundle.pem.sha256

The BasicAuth username is derived from tenant.node. curl prompts
interactively for the BasicAuth credential; the credential is never accepted
as a command-line value, printed, written to tenant.yaml, or stored on disk by
this script.

The Operator CA bundle is public trust material, not a Kubernetes Secret. The
PEM and its relative-name SHA256 checksum are verified before anything is
published to the output directory. The certificate must parse as X.509 and
must be a CA certificate.

Usage:
  fetch-operator-trust.sh [--output-dir <path>]
  fetch-operator-trust.sh --help

Options:
  --output-dir <path>  Directory for verified operator-ca-bundle.pem and
                       operator-ca-bundle.pem.sha256. It is created if
                       needed. If omitted, a secure temporary output directory
                       is created and left in place on success.
  --help               Show this help.

Current bootstrap usage: run this before Tenant OpenBao bootstrap needs to
trust the operator-plane artifacts and Transit endpoints.

Future behavior, not implemented here: if Tenant OpenBao is available and
contains the operator-artifacts credential, retrieve it from Tenant OpenBao;
otherwise keep prompting interactively.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

yaml_value() {
  local file="$1"
  local path="$2"
  awk -v target="$path" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function unquote(value) {
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
        return substr(value, 2, length(value) - 2)
      }
      return value
    }
    /^[[:space:]]*($|#)/ { next }
    {
      match($0, /^ */)
      indent = RLENGTH / 2
      line = trim($0)
      split(line, parts, ":")
      key = trim(parts[1])
      value = substr(line, index(line, ":") + 1)
      keys[indent] = key
      for (level in keys) {
        if (level > indent) {
          delete keys[level]
        }
      }
      if (trim(value) != "") {
        candidate = ""
        for (i = 0; i <= indent; i++) {
          if (keys[i] == "") {
            next
          }
          candidate = candidate (candidate == "" ? "" : ".") keys[i]
        }
        if (candidate == target) {
          print unquote(value)
          found = 1
          exit
        }
      }
    }
    END { if (!found) exit 1 }
  ' "$file"
}

download_file() {
  local url="$1"
  local destination="$2"

  curl -fsS --proto '=https' --tlsv1.2 -u "${tenant_node}" -o "${destination}" "${url}"
}

output_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ "$#" -ge 2 ] || die "--output-dir requires a path"
      output_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tenant_file="$(cd "${script_dir}/.." && pwd)/tenant.yaml"

[ -f "$tenant_file" ] || die "tenant configuration not found: ${tenant_file}"

tenant_node="$(yaml_value "$tenant_file" "tenant.node")" || die "missing tenant.node in ${tenant_file}"
artifacts_address="$(yaml_value "$tenant_file" "operatorPlane.artifacts.address")" || die "missing operatorPlane.artifacts.address in ${tenant_file}"

[ -n "$tenant_node" ] || die "tenant.node is empty"
[ -n "$artifacts_address" ] || die "operatorPlane.artifacts.address is empty"

case "$artifacts_address" in
  https://*) ;;
  *) die "operatorPlane.artifacts.address must use HTTPS" ;;
esac

artifacts_address="${artifacts_address%/}"
trust_path="/tenants/${tenant_node}/trust"
ca_file="operator-ca-bundle.pem"
checksum_file="${ca_file}.sha256"
ca_url="${artifacts_address}${trust_path}/${ca_file}"
checksum_url="${artifacts_address}${trust_path}/${checksum_file}"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/family-infra-operator-trust-work.XXXXXX")"
chmod 700 "$work_dir"
cleanup_work_dir=true

if [ -z "$output_dir" ]; then
  output_dir="$(mktemp -d "${TMPDIR:-/tmp}/family-infra-operator-trust.XXXXXX")"
  chmod 700 "$output_dir"
  created_output_dir=true
else
  mkdir -p "$output_dir"
  created_output_dir=false
fi

cleanup() {
  if [ "${cleanup_work_dir}" = "true" ] && [ -n "${work_dir:-}" ] && [ -d "$work_dir" ]; then
    rm -rf "$work_dir"
  fi
  if [ "${created_output_dir:-false}" = "true" ] && [ "${success:-false}" != "true" ] && [ -n "${output_dir:-}" ] && [ -d "$output_dir" ]; then
    rm -rf "$output_dir"
  fi
}
trap cleanup EXIT

printf 'Tenant node: %s\n' "$tenant_node"
printf 'Artifacts endpoint: %s\n' "$artifacts_address"
printf 'Downloading public Operator CA bundle with BasicAuth username: %s\n' "$tenant_node"

download_file "$ca_url" "${work_dir}/${ca_file}"
download_file "$checksum_url" "${work_dir}/${checksum_file}"

(
  cd "$work_dir"
  sha256sum -c "$checksum_file"
)

openssl x509 -in "${work_dir}/${ca_file}" -noout >/dev/null

if ! openssl x509 -in "${work_dir}/${ca_file}" -noout -text | grep -A2 'Basic Constraints' | grep -q 'CA:TRUE'; then
  die "operator-ca-bundle.pem is not a CA certificate"
fi

cp "${work_dir}/${ca_file}" "${output_dir}/${ca_file}"
cp "${work_dir}/${checksum_file}" "${output_dir}/${checksum_file}"
chmod 644 "${output_dir}/${ca_file}" "${output_dir}/${checksum_file}"

printf 'Verified trust material written to: %s\n' "$output_dir"
openssl x509 -in "${output_dir}/${ca_file}" -noout -subject -issuer -dates -fingerprint -sha256

success=true
