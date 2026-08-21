#!/usr/bin/env bash
set -euo pipefail

hostname_value="$(hostname 2>/dev/null || true)"
ssh_port="50022"
update_policy="automatic"
expected_os_id="ubuntu"
expected_version_id="26.04"
expected_os_label="Ubuntu Server 26.04 LTS"
os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
arch_value="${UNAME_M:-$(uname -m)}"
os_only=false

ok_count=0
warn_count=0
fail_count=0

baseline_packages=(
  git
  curl
  ca-certificates
  jq
  bind9-dnsutils
  vim
  htop
  fail2ban
  unattended-upgrades
  openssh-server
)

usage() {
  cat <<'USAGE'
Usage: verify-host-baseline.sh [options]

Read-only verification of the reusable host OS baseline.

Options:
  --hostname <hostname>              Expected host name. Default: current hostname
  --ssh-port <port>                  Expected SSH port. Default: 50022
  --update-policy <automatic|security-only>
                                     Expected unattended-upgrades policy. Default: automatic
  --os-only                          Only run operating system detection checks.
  -h, --help                         Show this help.
USAGE
}

section() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  ok_count=$((ok_count + 1))
  echo "OK: $*"
}

warn() {
  warn_count=$((warn_count + 1))
  echo "WARN: $*"
}

fail_check() {
  fail_count=$((fail_count + 1))
  echo "FAIL: $*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)
        [[ $# -ge 2 ]] || {
          echo "ERROR: --hostname requires a value." >&2
          exit 1
        }
        hostname_value="$2"
        shift 2
        ;;
      --ssh-port)
        [[ $# -ge 2 ]] || {
          echo "ERROR: --ssh-port requires a value." >&2
          exit 1
        }
        ssh_port="$2"
        shift 2
        ;;
      --update-policy)
        [[ $# -ge 2 ]] || {
          echo "ERROR: --update-policy requires a value." >&2
          exit 1
        }
        update_policy="$2"
        shift 2
        ;;
      --os-only)
        os_only=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

check_command() {
  command -v "$1" >/dev/null 2>&1
}

service_enabled() {
  local service_name="$1"
  systemctl is-enabled --quiet "${service_name}" 2>/dev/null
}

unit_file_exists() {
  local service_name="$1"
  systemctl list-unit-files "${service_name}" --no-legend 2>/dev/null | awk -v service_name="${service_name}" '$1 == service_name { found=1 } END { exit found ? 0 : 1 }'
}

is_integer_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

validate_inputs() {
  [[ -n "${hostname_value}" ]] || {
    echo "ERROR: hostname must not be empty." >&2
    exit 1
  }
  is_integer_port "${ssh_port}" || {
    echo "ERROR: --ssh-port must be an integer from 1 to 65535." >&2
    exit 1
  }

  case "${update_policy}" in
    automatic|security-only)
      ;;
    *)
      echo "ERROR: --update-policy must be automatic or security-only." >&2
      exit 1
      ;;
  esac
}

detect_os() {
  if [[ ! -r "${os_release_file}" ]]; then
    return 1
  fi

  (
    # shellcheck disable=SC1090
    . "${os_release_file}"
    printf '%s\n' "${ID:-}" "${VERSION_ID:-}" "${VERSION_CODENAME:-}" "${PRETTY_NAME:-}"
  )
}

sshd_effective_value() {
  local key="$1"
  sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null | awk -v key="${key}" '
    $1 == key && !found {
      value=$2
      found=1
    }
    END {
      if (found) {
        print value
      } else {
        exit 1
      }
    }
  '
}

check_host_identity() {
  local current_hostname
  section "Host identity"

  current_hostname="$(hostname)"
  if [[ "${current_hostname}" == "${hostname_value}" ]]; then
    ok "hostname is ${hostname_value}."
  else
    fail_check "hostname is ${current_hostname}; expected ${hostname_value}."
  fi

  if systemctl is-system-running --quiet 2>/dev/null; then
    ok "systemd reports the system is running."
  else
    warn "systemd state is $(systemctl is-system-running 2>/dev/null || echo unknown)."
  fi
}

