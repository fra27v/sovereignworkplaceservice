#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"

dry_run="false"
env_file="${env_dir}/operator-plane.env"
run_traefik="false"
run_openbao="false"
run_operator_secret_sync_ca_bundle="false"
run_operator_secret_sync_foundation="false"
run_operator_secret_sync_runner_image="false"
run_operator_secret_sync_job="false"
run_operator_artifacts="false"
run_operator_pki="false"
run_operator_vault_tls="false"
run_operator_vault_public_endpoint="false"
run_openbao_operator_kv="false"
run_openbao_transit_configure="false"

summary_ok=()
summary_warn=()
summary_fail=()

usage() {
  cat <<EOF
Usage: $0 [--all] [--traefik] [--openbao] [--openbao-operator-kv] [--operator-secret-sync-ca-bundle] [--operator-secret-sync-foundation] [--operator-secret-sync-runner-image] [--operator-secret-sync-job] [--operator-artifacts] [--operator-pki] [--operator-vault-tls] [--operator-vault-public-endpoint] [--env-file <path>] [--dry-run]

Bootstrap the vps-family-control operator plane by orchestrating validated
component entrypoints.

Options:
  --all                              Run all currently supported phases.
  --traefik                          Run Traefik ACME DNS-01 OVH bootstrap.
  --openbao                          Run Global OpenBao baseline verification only.
  --openbao-operator-kv              Configure the Global OpenBao operator-kv KV v2 mount.
  --operator-secret-sync-ca-bundle   Project OpenBao CA bundle into operator-secret-sync namespace.
  --operator-secret-sync-foundation  Install operator-secret-sync foundation without creating or running the Job.
  --operator-secret-sync-runner-image
                                      Validate the locked runner image candidate with a temporary no-secret Kubernetes Job.
  --operator-secret-sync-job         Run the real one-shot sync Job after preflight.
  --operator-artifacts               Run operator-artifacts bootstrap.
  --operator-pki                     Configure and verify Operator PKI foundation.
  --operator-vault-tls               Issue and install operator-vault runtime TLS, then restart OpenBao.
  --operator-vault-public-endpoint   Reconcile Traefik TCP passthrough endpoint for operator-vault.
  --env-file <path>                  Path to the central operator-plane.env file.
  --dry-run                          Print commands without running component scripts.
  --help                             Show this help.

Safety:
  - This script is non-destructive and idempotent.
  - It does not delete or rotate secrets.
  - It does not print secret values.
  - It does not initialize OpenBao directly.
  - --operator-secret-sync-ca-bundle projects public CA trust material only.
  - --operator-secret-sync-foundation installs ServiceAccount, RBAC, script
    ConfigMap, CA bundle projection, and OpenBao Kubernetes auth without
    running the sync Job or selecting a runner image.
  - --operator-secret-sync-runner-image validates only the candidate image from
    dependencies.lock.json through Kubernetes/k3s/containerd-compatible
    execution. It does not run the real sync Job and does not mutate target
    runtime Secrets.
  - --all currently includes only supported foundation phases and does not
    enable the real operator-secret-sync Job or runner-image validation phase.
  - --openbao-operator-kv is explicit because it creates the versioned
    operator-plane source-of-truth KV mount in Global OpenBao.
  - --operator-secret-sync-job is explicit and runs only when requested.
  - --operator-artifacts --dry-run renders the manifest and runs the
    operator-artifacts installer in server-side dry-run mode.
  - --operator-vault-tls is intentionally explicit because it rotates runtime
    TLS and restarts only the configured OpenBao pod.
  - --operator-vault-public-endpoint is explicit. It uses Traefik TCP
    passthrough; OpenBao terminates TLS and still requires OpenBao auth.
EOF
}

ok() {
  summary_ok+=("$1")
  echo "OK: $1"
}

warn() {
  summary_warn+=("$1")
  echo "WARN: $1" >&2
}

fail() {
  summary_fail+=("$1")
  echo "FAIL: $1" >&2
}

