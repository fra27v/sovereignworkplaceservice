#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tenant_root="${repo_root}/tenants/family-infra"
script="${tenant_root}/scripts/fetch-operator-trust.sh"
tenant_file="${tenant_root}/tenant.yaml"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "unexpected file: $1"
}

make_ca_fixture() {
  local fixture_dir="$1"
  mkdir -p "$fixture_dir"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${fixture_dir}/operator-ca.key" \
    -out "${fixture_dir}/operator-ca-bundle.pem" \
    -subj "/CN=family-infra test operator CA" \
    -days 1 \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
  (
    cd "$fixture_dir"
    sha256sum operator-ca-bundle.pem > operator-ca-bundle.pem.sha256
  )
}

make_mock_curl() {
  local bin_dir="$1"
  local fixture_dir="$2"
  local calls_file="$3"
  mkdir -p "$bin_dir"
  cat > "${bin_dir}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

out=""
user=""
url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -u)
      user="$2"
      shift 2
      ;;
    --insecure|-k)
      echo "insecure curl option was used" >&2
      exit 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[ "$user" = "family-infra-01" ] || {
  echo "unexpected BasicAuth user: $user" >&2
  exit 2
}

case "$url" in
  https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem)
    cp "${FIXTURE_DIR}/operator-ca-bundle.pem" "$out"
    ;;
  https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem.sha256)
    cp "${FIXTURE_DIR}/operator-ca-bundle.pem.sha256" "$out"
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 2
    ;;
esac

printf '%s %s\n' "$user" "$url" >> "$CALLS_FILE"
MOCK_CURL
  chmod 755 "${bin_dir}/curl"
}

run_with_fixture() {
  local fixture_dir="$1"
  local output_dir="$2"
  local temp_dir="$3"
  local mock_bin="${temp_dir}/bin"
  local calls_file="${temp_dir}/curl.calls"

  make_mock_curl "$mock_bin" "$fixture_dir" "$calls_file"
  FIXTURE_DIR="$fixture_dir" CALLS_FILE="$calls_file" PATH="${mock_bin}:$PATH" \
    bash "$script" --output-dir "$output_dir" > "${temp_dir}/run.out" 2> "${temp_dir}/run.err"
}

test_valid_ca_passes() {
  local temp_dir="$1/valid"
  local fixture_dir="${temp_dir}/fixture"
  local output_dir="${temp_dir}/out"
  mkdir -p "$temp_dir"
  make_ca_fixture "$fixture_dir"

  run_with_fixture "$fixture_dir" "$output_dir" "$temp_dir"

  assert_file "${output_dir}/operator-ca-bundle.pem"
  assert_file "${output_dir}/operator-ca-bundle.pem.sha256"
  grep -q 'family-infra-01 https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem$' "${temp_dir}/curl.calls" || fail "CA URL was not requested with derived username"
  grep -q 'family-infra-01 https://operator-artifacts.varrese.com/tenants/family-infra-01/trust/operator-ca-bundle.pem.sha256$' "${temp_dir}/curl.calls" || fail "checksum URL was not requested with derived username"
}

test_checksum_mismatch_fails_before_publish() {
  local temp_dir="$1/checksum"
  local fixture_dir="${temp_dir}/fixture"
  local output_dir="${temp_dir}/out"
  mkdir -p "$temp_dir" "$output_dir"
  make_ca_fixture "$fixture_dir"
  printf '0000000000000000000000000000000000000000000000000000000000000000  operator-ca-bundle.pem\n' > "${fixture_dir}/operator-ca-bundle.pem.sha256"

  if run_with_fixture "$fixture_dir" "$output_dir" "$temp_dir"; then
    fail "checksum mismatch should fail"
  fi

  assert_no_file "${output_dir}/operator-ca-bundle.pem"
  assert_no_file "${output_dir}/operator-ca-bundle.pem.sha256"
}

test_invalid_pem_fails_before_publish() {
  local temp_dir="$1/invalid-pem"
  local fixture_dir="${temp_dir}/fixture"
  local output_dir="${temp_dir}/out"
  mkdir -p "$fixture_dir" "$output_dir"
  printf 'not a certificate\n' > "${fixture_dir}/operator-ca-bundle.pem"
  (
    cd "$fixture_dir"
    sha256sum operator-ca-bundle.pem > operator-ca-bundle.pem.sha256
  )

  if run_with_fixture "$fixture_dir" "$output_dir" "$temp_dir"; then
    fail "invalid PEM should fail"
  fi

  assert_no_file "${output_dir}/operator-ca-bundle.pem"
  assert_no_file "${output_dir}/operator-ca-bundle.pem.sha256"
}

test_https_required() {
  local temp_dir="$1/http"
  mkdir -p "${temp_dir}/scripts"
  cp "$script" "${temp_dir}/scripts/fetch-operator-trust.sh"
  sed 's#https://operator-artifacts.varrese.com#http://operator-artifacts.varrese.com#' "$tenant_file" > "${temp_dir}/tenant.yaml"

  if bash "${temp_dir}/scripts/fetch-operator-trust.sh" --output-dir "${temp_dir}/out" > "${temp_dir}/run.out" 2> "${temp_dir}/run.err"; then
    fail "HTTP artifacts endpoint should fail"
  fi

  grep -q 'must use HTTPS' "${temp_dir}/run.err" || fail "HTTPS failure message missing"
}

test_repo_files_do_not_accept_cli_credentials() {
  if grep -- '--password\|--token\|curl .* -u .*:' "$script" >/dev/null 2>&1; then
    fail "script exposes credential-style CLI usage"
  fi
  if grep -- '--insecure\|curl .* -k' "$script" >/dev/null 2>&1; then
    fail "script allows insecure curl"
  fi
}

main() {
  [ -f "$script" ] || fail "script not found"
  bash -n "$script"

  grep -q '^  node: family-infra-01$' "$tenant_file" || fail "tenant.node not configured"
  grep -q '^    address: https://operator-artifacts.varrese.com$' "$tenant_file" || fail "operator artifacts address not configured"

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/family-infra-fetch-operator-trust-test.XXXXXX")"
  trap 'rm -rf "${temp_root:-}"' EXIT

  test_valid_ca_passes "$temp_root"
  test_checksum_mismatch_fails_before_publish "$temp_root"
  test_invalid_pem_fails_before_publish "$temp_root"
  test_https_required "$temp_root"
  test_repo_files_do_not_accept_cli_credentials

  printf 'ok - fetch-operator-trust tenant tests passed\n'
}

main "$@"
