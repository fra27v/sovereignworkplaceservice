#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/check-host-baseline-tools.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this script as root because it installs apt packages." >&2
  exit 1
fi

echo "Installing apt-managed operator-plane baseline tools."
echo "apache2-utils is included because it provides htpasswd."
echo "This script does not install or upgrade Helm."
echo "This script does not install or manage k3s or kubectl."

apt-get update
apt-get install -y jq openssl curl git apache2-utils

echo "Running host baseline tool check after apt installation."
"${check_script}"
