#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
render_script="${script_dir}/render-traefik-acme-dns01-ovh.sh"
rendered_file="$(mktemp /tmp/traefik-helmchartconfig-acme-dns01-ovh.install.XXXXXX.yaml)"
target_file="/var/lib/rancher/k3s/server/manifests/traefik-helmchartconfig-acme-dns01-ovh.yaml"

cleanup() {
  rm -f "${rendered_file}"
}
trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this script as root because it writes to the k3s server manifests directory." >&2
  exit 1
fi

"${render_script}" --output "${rendered_file}"

install -o root -g root -m 0644 "${rendered_file}" "${target_file}"

echo "Installed Traefik HelmChartConfig manifest for k3s reconciliation."
echo "Target file: ${target_file}"
echo "This script does not edit the Traefik Deployment directly."
echo "Temporary rendered file will be removed after script completion."
echo "Safe verification commands:"
echo "  kubectl -n kube-system get helmchartconfig traefik -o yaml"
echo "  kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik"
echo "  kubectl -n kube-system logs deploy/traefik --tail=120"
