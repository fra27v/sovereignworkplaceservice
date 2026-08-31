#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tenant_file=""
mode=""
phase=""

usage() {
  cat <<'USAGE'
Usage:
  reconcile-bootstrap.sh --phase foundation --dry-run [--tenant-file <path>]
  reconcile-bootstrap.sh --phase foundation --apply [--tenant-file <path>]
  reconcile-bootstrap.sh --phase statefulset --dry-run [--tenant-file <path>]
  reconcile-bootstrap.sh --phase statefulset --apply [--tenant-file <path>]

Renders and reconciles one explicit Tenant OpenBao bootstrap phase. Both
--phase and exactly one of --dry-run or --apply are mandatory. Calling this
script without them fails safely.

Modes:
  --dry-run
      Run Kubernetes server-side validation for the selected phase. This does
      not mutate cluster resources.

  --apply
      Apply the selected phase to the cluster.

Phases:
  foundation
      Creates only the Tenant OpenBao Kubernetes Namespace. It does not deploy
      OpenBao. Use this first so the Operator CA ConfigMap and Transit token
      Secret can be projected into the namespace.

      After foundation --apply:
        1. Project Operator CA ConfigMap.
        2. Project Transit token Secret.
        3. Run live Transit preflight.
        4. Continue with the statefulset phase.

  statefulset
      Creates the bootstrap workload:
        - ServiceAccount
        - OpenBao bootstrap ConfigMap
        - StatefulSet
        - Raft PVC through volumeClaimTemplate

      Use this only after foundation and Transit prerequisites are ready.
      statefulset --apply runs live Transit preflight first. If Transit
      prerequisites fail, the StatefulSet is not deployed.

There is intentionally no "all" phase for reconciliation. Foundation and
StatefulSet must be applied separately so Transit prerequisites can be projected
and verified between them. To review the complete configuration without
applying it, render it instead:

  render-bootstrap.sh --phase all

Workflow:
  1. foundation --dry-run
  2. foundation --apply
  3. project Operator CA
  4. project Transit token
  5. verify Transit preflight
  6. statefulset --dry-run
  7. statefulset --apply
  8. verify READY_FOR_INIT
  9. STOP before operator init

This script never runs bao operator init and never creates a Service, Ingress,
IngressRoute, Traefik route, TLS certificate, or tenant PKI.
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
      [[ -z "${mode}" ]] || fail "Specify only one mode."
      mode="dry-run"
      shift
      ;;
    --apply)
      [[ -z "${mode}" ]] || fail "Specify only one mode."
      mode="apply"
      shift
      ;;
    --phase)
      [[ "$#" -ge 2 ]] || fail "--phase requires a value."
      phase="$2"
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

[[ -n "${mode}" ]] || {
  usage >&2
  fail "Missing required mode: use --dry-run or --apply."
}

[[ "${phase}" = "foundation" || "${phase}" = "statefulset" ]] || {
  usage >&2
  fail "Missing or invalid --phase: use foundation or statefulset."
}

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"

manifest_file="$(mktemp /tmp/tenant-openbao-bootstrap.XXXXXX.yaml)"
cleanup() {
  rm -f "${manifest_file}"
}
trap cleanup EXIT

render_args=(--phase "${phase}" --output "${manifest_file}")
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

if [[ "${mode}" = "dry-run" ]]; then
  kubectl apply --dry-run=server -f "${manifest_file}"
  echo "Dry-run completed. No Kubernetes resources were changed."
else
  if [[ "${phase}" = "statefulset" ]]; then
    preflight_args=(--live)
    if [[ -n "${tenant_file}" ]]; then
      preflight_args+=(--tenant-file "${tenant_file}")
    fi
    "${script_dir}/verify-transit-preflight.sh" "${preflight_args[@]}"
  fi
  kubectl apply -f "${manifest_file}"
  echo "Bootstrap ${phase} reconciled. OpenBao remains uninitialized until explicit operator init."
fi