run_if_executable() {
  local label="$1"
  local path="$2"
  local required="${3:-false}"
  shift 3 || true
  local args=("$@")

  if [[ ! -f "${path}" ]]; then
    if [[ "${required}" = "true" ]]; then
      fail "${label} script is missing: ${path}"
      return 0
    fi
    warn "${label} script is missing: ${path}"
    return 0
  fi

  if [[ ! -x "${path}" ]]; then
    if [[ "${required}" = "true" ]]; then
      fail "${label} script is not executable: ${path}"
      return 0
    fi
    warn "${label} script is not executable: ${path}"
    return 0
  fi

  echo "+ ${path}${args[*]:+ ${args[*]}}"
  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would run ${path}${args[*]:+ ${args[*]}}"
    return 0
  fi

  if "${path}" "${args[@]}"; then
    return 0
  fi

  fail "${label} script failed: ${path}"
  return 0
}

phase_prerequisites() {
  echo
  echo "== Prerequisites =="
  if command -v bash >/dev/null 2>&1; then
    ok "bash is available"
  else
    fail "bash is required"
    return 0
  fi

  if command -v kubectl >/dev/null 2>&1; then
    ok "kubectl is available"
  else
    warn "kubectl is not available; component scripts may fail when executed"
  fi
}

phase_traefik() {
  echo
  echo "== Traefik =="
  local traefik_scripts="${env_dir}/traefik/scripts"
  local fail_count_before="${#summary_fail[@]}"

  run_if_executable "Traefik OVH DNS Secret creation" "${traefik_scripts}/create-traefik-ovh-dns-secret.sh" "false"
  run_if_executable "Traefik ACME DNS-01 OVH install" "${traefik_scripts}/install-traefik-acme-dns01-ovh.sh" "true"
  run_if_executable "Traefik ACME DNS-01 OVH verify" "${traefik_scripts}/verify-traefik-acme-dns01-ovh.sh" "false"
  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "Traefik phase completed"
  fi
}

phase_openbao_global() {
  echo
  echo "== Global OpenBao =="
  local openbao_scripts="${env_dir}/openbao/scripts"
  local fail_count_before="${#summary_fail[@]}"

  cat <<EOF
Global OpenBao install, initialization, and transit configuration remain
component-level operations until stable environment entrypoints are validated.

Safe TODO:
  - keep initialization delegated to the existing explicit OpenBao runbook
  - import operator-plane runtime secrets into OpenBao KV
  - add OpenBao KV to Kubernetes Secret sync scripts
  - keep transit keys and future PKI CA keys as OpenBao-managed state
EOF

  run_if_executable "Global OpenBao audit verify" "${openbao_scripts}/verify-openbao-global-audit.sh" "false"
  run_if_executable "Global OpenBao transit verify" "${openbao_scripts}/verify-openbao-global-transit.sh" "false"
  if [[ "${run_openbao_transit_configure}" = "true" ]]; then
    run_if_executable "Global OpenBao transit configure" "${openbao_scripts}/configure-openbao-global-transit-family-infra-01.sh" "false" --env-file "${env_file}"
  fi
  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "Global OpenBao phase completed"
  fi
}

phase_openbao_operator_kv() {
  echo
  echo "== Global OpenBao operator KV =="
  local openbao_scripts="${env_dir}/openbao/scripts"
  local fail_count_before="${#summary_fail[@]}"
  local args=(--env-file "${env_file}")

  if [[ "${dry_run}" = "true" ]]; then
    args+=(--dry-run)
  fi

  run_if_executable "Global OpenBao operator KV configure" "${openbao_scripts}/configure-openbao-global-operator-kv.sh" "true" "${args[@]}"

  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "Global OpenBao operator KV phase completed"
  fi
}

