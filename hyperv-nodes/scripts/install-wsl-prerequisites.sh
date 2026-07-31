#!/usr/bin/env bash
set -euo pipefail

OPENTOFU_VERSION="${OPENTOFU_VERSION:-1.12.5}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-wsl-prerequisites.sh

Installs the ISO build dependencies and an exact OpenTofu version from the
official OpenTofu APT repository on Ubuntu/Debian WSL.

Optional environment variable:
  OPENTOFU_VERSION  Exact version to install (default: 1.12.5)
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if (($# != 0)); then
  usage >&2
  exit 1
fi

if [[ ! "${OPENTOFU_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "OPENTOFU_VERSION must be an exact stable version such as 1.12.5" >&2
  exit 1
fi
if [[ "$(uname -s)" != "Linux" ]] ||
  ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "This installer must be run inside Ubuntu/Debian WSL." >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the Linux distribution: /etc/os-release is missing" >&2
  exit 1
fi

# /etc/os-release is a system-owned shell-compatible data file.
# shellcheck disable=SC1091
source /etc/os-release
distribution_family="${ID:-} ${ID_LIKE:-}"
if [[ ! "${distribution_family}" =~ (ubuntu|debian) ]]; then
  echo "Only Ubuntu/Debian WSL is supported; detected ID=${ID:-unknown}" >&2
  exit 1
fi

if ((EUID == 0)); then
  sudo_command=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when the script is not run as root" >&2
    exit 1
  fi
  sudo_command=(sudo)
fi

run_as_root() {
  "${sudo_command[@]}" "$@"
}

echo "Installing WSL prerequisites..."
run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update
run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apt-transport-https \
  ca-certificates \
  coreutils \
  curl \
  gettext-base \
  gnupg \
  netcat-openbsd \
  openssh-client \
  openssl \
  python3 \
  xorriso

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "${temporary_directory}"' EXIT

curl --fail --silent --show-error --location \
  --proto '=https' \
  --tlsv1.2 \
  --output "${temporary_directory}/opentofu.gpg" \
  https://get.opentofu.org/opentofu.gpg
curl --fail --silent --show-error --location \
  --proto '=https' \
  --tlsv1.2 \
  --output "${temporary_directory}/opentofu-repo.asc" \
  https://packages.opentofu.org/opentofu/tofu/gpgkey
gpg --no-tty --batch --dearmor \
  --output "${temporary_directory}/opentofu-repo.gpg" \
  "${temporary_directory}/opentofu-repo.asc"

run_as_root install -m 0755 -d /etc/apt/keyrings
run_as_root install -m 0644 \
  "${temporary_directory}/opentofu.gpg" \
  /etc/apt/keyrings/opentofu.gpg
run_as_root install -m 0644 \
  "${temporary_directory}/opentofu-repo.gpg" \
  /etc/apt/keyrings/opentofu-repo.gpg

printf '%s\n' \
  'deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main' \
  'deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main' |
  run_as_root tee /etc/apt/sources.list.d/opentofu.list >/dev/null

printf 'Package: tofu\nPin: version %s\nPin-Priority: 1001\n' \
  "${OPENTOFU_VERSION}" |
  run_as_root tee /etc/apt/preferences.d/opentofu >/dev/null

run_as_root chmod 0644 \
  /etc/apt/sources.list.d/opentofu.list \
  /etc/apt/preferences.d/opentofu
run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update

if ! apt-cache madison tofu |
  awk '{print $3}' |
  grep -Fx -- "${OPENTOFU_VERSION}" >/dev/null; then
  echo "OpenTofu ${OPENTOFU_VERSION} is not available from the configured repository." >&2
  echo "Available stable versions:" >&2
  apt-cache madison tofu |
    awk '{print $3}' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -Vu |
    tail -10 >&2
  exit 1
fi

run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  "tofu=${OPENTOFU_VERSION}"

installed_version="$(
  tofu version |
    sed -n '1s/^OpenTofu v//p'
)"
if [[ "${installed_version}" != "${OPENTOFU_VERSION}" ]]; then
  echo "Expected OpenTofu ${OPENTOFU_VERSION}, installed ${installed_version:-unknown}" >&2
  exit 1
fi

echo "OpenTofu ${installed_version} and all ISO build prerequisites are installed."
echo "Next: ./scripts/configure-deployment.sh"