check_operating_system() {
  local os_id
  local version_id
  local version_codename
  local pretty_name
  section "Operating system"

  if [[ ! -r "${os_release_file}" ]]; then
    fail_check "cannot read ${os_release_file}; ${expected_os_label} is the expected platform."
    ok "architecture is ${arch_value}."
    return
  fi

  mapfile -t os_info < <(detect_os)
  os_id="${os_info[0]:-}"
  version_id="${os_info[1]:-}"
  version_codename="${os_info[2]:-unknown}"
  pretty_name="${os_info[3]:-unknown}"

  if [[ "${os_id}" == "${expected_os_id}" ]]; then
    ok "operating system is Ubuntu."
    if [[ "${version_id}" == "${expected_version_id}" ]]; then
      ok "Ubuntu ${expected_version_id} LTS matches expected baseline target (${version_codename})."
    else
      warn "Ubuntu release mismatch: expected ${expected_version_id}, detected ${version_id:-unknown} (${version_codename}); this baseline is optimized for ${expected_os_label}."
    fi
  else
    fail_check "unsupported operating system (${pretty_name}); ${expected_os_label} is the expected platform."
  fi

  case "${arch_value}" in
    x86_64|amd64)
      ok "architecture is ${arch_value}."
      ;;
    *)
      warn "architecture is ${arch_value}; expected x86_64/amd64 for this baseline."
      ;;
  esac
}

check_ssh() {
  local actual
  section "SSH"

  if ! check_command sshd; then
    fail_check "sshd command is not available."
    return
  fi

  if sshd -t 2>/dev/null; then
    ok "sshd configuration validates."
  else
    fail_check "sshd -t failed."
  fi

  if actual="$(sshd_effective_value port)"; then
    if [[ "${actual}" == "${ssh_port}" ]]; then
      ok "effective SSH port is ${ssh_port}."
    else
      fail_check "effective SSH port is ${actual:-unknown}; expected ${ssh_port}."
    fi
  else
    fail_check "effective SSH port is unknown; expected ${ssh_port}."
  fi

  for pair in \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "permitemptypasswords no" \
    "permitrootlogin no" \
    "x11forwarding no" \
    "maxauthtries 3"; do
    local key
    local expected
    key="${pair%% *}"
    expected="${pair#* }"
    if actual="$(sshd_effective_value "${key}")"; then
      if [[ "${actual}" == "${expected}" ]]; then
        ok "effective ${key} is ${expected}."
      else
        fail_check "effective ${key} is ${actual:-unknown}; expected ${expected}."
      fi
    else
      fail_check "effective ${key} is unknown; expected ${expected}."
    fi
  done

  if check_command ss; then
    if ss -ltn | awk -v port=":${ssh_port}" '$4 ~ port "$" { found=1 } END { exit found ? 0 : 1 }'; then
      ok "SSH is listening on port ${ssh_port}."
    else
      fail_check "SSH is not listening on port ${ssh_port}."
    fi
  else
    warn "ss command is not available; cannot verify listening SSH port."
  fi
}

check_fail2ban() {
  section "Fail2ban"

  if ! check_command fail2ban-client; then
    fail_check "fail2ban-client is not available."
    return
  fi

  if systemctl is-enabled --quiet fail2ban 2>/dev/null; then
    ok "fail2ban service is enabled."
  else
    fail_check "fail2ban service is not enabled."
  fi

  if systemctl is-active --quiet fail2ban 2>/dev/null; then
    ok "fail2ban service is active."
  else
    fail_check "fail2ban service is not active."
  fi

  if fail2ban-client status sshd >/dev/null 2>&1; then
    ok "fail2ban sshd jail is active."
  else
    fail_check "fail2ban sshd jail is not active."
  fi

  # Runtime filenames retain the original family-infra profile name so already
  # configured hosts continue to verify without an invasive /etc migration.
  if [[ -r /etc/fail2ban/jail.d/family-infra-sshd.local ]] && grep -Eq "^[[:space:]]*port[[:space:]]*=[[:space:]]*${ssh_port}[[:space:]]*$" /etc/fail2ban/jail.d/family-infra-sshd.local; then
    ok "fail2ban sshd jail is configured for port ${ssh_port}."
  else
    fail_check "fail2ban sshd jail is not configured for port ${ssh_port}."
  fi
}