phase_operator_secret_sync() {
  echo
  echo "== operator-secret-sync =="
  local openbao_scripts="${env_dir}/openbao/scripts"
  local sync_scripts="${env_dir}/operator-secret-sync/scripts"
  local fail_count_before="${#summary_fail[@]}"

  if [[ "${run_operator_secret_sync_ca_bundle}" = "true" ]]; then
    run_if_executable "OpenBao CA bundle projection" "${sync_scripts}/install-openbao-ca-bundle-configmap.sh" "true" --env-file "${env_file}"
  fi

  if [[ "${run_operator_secret_sync_foundation}" = "true" ]]; then
    run_if_executable "operator-secret-sync foundation install" "${sync_scripts}/install-operator-secret-sync-foundation.sh" "true" --env-file "${env_file}"
  fi

  if [[ "${run_operator_secret_sync_runner_image}" = "true" ]]; then
    run_if_executable "operator-secret-sync runner image validation" "${sync_scripts}/validate-runner-image-contract.sh" "true"
  fi

  if [[ "${run_operator_secret_sync_job}" = "true" ]]; then
    if [[ "${dry_run}" = "true" ]]; then
      run_if_executable "operator-secret-sync real Job dry-run" "${sync_scripts}/install-operator-secret-sync-job.sh" "true" --env-file "${env_file}" --dry-run
    else
      run_if_executable "operator-secret-sync real Job preflight" "${sync_scripts}/preflight-operator-secret-sync.sh" "true" --env-file "${env_file}"
      run_if_executable "operator-secret-sync real Job install" "${sync_scripts}/install-operator-secret-sync-job.sh" "true" --env-file "${env_file}" --wait
    fi
  fi

  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "operator-secret-sync phase completed"
  fi
}

phase_operator_artifacts() {
  echo
  echo "== operator-artifacts =="
  local artifacts_scripts="${env_dir}/operator-artifacts/scripts"
  local fail_count_before="${#summary_fail[@]}"

  if [[ "${dry_run}" = "true" ]]; then
    local install_script="${artifacts_scripts}/install-operator-artifacts.sh"
    if [[ ! -x "${install_script}" ]]; then
      fail "operator-artifacts install script is missing or not executable: ${install_script}"
      return 0
    fi

    echo "+ ${install_script} --env-file ${env_file} --dry-run"
    if ! "${install_script}" --env-file "${env_file}" --dry-run; then
      fail "operator-artifacts install dry-run failed: ${install_script}"
      return 0
    fi

    if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
      ok "operator-artifacts phase completed"
    fi
    return 0
  fi

  run_if_executable "operator-artifacts local file preparation" "${artifacts_scripts}/prepare-local-operator-artifacts-files.sh" "false" --env-file "${env_file}"
  run_if_executable "family-infra-01 artifact token reconcile" "${artifacts_scripts}/create-family-infra-01-artifact-token.sh" "false" --env-file "${env_file}"
  run_if_executable "operator-artifacts install" "${artifacts_scripts}/install-operator-artifacts.sh" "true" --env-file "${env_file}" --wait
  run_if_executable "operator-artifacts verify" "${artifacts_scripts}/verify-operator-artifacts.sh" "false" --env-file "${env_file}"
  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "operator-artifacts phase completed"
  fi
}

phase_operator_pki() {
  echo
  echo "== Operator PKI =="
  local pki_scripts="${env_dir}/operator-pki/scripts"
  local fail_count_before="${#summary_fail[@]}"

  run_if_executable "Operator PKI configure" "${pki_scripts}/configure-openbao-operator-pki.sh" "true" --env-file "${env_file}"
  run_if_executable "Operator PKI verify" "${pki_scripts}/verify-openbao-operator-pki.sh" "true" --env-file "${env_file}"

  cat <<'EOF'
Safe TODO:
  - run --operator-vault-tls before exposing the public endpoint
  - run --operator-vault-public-endpoint only after the TLS SANs are verified
EOF

  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "Operator PKI phase completed"
  fi
}

phase_operator_vault_tls() {
  echo
  echo "== operator-vault TLS =="
  local pki_scripts="${env_dir}/operator-pki/scripts"
  local fail_count_before="${#summary_fail[@]}"

  cat <<'EOF'
This phase is not included in --all yet because it rotates OpenBao runtime TLS
and restarts the configured OpenBao pod. Run it explicitly during this stage.
EOF

  run_if_executable "operator-vault TLS rotation" "${pki_scripts}/rotate-operator-vault-tls-from-operator-pki.sh" "true" --env-file "${env_file}"
  run_if_executable "operator-vault TLS runtime verify" "${pki_scripts}/verify-operator-vault-tls-runtime.sh" "true" --env-file "${env_file}"

  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "operator-vault TLS phase completed"
  fi
}

