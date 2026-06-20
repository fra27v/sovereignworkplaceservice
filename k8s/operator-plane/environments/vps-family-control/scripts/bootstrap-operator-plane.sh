#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_dir="$(cd -- "${script_dir}/.." && pwd)"

dry_run="false"
run_traefik="false"
run_openbao="false"
run_operator_artifacts="false"

summary_ok=()
summary_warn=()
summary_fail=()

usage() {
  cat <<EOF
Usage: $0 [--all] [--traefik] [--openbao] [--operator-artifacts] [--dry-run]

Bootstrap the vps-family-control operator plane by orchestrating validated
component entrypoints.

Options:
  --all                 Run all currently supported phases.
  --traefik             Run Traefik ACME DNS-01 OVH bootstrap.
  --openbao             Run Global OpenBao baseline verification only.
  --operator-artifacts  Run operator-artifacts bootstrap.
  --dry-run             Print commands without running component scripts.
  --help                Show this help.

Safety:
  - This script is non-destructive and idempotent.
  - It does not delete or rotate secrets.
  - It does not print secret values.
  - It does not initialize OpenBao directly.
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

  echo "+ ${path}"
  if [[ "${dry_run}" = "true" ]]; then
    echo "DRY-RUN: would run ${path}"
    return 0
  fi

  if "${path}"; then
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
  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "Global OpenBao phase completed"
  fi
}

phase_operator_artifacts() {
  echo
  echo "== operator-artifacts =="
  local artifacts_scripts="${env_dir}/operator-artifacts/scripts"
  local fail_count_before="${#summary_fail[@]}"

  run_if_executable "operator-artifacts local file preparation" "${artifacts_scripts}/prepare-local-operator-artifacts-files.sh" "false"
  run_if_executable "family-infra-01 artifact token creation" "${artifacts_scripts}/create-family-infra-01-artifact-token.sh" "false"
  run_if_executable "operator-artifacts install" "${artifacts_scripts}/install-operator-artifacts.sh" "true"
  run_if_executable "operator-artifacts verify" "${artifacts_scripts}/verify-operator-artifacts.sh" "false"
  if [[ "${#summary_fail[@]}" -eq "${fail_count_before}" ]]; then
    ok "operator-artifacts phase completed"
  fi
}

phase_operator_pki_placeholder() {
  echo
  echo "== Operator PKI =="
  echo "TODO: next phase"
  warn "Operator PKI is not implemented yet"
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
      run_operator_artifacts="true"
      ;;
    --traefik)
      run_traefik="true"
      ;;
    --openbao)
      run_openbao="true"
      ;;
    --operator-artifacts)
      run_operator_artifacts="true"
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

if [[ "${run_traefik}" != "true" && "${run_openbao}" != "true" && "${run_operator_artifacts}" != "true" ]]; then
  usage >&2
  exit 1
fi

phase_prerequisites

if [[ "${run_traefik}" = "true" ]]; then
  phase_traefik
fi

if [[ "${run_openbao}" = "true" ]]; then
  phase_openbao_global
fi

if [[ "${run_operator_artifacts}" = "true" ]]; then
  phase_operator_artifacts
fi

phase_operator_pki_placeholder
phase_summary

if [[ "${#summary_fail[@]}" -gt 0 ]]; then
  exit 1
fi
