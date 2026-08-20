#!/usr/bin/env bash
set -euo pipefail

default_hostname="family-infra-01"
default_admin_user="${SUDO_USER:-${USER:-}}"
default_ssh_port="50022"
default_update_policy="automatic"
expected_os_id="ubuntu"
expected_version_id="26.04"
expected_os_label="Ubuntu Server 26.04 LTS"
os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"

hostname_value="${default_hostname}"
admin_user="${default_admin_user}"
ssh_port="${default_ssh_port}"
update_policy="${default_update_policy}"
dry_run=false

baseline_packages=(
  git
  curl
  ca-certificates
  jq
  dnsutils
  vim
  htop
  fail2ban
  unattended-upgrades
  openssh-server
)

usage() {
  cat <<'USAGE'
Usage: apply-host-baseline.sh [options]

Apply the family-infra host OS baseline for family-infra-01.

Options:
  --hostname <hostname>              Expected host name. Default: family-infra-01
  --admin-user <user>                Existing admin user with SSH authorized_keys.
                                     Default: invoking sudo user when available.
  --ssh-port <port>                  SSH port to configure. Default: 50022
  --update-policy <automatic|security-only>
                                     Ubuntu unattended-upgrades policy. Default: automatic
  --dry-run                          Show planned changes without applying them.
  -h, --help                         Show this help.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "INFO: $*"
}

is_integer_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

detect_os() {
  if [[ ! -r "${os_release_file}" ]]; then
    fail "Cannot read ${os_release_file}; ${expected_os_label} is the expected platform."
  fi

  (
    # shellcheck disable=SC1090
    . "${os_release_file}"
    printf '%s\n' "${ID:-}" "${VERSION_ID:-}" "${VERSION_CODENAME:-}" "${PRETTY_NAME:-}"
  )
}

check_operating_system() {
  local os_id
  local version_id
  local version_codename
  local pretty_name

  mapfile -t os_info < <(detect_os)
  os_id="${os_info[0]:-}"
  version_id="${os_info[1]:-}"
  version_codename="${os_info[2]:-unknown}"
  pretty_name="${os_info[3]:-unknown}"

  if [[ "${os_id}" != "${expected_os_id}" ]]; then
    fail "Unsupported operating system (${pretty_name}); ${expected_os_label} is the expected platform."
  fi

  if [[ "${version_id}" == "${expected_version_id}" ]]; then
    echo "OK: Ubuntu ${expected_version_id} LTS detected (${version_codename})."
  else
    echo "WARN: this baseline is optimized for ${expected_os_label}; detected Ubuntu ${version_id:-unknown} (${version_codename})."
  fi
}

require_root_for_apply() {
  if [[ "${dry_run}" == false && "${EUID}" -ne 0 ]]; then
    fail "Run this script as root, for example with sudo."
  fi
}

