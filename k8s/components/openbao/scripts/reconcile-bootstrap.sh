#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tenant_file=""
dry_run="false"

usage() {
  cat <<'USAGE'
Usage:
  reconcile-bootstrap.sh --dry-run [--tenant-file <path>]
  reconcile-bootstrap.sh --apply [--tenant-file <path>]

Renders and reconciles the Tenant OpenBao bootstrap foundation. This script
never runs bao operator init and never creates a Service, Ingress, IngressRoute,
Traefik route, TLS certificate, or tenant PKI.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tenant-file)
      [[ "$#" -ge 2 ]] || fail "--tenant-file requires a path."
      tenant_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --apply)
      dry_run="false"
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

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"

manifest_file="$(mktemp /tmp/tenant-openbao-bootstrap.XXXXXX.yaml)"
cleanup() {
  rm -f "${manifest_file}"
}
trap cleanup EXIT

render_args=(--output "${manifest_file}")
if [[ -n "${tenant_file}" ]]; then
  render_args+=(--tenant-file "${tenant_file}")
fi
"${script_dir}/render-bootstrap.sh" "${render_args[@]}" >/dev/null

if grep -Eq '^kind: (Service|Ingress|IngressRoute|IngressRouteTCP)$' "${manifest_file}"; then
  fail "Rendered bootstrap manifest contains forbidden network exposure"
fi

if grep -q '0.0.0.0:8200' "${manifest_file}"; then
  fail "Rendered bootstrap manifest contains forbidden bootstrap listener 0.0.0.0:8200"
fi

if [[ "${dry_run}" = "true" ]]; then
  kubectl apply --dry-run=server -f "${manifest_file}"
  echo "Dry-run completed. No Kubernetes resources were changed."
else
  kubectl apply -f "${manifest_file}"
  echo "Bootstrap foundation reconciled. OpenBao remains uninitialized until explicit operator init."
fi