check_packages() {
  section "Packages"

  for package_name in "${baseline_packages[@]}"; do
    if dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q 'install ok installed'; then
      ok "package ${package_name} is installed."
    else
      fail_check "package ${package_name} is not installed."
    fi
  done

  if check_command dig; then
    ok "dig command is available."
  else
    fail_check "dig command is not available."
  fi
}

check_updates() {
  local apt_dump
  local automatic_reboot
  local periodic_unattended
  local periodic_update_lists
  local timer_name
  local unattended_file
  section "Automatic updates"

  unattended_file="/etc/apt/apt.conf.d/52family-infra-unattended-upgrades"
  apt_dump="$(apt-config dump 2>/dev/null || true)"

  if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q 'install ok installed'; then
    ok "unattended-upgrades is installed."
  else
    fail_check "unattended-upgrades is not installed."
  fi

  for timer_name in apt-daily.timer apt-daily-upgrade.timer; do
    if unit_file_exists "${timer_name}"; then
      ok "${timer_name} is available."
      if service_enabled "${timer_name}"; then
        ok "${timer_name} is enabled."
      else
        fail_check "${timer_name} is not enabled."
      fi
    else
      fail_check "${timer_name} is not available."
    fi
  done

  periodic_update_lists="$(awk -F'"' '/^APT::Periodic::Update-Package-Lists / { value=$2 } END { print value }' <<<"${apt_dump}")"
  periodic_unattended="$(awk -F'"' '/^APT::Periodic::Unattended-Upgrade / { value=$2 } END { print value }' <<<"${apt_dump}")"
  if [[ "${periodic_update_lists}" == "1" && "${periodic_unattended}" == "1" ]]; then
    ok "effective APT periodic unattended upgrades are enabled."
  else
    fail_check "effective APT periodic unattended upgrades are not enabled."
  fi

  automatic_reboot="$(awk -F'"' '/^Unattended-Upgrade::Automatic-Reboot / { value=$2 } END { print value }' <<<"${apt_dump}")"
  if [[ "${automatic_reboot}" == "false" ]]; then
    ok "effective unattended-upgrades automatic reboot is disabled."
  else
    fail_check "effective unattended-upgrades automatic reboot is ${automatic_reboot:-unset}; expected false."
  fi

  if grep -q 'Unattended-Upgrade::Allowed-Origins::.*\${distro_codename}-security' <<<"${apt_dump}"; then
    if [[ "${update_policy}" == "automatic" ]]; then
      if grep -q 'Unattended-Upgrade::Allowed-Origins::.*\${distro_codename}-updates' <<<"${apt_dump}"; then
        ok "effective update policy is automatic."
      else
        fail_check "effective update policy is not automatic; normal updates are missing."
      fi
    else
      if grep -q 'Unattended-Upgrade::Allowed-Origins::.*\${distro_codename}-updates' <<<"${apt_dump}"; then
        fail_check "effective update policy is not security-only; normal updates are enabled."
      else
        ok "effective update policy is security-only."
      fi
    fi
  else
    fail_check "security updates are not configured in effective unattended-upgrades origins."
  fi

  if [[ -r "${unattended_file}" ]]; then
    ok "host baseline unattended-upgrades drop-in exists."
  else
    fail_check "host baseline unattended-upgrades drop-in is missing."
  fi

  if [[ -e /var/run/reboot-required ]]; then
    warn "host reports reboot required."
  else
    ok "no reboot-required marker is present."
  fi
}

