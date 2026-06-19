#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../../../../.." && pwd)"
traefik_dir="${repo_root}/k8s/operator-plane/environments/vps-family-control/traefik"
env_file="${traefik_dir}/traefik-acme-dns01.env"
env_template="${traefik_dir}/traefik-acme-dns01.env.example"
render_script="${script_dir}/render-traefik-acme-dns01-ovh.sh"
rendered_file="$(mktemp /tmp/traefik-helmchartconfig-acme-dns01-ovh.install.XXXXXX.yaml)"
target_file="/var/lib/rancher/k3s/server/manifests/traefik-helmchartconfig-acme-dns01-ovh.yaml"

cleanup() {
  rm -f "${rendered_file}"
}
trap cleanup EXIT

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

missing_env_file() {
  cat >&2 <<EOF
Missing Traefik ACME DNS-01 environment file:
  ${env_file}

Create it from the template:
  cp ${env_template} ${env_file}

Then edit all required placeholder values before rerunning this script.

The real env file is intentionally gitignored and must not be committed.
EOF
  exit 1
}

require_var() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || fail "Missing required variable: ${name}"
  [[ "${value}" != "<set-me>" ]] || fail "Variable still has placeholder value: ${name}"
}

print_reconciliation_diagnostics() {
  cat <<EOF
k3s Helm reconciliation did not update Traefik Service externalTrafficPolicy in time.
Safe diagnostics:
  kubectl -n ${TRAEFIK_NAMESPACE} get helmchart traefik -o wide
  kubectl -n ${TRAEFIK_NAMESPACE} get helmchartconfig ${TRAEFIK_HELMCHARTCONFIG_NAME} -o yaml
  kubectl -n ${TRAEFIK_NAMESPACE} get svc traefik -o yaml
  kubectl -n ${TRAEFIK_NAMESPACE} get jobs,pods | grep -Ei 'helm|traefik'

Do not print or paste Kubernetes Secret data or OVH credentials.
EOF
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this script as root because it writes to the k3s server manifests directory." >&2
  exit 1
fi

command -v kubectl >/dev/null 2>&1 || fail "Missing required command: kubectl"
[[ -f "${env_file}" ]] || missing_env_file

# shellcheck source=/dev/null
source "${env_file}"

required_vars=(
  TRAEFIK_NAMESPACE
  TRAEFIK_HELMCHARTCONFIG_NAME
  TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY
)

for var_name in "${required_vars[@]}"; do
  require_var "${var_name}"
done

case "${TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY}" in
  Local|Cluster)
    ;;
  *)
    fail "TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY must be Local or Cluster."
    ;;
esac

"${render_script}" --output "${rendered_file}"

install -o root -g root -m 0644 "${rendered_file}" "${target_file}"

echo "Installed Traefik HelmChartConfig manifest for k3s reconciliation."
echo "Target file: ${target_file}"
echo "This script does not edit the Traefik Deployment directly."

echo "Waiting for Traefik Service externalTrafficPolicy to reconcile to ${TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY}."
deadline=$((SECONDS + 180))
while true; do
  live_external_traffic_policy="$(kubectl -n "${TRAEFIK_NAMESPACE}" get svc traefik -o jsonpath='{.spec.externalTrafficPolicy}' 2>/dev/null || true)"
  if [[ "${live_external_traffic_policy}" = "${TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY}" ]]; then
    echo "Traefik Service externalTrafficPolicy reconciled."
    break
  fi

  if [[ "${SECONDS}" -ge "${deadline}" ]]; then
    echo "Expected externalTrafficPolicy: ${TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY}"
    echo "Live externalTrafficPolicy: ${live_external_traffic_policy:-<empty>}"
    print_reconciliation_diagnostics
    exit 1
  fi

  echo "Waiting for k3s Helm reconciliation. Current externalTrafficPolicy: ${live_external_traffic_policy:-<empty>}"
  sleep 5
done

cleanup
echo "Temporary rendered file was removed."
echo "Safe verification commands:"
echo "  kubectl -n kube-system get helmchartconfig traefik -o yaml"
echo "  kubectl -n kube-system get svc traefik -o jsonpath='{.spec.type}{\" externalTrafficPolicy=\"}{.spec.externalTrafficPolicy}{\"\\n\"}'"
echo "  kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik"
echo "  kubectl -n kube-system logs deploy/traefik --tail=120"