phase_operator_vault_public_endpoint() {
  echo
  echo "== operator-vault public endpoint =="
  local openbao_scripts="${env_dir}/openbao/scripts"
  local fail_count_before="${#summary_fail[@]}"
  local args=(--env-file "${env_file}")

  if [[ "${dry_run}" = "true" ]]; then
    args+=(--dry-run)
  fi

  echo "TLS passthrough is used; OpenBao terminates TLS and OpenBao authentication remains required."
  run_if_executable "operator-vault public endpoint install" "${openbao_scripts}/install-operator-vault-public-endpoint.sh" "true" "${args[@]}"

  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "operator-vault public endpoint phase completed"
  fi
}

phase_summary() {
  echo
  echo "== Summary =="
  echo "OK components:"
  if [[ "${#summary_ok[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_ok[@]}"
  fi

  echo "WARN components:"
  if [[ "${#summary_warn[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_warn[@]}"
  fi

  echo "FAIL components:"
  if [[ "${#summary_fail[@]}" -eq 0 ]]; then
    echo "  none"
  else
    printf '  %s\n' "${summary_fail[@]}"
  fi
}

if [[ "$#" -eq 0 ]]; then
  usage >&2
  exit 1
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --all)
      run_traefik="true"
      run_openbao="true"
      run_openbao_operator_kv="true"
      run_operator_secret_sync_ca_bundle="true"
      run_operator_secret_sync_foundation="true"
      run_operator_secret_sync_runner_image="false"
      run_operator_secret_sync_job="false"
      run_operator_artifacts="true"
      run_operator_pki="true"
      ;;
    --traefik)
      run_traefik="true"
      ;;
    --openbao)
      run_openbao="true"
      ;;
    --openbao-operator-kv)
      run_openbao_operator_kv="true"
      ;;
    --operator-secret-sync-ca-bundle)
      run_operator_secret_sync_ca_bundle="true"
      ;;
    --operator-secret-sync-foundation)
      run_operator_secret_sync_foundation="true"
      ;;
    --operator-secret-sync-runner-image)
      run_operator_secret_sync_runner_image="true"
      ;;
    --operator-secret-sync-job)
      run_operator_secret_sync_job="true"
      ;;
    --operator-artifacts)
      run_operator_artifacts="true"
      ;;
    --operator-pki)
      run_operator_pki="true"
      ;;
    --operator-vault-tls)
      run_operator_vault_tls="true"
      ;;
    --operator-vault-public-endpoint)
      run_operator_vault_public_endpoint="true"
      ;;
    --openbao-transit-configure)
      run_openbao_transit_configure="true"
      ;;
    --env-file)
      [[ "$#" -ge 2 ]] || {
        echo "--env-file requires a path." >&2
        exit 1
      }
      env_file="$2"
      shift
      ;;
    --dry-run)
      dry_run="true"
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${run_traefik}" != "true" && "${run_openbao}" != "true" && "${run_openbao_operator_kv}" != "true" && "${run_operator_secret_sync_ca_bundle}" != "true" && "${run_operator_secret_sync_foundation}" != "true" && "${run_operator_secret_sync_runner_image}" != "true" && "${run_operator_secret_sync_job}" != "true" && "${run_operator_artifacts}" != "true" && "${run_operator_pki}" != "true" && "${run_operator_vault_tls}" != "true" && "${run_operator_vault_public_endpoint}" != "true" ]]; then
  usage >&2
  exit 1
fi

phase_prerequisites

if [[ "${run_openbao}" = "true" ]]; then
  phase_openbao_global
fi

if [[ "${run_traefik}" = "true" ]]; then
  phase_traefik
fi

if [[ "${run_operator_artifacts}" = "true" ]]; then
  phase_operator_artifacts
fi

if [[ "${run_operator_pki}" = "true" ]]; then
  phase_operator_pki
fi

if [[ "${run_openbao_operator_kv}" = "true" ]]; then
  phase_openbao_operator_kv
fi

if [[ "${run_operator_secret_sync_job}" = "true" || "${run_operator_secret_sync_runner_image}" = "true" || "${run_operator_secret_sync_foundation}" = "true" || "${run_operator_secret_sync_ca_bundle}" = "true" ]]; then
  phase_operator_secret_sync
fi

if [[ "${run_operator_vault_tls}" = "true" ]]; then
  phase_operator_vault_tls
fi

if [[ "${run_operator_vault_public_endpoint}" = "true" ]]; then
  phase_operator_vault_public_endpoint
fi

phase_summary

if [[ "${#summary_fail[@]}" -gt 0 ]]; then
  exit 1
fi