check_network() {
  section "Network"

  if check_command ip && ip -o link show up | awk -F': ' '$2 != "lo" { found=1 } END { exit found ? 0 : 1 }'; then
    ok "at least one non-loopback interface is up."
  else
    fail_check "no usable non-loopback interface is up."
  fi

  if check_command ip && ip route show default | grep -q '^default '; then
    ok "default route is present."
  else
    fail_check "default route is missing."
  fi

  if getent hosts github.com >/dev/null 2>&1; then
    ok "DNS resolution works for github.com."
  else
    fail_check "DNS resolution failed for github.com."
  fi
}

check_firewall() {
  section "Firewall"

  if ! check_command ufw; then
    ok "UFW is absent."
    return
  fi

  if ufw status 2>/dev/null | grep -qi '^Status: active'; then
    fail_check "UFW is active; this baseline expects UFW disabled for k3s host networking."
  else
    ok "UFW is inactive."
  fi
}

check_time() {
  local synced
  section "Time synchronization"

  if check_command chronyc || unit_file_exists chrony.service; then
    ok "chrony is installed or available."
    if systemctl is-active --quiet chrony.service 2>/dev/null; then
      ok "chrony service is active."

      if check_command chronyc && chronyc tracking >/dev/null 2>&1; then
        ok "chrony reports tracking status."
      else
        warn "chrony tracking status is not available."
      fi

      if check_command chronyc && chronyc waitsync 1 >/dev/null 2>&1; then
        ok "system clock is synchronized via chrony."
      else
        warn "chrony is active but synchronization is not confirmed yet."
      fi
      return
    else
      warn "chrony service is not active."
    fi
  fi

  if systemctl is-active --quiet systemd-timesyncd.service 2>/dev/null; then
    ok "systemd-timesyncd service is active."
  else
    warn "no active chrony or systemd-timesyncd service detected."
    return
  fi

  if check_command timedatectl; then
    synced="$(timedatectl show -p SystemClockSynchronized --value 2>/dev/null || true)"
    if [[ "${synced}" == "yes" ]]; then
      ok "system clock is synchronized."
    else
      warn "system clock synchronization is ${synced:-unknown}."
    fi
  else
    warn "timedatectl is not available; cannot verify system clock synchronization."
  fi
}

check_security() {
  section "Security"

  if [[ -d /sys/kernel/security/apparmor ]]; then
    if [[ -r /sys/module/apparmor/parameters/enabled ]] && grep -qi '^Y' /sys/module/apparmor/parameters/enabled; then
      ok "AppArmor is available and enabled."
    else
      warn "AppArmor is available but not clearly enabled."
    fi
  else
    warn "AppArmor status is not available from /sys/kernel/security/apparmor."
  fi
}

check_k3s_prerequisites() {
  section "k3s host prerequisites"

  if check_command curl; then
    ok "curl is available for the k3s installer wrapper."
  else
    fail_check "curl is missing."
  fi

  if check_command ss; then
    ok "ss is available for k3s verification."
  else
    warn "ss is not available; k3s verification can still run with reduced port output."
  fi

  ok "host baseline does not configure static IP, Netplan, pod CIDR, service CIDR, or Kubernetes firewall rules."
}

main() {
  parse_args "$@"
  validate_inputs

  if [[ "${os_only}" == true ]]; then
    check_operating_system
    section "Summary"
    echo "OK: ${ok_count}"
    echo "WARN: ${warn_count}"
    echo "FAIL: ${fail_count}"
    if [[ "${fail_count}" -gt 0 ]]; then
      exit 1
    fi
    exit 0
  fi

  check_host_identity
  check_operating_system
  check_ssh
  check_fail2ban
  check_packages
  check_updates
  check_network
  check_firewall
  check_time
  check_security
  check_k3s_prerequisites

  section "Summary"
  echo "OK: ${ok_count}"
  echo "WARN: ${warn_count}"
  echo "FAIL: ${fail_count}"

  if [[ "${fail_count}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