run_or_print() {
  if [[ "${dry_run}" == true ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

install_text_file() {
  local target="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"
  local content="$5"
  local target_dir
  local tmp

  target_dir="$(dirname -- "${target}")"

  if [[ "${dry_run}" == true ]]; then
    if [[ -f "${target}" ]] && cmp -s <(printf '%s' "${content}") "${target}"; then
      echo "DRY-RUN: ${target} already matches desired content."
    else
      echo "DRY-RUN: would install ${target} with mode ${mode}."
    fi
    return 0
  fi

  install -d -m 0755 "${target_dir}"
  tmp="$(mktemp "${target_dir}/.tmp.XXXXXX")"
  printf '%s' "${content}" > "${tmp}"
  chown "${owner}:${group}" "${tmp}"
  chmod "${mode}" "${tmp}"

  if [[ -f "${target}" ]] && cmp -s "${tmp}" "${target}"; then
    rm -f "${tmp}"
    info "${target} already matches desired content."
  else
    mv "${tmp}" "${target}"
    info "Installed ${target}."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)
        [[ $# -ge 2 ]] || fail "--hostname requires a value."
        hostname_value="$2"
        shift 2
        ;;
      --admin-user)
        [[ $# -ge 2 ]] || fail "--admin-user requires a value."
        admin_user="$2"
        shift 2
        ;;
      --ssh-port)
        [[ $# -ge 2 ]] || fail "--ssh-port requires a value."
        ssh_port="$2"
        shift 2
        ;;
      --update-policy)
        [[ $# -ge 2 ]] || fail "--update-policy requires a value."
        update_policy="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

validate_inputs() {
  [[ -n "${hostname_value}" ]] || fail "hostname must not be empty."
  [[ -n "${admin_user}" ]] || fail "--admin-user is required when it cannot be inferred from sudo."
  is_integer_port "${ssh_port}" || fail "--ssh-port must be an integer from 1 to 65535."

  case "${update_policy}" in
    automatic|security-only)
      ;;
    *)
      fail "--update-policy must be automatic or security-only."
      ;;
  esac
}

validate_admin_ssh_access() {
  local user_home
  local ssh_dir
  local authorized_keys
  local key_count
  local ssh_dir_mode
  local authorized_keys_mode

  getent passwd "${admin_user}" >/dev/null || fail "Admin user does not exist: ${admin_user}"
  user_home="$(getent passwd "${admin_user}" | cut -d: -f6)"
  [[ -n "${user_home}" && -d "${user_home}" ]] || fail "Admin user home directory is missing: ${admin_user}"

  ssh_dir="${user_home}/.ssh"
  authorized_keys="${ssh_dir}/authorized_keys"
  [[ -d "${ssh_dir}" ]] || fail "Missing ${ssh_dir}; refusing to apply restrictive SSH config."
  [[ -f "${authorized_keys}" ]] || fail "Missing ${authorized_keys}; refusing to apply restrictive SSH config."

  key_count="$(grep -Ec '^[[:space:]]*[^#[:space:]]' "${authorized_keys}" || true)"
  [[ "${key_count}" -gt 0 ]] || fail "${authorized_keys} has no non-empty public key entries."

  ssh_dir_mode="$(stat -c '%a' "${ssh_dir}")"
  authorized_keys_mode="$(stat -c '%a' "${authorized_keys}")"
  [[ "${ssh_dir_mode}" == "700" ]] || fail "${ssh_dir} permissions are ${ssh_dir_mode}; expected 0700."
  [[ "${authorized_keys_mode}" == "600" ]] || fail "${authorized_keys} permissions are ${authorized_keys_mode}; expected 0600."

  info "Admin SSH key preflight passed for ${admin_user}; authorized_keys has ${key_count} non-empty entry or entries."
}

configure_hostname() {
  if [[ "$(hostname)" == "${hostname_value}" ]]; then
    info "Hostname already set to ${hostname_value}."
  else
    run_or_print hostnamectl set-hostname "${hostname_value}"
  fi
}

install_packages_and_updates() {
  run_or_print apt-get update
  run_or_print apt-get install -y "${baseline_packages[@]}"
  run_or_print apt-get upgrade -y
}

service_active_or_enabled() {
  local service_name="$1"
  systemctl is-active --quiet "${service_name}" 2>/dev/null || systemctl is-enabled --quiet "${service_name}" 2>/dev/null
}

unit_file_exists() {
  local service_name="$1"
  systemctl list-unit-files "${service_name}" --no-legend 2>/dev/null | awk -v service_name="${service_name}" '$1 == service_name { found=1 } END { exit found ? 0 : 1 }'
}

configure_time_sync() {
  if command -v chronyc >/dev/null 2>&1 || unit_file_exists chrony.service; then
    info "Chrony is available; ensuring chrony.service is enabled and active."
    run_or_print systemctl enable --now chrony.service
    return 0
  fi

  if service_active_or_enabled systemd-timesyncd.service; then
    info "systemd-timesyncd is available; leaving existing time synchronization mechanism in place."
    return 0
  fi

  info "No adequate time synchronization service detected; installing Chrony for ${expected_os_label}."
  if [[ "${dry_run}" == true ]]; then
    echo "DRY-RUN: would install chrony and enable chrony.service."
  else
    apt-get install -y chrony
    systemctl enable --now chrony.service
  fi
}

configure_ssh() {
  local sshd_dropin
  local socket_dropin
  local sshd_content
  local socket_content

  sshd_dropin="/etc/ssh/sshd_config.d/20-family-infra-baseline.conf"
  socket_dropin="/etc/systemd/system/ssh.socket.d/20-family-infra-baseline.conf"

  sshd_content="$(cat <<EOF
# Managed by sovereignworkplaceservice family-infra host baseline.
Port ${ssh_port}
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
X11Forwarding no
MaxAuthTries 3
EOF
)"

  socket_content="$(cat <<EOF
# Managed by sovereignworkplaceservice family-infra host baseline.
[Socket]
ListenStream=
ListenStream=${ssh_port}
EOF
)"

  install_text_file "${sshd_dropin}" "0644" "root" "root" "${sshd_content}"$'\n'
  install_text_file "${socket_dropin}" "0644" "root" "root" "${socket_content}"$'\n'

  if [[ "${dry_run}" == true ]]; then
    echo "DRY-RUN: would validate SSH configuration with sshd -t."
    echo "DRY-RUN: would reload ssh.service when active and restart ssh.socket when active."
    return 0
  fi

  sshd -t
  systemctl daemon-reload

  if systemctl is-active --quiet ssh.service; then
    systemctl reload ssh.service || systemctl restart ssh.service
  fi

  if systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket; then
    systemctl restart ssh.socket
  fi

  info "SSH baseline applied. Keep the current session open and test a new session on port ${ssh_port}."
}

configure_fail2ban() {
  local jail_file
  local jail_content

  jail_file="/etc/fail2ban/jail.d/family-infra-sshd.local"
  jail_content="$(cat <<EOF
# Managed by sovereignworkplaceservice family-infra host baseline.
[sshd]
enabled = true
port = ${ssh_port}
filter = sshd
backend = systemd
maxretry = 3
findtime = 30m
bantime = 12h
EOF
)"

  install_text_file "${jail_file}" "0644" "root" "root" "${jail_content}"$'\n'

  if [[ "${dry_run}" == true ]]; then
    echo "DRY-RUN: would enable and restart fail2ban."
    echo "DRY-RUN: would verify fail2ban configuration."
    return 0
  fi

  fail2ban-client -t
  systemctl enable --now fail2ban
  systemctl restart fail2ban
}

configure_unattended_upgrades() {
  local periodic_file
  local unattended_file
  local allowed_origins

  periodic_file="/etc/apt/apt.conf.d/51family-infra-auto-upgrades"
  unattended_file="/etc/apt/apt.conf.d/52family-infra-unattended-upgrades"

  if [[ "${update_policy}" == "automatic" ]]; then
    allowed_origins='        "${distro_id}:${distro_codename}-security";
        "${distro_id}:${distro_codename}-updates";'
  else
    allowed_origins='        "${distro_id}:${distro_codename}-security";'
  fi

  install_text_file "${periodic_file}" "0644" "root" "root" "$(cat <<'EOF'
// Managed by sovereignworkplaceservice family-infra host baseline.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
)"$'\n'

  install_text_file "${unattended_file}" "0644" "root" "root" "$(cat <<EOF
// Managed by sovereignworkplaceservice family-infra host baseline.
Unattended-Upgrade::Allowed-Origins {
${allowed_origins}
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";
Unattended-Upgrade::Remove-New-Unused-Dependencies "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
EOF
)"$'\n'

  if [[ "${dry_run}" == true ]]; then
    echo "DRY-RUN: would enable apt-daily.timer and apt-daily-upgrade.timer when systemd is available."
    return 0
  fi

  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    info "UFW is not installed."
    return 0
  fi

  if ufw status | grep -qi '^Status: active'; then
    info "UFW is active; disabling it for the k3s host baseline."
    run_or_print ufw --force disable
  else
    info "UFW is installed and inactive."
  fi
}

show_network_and_time_status() {
  info "Network baseline does not configure static IP, Netplan, interface names, VLANs, or Synology switch details."
  if command -v ip >/dev/null 2>&1; then
    ip -brief address show up scope global || true
    ip route show default || true
  fi
  if command -v chronyc >/dev/null 2>&1; then
    chronyc tracking 2>/dev/null | awk -F': ' '/^Reference ID|^Leap status|^System time/ { print $1 ": " $2 }' || true
  fi
  timedatectl show -p SystemClockSynchronized -p Timezone 2>/dev/null || true
}

main() {
  parse_args "$@"
  validate_inputs
  require_root_for_apply

  echo "family-infra host baseline"
  echo "hostname=${hostname_value}"
  echo "admin_user=${admin_user}"
  echo "ssh_port=${ssh_port}"
  echo "update_policy=${update_policy}"
  echo "automatic_reboot=false"
  echo "dry_run=${dry_run}"

  check_operating_system
  validate_admin_ssh_access
  configure_hostname
  install_packages_and_updates
  configure_time_sync
  configure_ssh
  configure_fail2ban
  configure_unattended_upgrades
  configure_firewall
  show_network_and_time_status

  echo "Host baseline apply completed."
}

main "$@"
