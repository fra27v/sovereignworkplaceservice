#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
ERROR: check-runner-image-contract.sh is deprecated and non-authoritative.

The former Docker-based validation path is intentionally disabled. Use the
dependency-lock-driven Kubernetes validation instead:

  ./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/validate-runner-image-contract.sh --dry-run
  ./k8s/operator-plane/environments/vps-family-control/scripts/bootstrap-operator-plane.sh --operator-secret-sync-runner-image

The authoritative validation must run through Kubernetes/k3s/containerd, not
Docker.
EOF

exit 1
