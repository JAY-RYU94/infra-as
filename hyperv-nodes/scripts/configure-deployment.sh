#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

NON_INTERACTIVE=false
FORCE=false
OUTPUT_DIR="${MODULE_DIR}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/configure-deployment.sh [options]

Creates a sourceable hyperv.env, secret input files, and terraform.tfvars.
WinRM and Ubuntu passwords are never written to hyperv.env or terraform.tfvars.

Options:
  --non-interactive    Read all values from environment variables
  --force              Replace existing hyperv.env and terraform.tfvars
  --output-dir PATH    Write configuration files to PATH
  -h, --help           Show this help

For non-interactive use, set at least:
  HYPERV_HOST HYPERV_USERNAME VM_HOSTNAME VM_MAC_ADDRESS VM_ADDRESS_CIDR
  VM_GATEWAY VM_DNS_SERVERS VM_DNS_SEARCH K3S_TLS_SAN
  TF_VAR_virtual_switch_name INSTALL_DISK_WIPE_CONFIRMATION

The asoladmin password file and SSH public key must already exist in
non-interactive mode. A missing k3s token is generated automatically.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --output-dir)
      if (($# < 2)); then
        echo "--output-dir requires a path" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]] ||
  ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "This configurator must be run inside WSL." >&2
  exit 1
fi

required_commands=(openssl python3 realpath ssh-keygen)
for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command is missing: ${command_name}" >&2
    echo "Run ./scripts/install-wsl-prerequisites.sh first." >&2
    exit 1
  fi
done

mkdir -p -- "${OUTPUT_DIR}"
OUTPUT_DIR="$(realpath -m "${OUTPUT_DIR}")"
HYPERV_ENV_PATH="${OUTPUT_DIR}/hyperv.env"
TFVARS_PATH="${OUTPUT_DIR}/terraform.tfvars"

if [[ "${FORCE}" != "true" ]]; then
  for output_path in "${HYPERV_ENV_PATH}" "${TFVARS_PATH}"; do
    if [[ -e "${output_path}" ]]; then
      echo "Refusing to replace existing file: ${output_path}" >&2
      echo "Review it, then rerun with --force if replacement is intended." >&2
      exit 1
    fi
  done
fi

prompt_value() {
  local variable_name="$1"
  local label="$2"
  local default_value="$3"
  local required="$4"
  local current_value="${!variable_name:-${default_value}}"
  local entered_value=""

  if [[ "${NON_INTERACTIVE}" != "true" ]]; then
    if [[ -n "${current_value}" ]]; then
      read -r -p "${label} [${current_value}]: " entered_value
    else
      read -r -p "${label}: " entered_value
    fi
    if [[ -n "${entered_value}" ]]; then
      current_value="${entered_value}"
    fi
  fi

  if [[ "${required}" == "true" && -z "${current_value}" ]]; then
    echo "A value is required for ${variable_name}" >&2
    exit 1
  fi
  if [[ "${current_value}" == *$'\n'* || "${current_value}" == *$'\r'* ]]; then
    echo "${variable_name} must be a single-line value" >&2
    exit 1
  fi
  printf -v "${variable_name}" '%s' "${current_value}"
}

prompt_value HYPERV_HOST "Hyper-V WinRM FQDN" "" true
prompt_value HYPERV_PORT "WinRM HTTPS port" "5986" true
prompt_value HYPERV_USERNAME "WinRM account (DOMAIN\\\\user or HOST\\\\user)" "" true
prompt_value HYPERV_WINRM_CACERT "Internal CA PEM path (blank for system trust)" "" false
prompt_value VM_HOSTNAME "VM hostname" "asol-k3s-01" true
prompt_value VM_MAC_ADDRESS "Unique static Hyper-V MAC" "" true
prompt_value VM_ADDRESS_CIDR "VM static IPv4 CIDR" "" true
prompt_value VM_GATEWAY "VM IPv4 gateway" "" true
prompt_value VM_DNS_SERVERS "Comma-separated DNS IPv4 addresses" "" true
prompt_value VM_DNS_SEARCH "DNS search domain" "" true
prompt_value K3S_TLS_SAN "k3s API DNS name or IPv4 SAN" "" true
TF_VAR_virtual_switch_name="${TF_VAR_virtual_switch_name:-External}"
prompt_value TF_VAR_virtual_switch_name "Existing External vSwitch name" "External" true

prompt_value VHD_SIZE_GIB "Dynamic VHDX maximum size (GiB)" "1024" true
prompt_value PROCESSOR_COUNT "VM virtual processor count" "8" true
prompt_value MEMORY_GIB "VM fixed memory (GiB)" "32" true
prompt_value INSTALL_ISO_HOST_PATH \
  "Installer ISO path on Hyper-V" \
  "C:/Hyper-V/ASOL/ISO/asol-k3s-ubuntu-24.04.4-autoinstall.iso" \
  true
prompt_value VHD_PATH \
  "VHDX path on Hyper-V" \
  "C:/Hyper-V/ASOL/VHDX/${VM_HOSTNAME}.vhdx" \
  true

ASOL_SECRETS_DIR="${ASOL_SECRETS_DIR:-${HOME}/.config/asol-infra/secrets}"
ASOL_ARTIFACT_DIR="${ASOL_ARTIFACT_DIR:-${HOME}/.local/share/asol-infra/artifacts}"
ASOLADMIN_PASSWORD_FILE="${ASOLADMIN_PASSWORD_FILE:-${ASOL_SECRETS_DIR}/asoladmin-initial-password}"
ASOLADMIN_SSH_PUBLIC_KEY_FILE="${ASOLADMIN_SSH_PUBLIC_KEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
K3S_TOKEN_FILE="${K3S_TOKEN_FILE:-${ASOL_SECRETS_DIR}/k3s-cluster-token}"
OUTPUT_ISO="${OUTPUT_ISO:-${ASOL_ARTIFACT_DIR}/asol-k3s-ubuntu-24.04.4-autoinstall.iso}"

ASOL_SECRETS_DIR="$(realpath -m "${ASOL_SECRETS_DIR}")"
ASOL_ARTIFACT_DIR="$(realpath -m "${ASOL_ARTIFACT_DIR}")"
ASOLADMIN_PASSWORD_FILE="$(realpath -m "${ASOLADMIN_PASSWORD_FILE}")"
ASOLADMIN_SSH_PUBLIC_KEY_FILE="$(realpath -m "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}")"
K3S_TOKEN_FILE="$(realpath -m "${K3S_TOKEN_FILE}")"
OUTPUT_ISO="$(realpath -m "${OUTPUT_ISO}")"

case "${ASOL_ARTIFACT_DIR}" in
  /mnt/[A-Za-z] | /mnt/[A-Za-z]/*)
    echo "ASOL_ARTIFACT_DIR must be on the WSL Linux filesystem, not /mnt/<drive>." >&2
    exit 1
    ;;
esac
case "${OUTPUT_ISO}" in
  "${ASOL_ARTIFACT_DIR}"/*) ;;
  *)
    echo "OUTPUT_ISO must be inside ASOL_ARTIFACT_DIR" >&2
    exit 1
    ;;
esac

if [[ ! "${HYPERV_PORT}" =~ ^[0-9]+$ ]] ||
  ((10#${HYPERV_PORT} < 1 || 10#${HYPERV_PORT} > 65535)); then
  echo "HYPERV_PORT must be an integer from 1 to 65535" >&2
  exit 1
fi
if [[ "${HYPERV_HOST}" =~ [[:space:]] ]]; then
  echo "HYPERV_HOST must not contain whitespace" >&2
  exit 1
fi
if [[ ! "${VM_HOSTNAME}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  echo "VM_HOSTNAME must be a lowercase DNS label of at most 63 characters" >&2
  exit 1
fi
if [[ ! "${VM_MAC_ADDRESS}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
  echo "VM_MAC_ADDRESS must have the form 00:15:5D:01:02:03" >&2
  exit 1
fi
if [[ ! "${VHD_SIZE_GIB}" =~ ^[0-9]+$ ]] || ((10#${VHD_SIZE_GIB} < 200)); then
  echo "VHD_SIZE_GIB must be an integer of at least 200" >&2
  exit 1
fi
if [[ ! "${PROCESSOR_COUNT}" =~ ^[0-9]+$ ]] || ((10#${PROCESSOR_COUNT} < 4)); then
  echo "PROCESSOR_COUNT must be an integer of at least 4" >&2
  exit 1
fi
if [[ ! "${MEMORY_GIB}" =~ ^[0-9]+$ ]] || ((10#${MEMORY_GIB} < 16)); then
  echo "MEMORY_GIB must be an integer of at least 16" >&2
  exit 1
fi
if [[ ! "${INSTALL_ISO_HOST_PATH}" =~ ^[A-Za-z]:/ ]] ||
  [[ ! "${VHD_PATH}" =~ ^[A-Za-z]:/ ]]; then
  echo "Hyper-V ISO and VHDX paths must use forward-slash absolute paths such as C:/Hyper-V/..." >&2
  exit 1
fi
if [[ -n "${HYPERV_WINRM_CACERT}" && ! -r "${HYPERV_WINRM_CACERT}" ]]; then
  echo "The internal CA certificate is not readable: ${HYPERV_WINRM_CACERT}" >&2
  exit 1
fi

export VM_ADDRESS_CIDR VM_GATEWAY VM_DNS_SERVERS VM_DNS_SEARCH K3S_TLS_SAN
python3 - <<'PY'
import ipaddress
import os
import re


def dns_name(value: str, variable: str) -> None:
    if len(value) > 253 or value.endswith("."):
        raise SystemExit(f"{variable} must be a DNS name without a trailing dot")
    pattern = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
    labels = value.split(".")
    if not labels or any(not pattern.fullmatch(label) for label in labels):
        raise SystemExit(f"{variable} contains an invalid DNS label")


interface = ipaddress.ip_interface(os.environ["VM_ADDRESS_CIDR"])
if interface.version != 4:
    raise SystemExit("VM_ADDRESS_CIDR must be IPv4")
gateway = ipaddress.ip_address(os.environ["VM_GATEWAY"])
if gateway.version != 4 or gateway not in interface.network:
    raise SystemExit("VM_GATEWAY must be IPv4 in the VM_ADDRESS_CIDR subnet")
if gateway in (interface.network.network_address, interface.network.broadcast_address):
    raise SystemExit("VM_GATEWAY cannot be the network or broadcast address")

dns_values = os.environ["VM_DNS_SERVERS"].split(",")
if not dns_values or any(not value or value != value.strip() for value in dns_values):
    raise SystemExit("VM_DNS_SERVERS must be comma-separated without spaces")
for value in dns_values:
    if ipaddress.ip_address(value).version != 4:
        raise SystemExit("VM_DNS_SERVERS entries must be IPv4")

dns_name(os.environ["VM_DNS_SEARCH"], "VM_DNS_SEARCH")
try:
    ipaddress.ip_address(os.environ["K3S_TLS_SAN"])
except ValueError:
    dns_name(os.environ["K3S_TLS_SAN"], "K3S_TLS_SAN")
PY

install -d -m 0700 -- "${ASOL_SECRETS_DIR}" "${ASOL_ARTIFACT_DIR}"

if [[ ! -s "${ASOLADMIN_PASSWORD_FILE}" ]]; then
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    echo "Create a non-empty mode-0600 password file first: ${ASOLADMIN_PASSWORD_FILE}" >&2
    exit 1
  fi
  read -rsp 'asoladmin initial password: ' initial_password
  printf '\n'
  read -rsp 'confirm asoladmin initial password: ' initial_password_confirmation
  printf '\n'
  if [[ -z "${initial_password}" || "${initial_password}" != "${initial_password_confirmation}" ]]; then
    unset initial_password initial_password_confirmation
    echo "The initial password is empty or the confirmation does not match" >&2
    exit 1
  fi
  printf '%s' "${initial_password}" >"${ASOLADMIN_PASSWORD_FILE}"
  unset initial_password initial_password_confirmation
fi
chmod 0600 "${ASOLADMIN_PASSWORD_FILE}"

if [[ ! -s "${K3S_TOKEN_FILE}" ]]; then
  openssl rand -hex 32 >"${K3S_TOKEN_FILE}"
fi
chmod 0600 "${K3S_TOKEN_FILE}"

if [[ ! -s "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" ]]; then
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    echo "Create an SSH public key first: ${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" >&2
    exit 1
  fi
  if [[ "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" != *.pub ]]; then
    echo "ASOLADMIN_SSH_PUBLIC_KEY_FILE must end in .pub" >&2
    exit 1
  fi
  install -d -m 0700 -- "$(dirname -- "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}")"
  ssh-keygen -t ed25519 -a 100 \
    -f "${ASOLADMIN_SSH_PUBLIC_KEY_FILE%.pub}"
fi

if [[ "${NON_INTERACTIVE}" == "true" ]]; then
  if [[ "${INSTALL_DISK_WIPE_CONFIRMATION:-}" != "${VM_HOSTNAME}" ]]; then
    echo "INSTALL_DISK_WIPE_CONFIRMATION must exactly match VM_HOSTNAME" >&2
    exit 1
  fi
else
  printf '\nTarget summary:\n'
  printf '  Hyper-V host: %s:%s\n' "${HYPERV_HOST}" "${HYPERV_PORT}"
  printf '  VM:           %s (%s, %s)\n' \
    "${VM_HOSTNAME}" "${VM_MAC_ADDRESS}" "${VM_ADDRESS_CIDR}"
  printf '  VHDX:         %s (%s GiB)\n' "${VHD_PATH}" "${VHD_SIZE_GIB}"
  printf '\nThe unattended installer will erase the new VM disk.\n'
  read -r -p "Type ${VM_HOSTNAME} to create the destructive-install confirmation: " \
    INSTALL_DISK_WIPE_CONFIRMATION
  if [[ "${INSTALL_DISK_WIPE_CONFIRMATION}" != "${VM_HOSTNAME}" ]]; then
    echo "Confirmation did not match; no configuration files were written." >&2
    exit 1
  fi
fi

temporary_directory="$(mktemp -d "${OUTPUT_DIR}/.configure.XXXXXXXX")"
trap 'rm -rf -- "${temporary_directory}"' EXIT
temporary_env="${temporary_directory}/hyperv.env"
temporary_tfvars="${temporary_directory}/terraform.tfvars"

write_export() {
  local variable_name="$1"
  local variable_value="$2"
  printf 'export %s=' "${variable_name}" >>"${temporary_env}"
  printf '%q\n' "${variable_value}" >>"${temporary_env}"
}

printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Generated by scripts/configure-deployment.sh. This file is ignored by Git.' \
  '# Run: source ./hyperv.env' \
  >"${temporary_env}"
write_export HYPERV_BACKEND "winrm"
write_export HYPERV_HOST "${HYPERV_HOST}"
write_export HYPERV_PORT "${HYPERV_PORT}"
write_export HYPERV_USERNAME "${HYPERV_USERNAME}"
write_export HYPERV_WINRM_USE_HTTPS "true"
write_export HYPERV_WINRM_AUTH "ntlm"
write_export HYPERV_TIMEOUT "30m"
write_export HYPERV_WINRM_CACERT "${HYPERV_WINRM_CACERT}"
write_export HYPERV_WINRM_INSECURE "false"
# The parameter expansion is intentionally written verbatim to hyperv.env.
# shellcheck disable=SC2016
printf '%s\n' \
  'if [[ -z "${HYPERV_PASSWORD:-}" ]]; then' \
  "  read -rsp 'Hyper-V WinRM password: ' HYPERV_PASSWORD" \
  "  printf '\\n'" \
  '  export HYPERV_PASSWORD' \
  'fi' \
  >>"${temporary_env}"
write_export ASOLADMIN_PASSWORD_FILE "${ASOLADMIN_PASSWORD_FILE}"
write_export ASOLADMIN_SSH_PUBLIC_KEY_FILE "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}"
write_export K3S_TOKEN_FILE "${K3S_TOKEN_FILE}"
write_export ASOL_ARTIFACT_DIR "${ASOL_ARTIFACT_DIR}"
write_export OUTPUT_ISO "${OUTPUT_ISO}"
write_export VM_HOSTNAME "${VM_HOSTNAME}"
write_export VM_MAC_ADDRESS "${VM_MAC_ADDRESS}"
write_export VM_ADDRESS_CIDR "${VM_ADDRESS_CIDR}"
write_export VM_GATEWAY "${VM_GATEWAY}"
write_export VM_DNS_SERVERS "${VM_DNS_SERVERS}"
write_export VM_DNS_SEARCH "${VM_DNS_SEARCH}"
write_export K3S_TLS_SAN "${K3S_TLS_SAN}"
write_export TF_VAR_vm_name "${VM_HOSTNAME}"
write_export TF_VAR_vm_mac_address "${VM_MAC_ADDRESS}"
write_export TF_VAR_vm_address_cidr "${VM_ADDRESS_CIDR}"
write_export TF_VAR_virtual_switch_name "${TF_VAR_virtual_switch_name}"
write_export TF_VAR_install_iso_local_path "${OUTPUT_ISO}"

hcl_quote() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

{
  printf 'installation_phase             = "install"\n'
  printf 'installer_iso_present          = true\n'
  printf 'installer_cleanup_confirmation = ""\n'
  printf 'install_disk_wipe_confirmation = %s\n\n' \
    "$(hcl_quote "${INSTALL_DISK_WIPE_CONFIRMATION}")"
  printf 'install_iso_host_path = %s\n\n' "$(hcl_quote "${INSTALL_ISO_HOST_PATH}")"
  printf 'vhd_path        = %s\n' "$(hcl_quote "${VHD_PATH}")"
  printf 'vhd_size_gib    = %s\n' "${VHD_SIZE_GIB}"
  printf 'processor_count = %s\n' "${PROCESSOR_COUNT}"
  printf 'memory_gib      = %s\n' "${MEMORY_GIB}"
} >"${temporary_tfvars}"

bash -n "${temporary_env}"
install -m 0600 "${temporary_env}" "${HYPERV_ENV_PATH}"
install -m 0600 "${temporary_tfvars}" "${TFVARS_PATH}"

echo
echo "Created ${HYPERV_ENV_PATH}"
echo "Created ${TFVARS_PATH}"
echo "Secret inputs are under ${ASOL_SECRETS_DIR}"
echo
echo "Next commands:"
printf '  cd %q\n' "${OUTPUT_DIR}"
echo "  source ./hyperv.env"
echo "  ./scripts/build-autoinstall-iso.sh"
echo "  tofu init"
echo "  tofu plan -out=hyperv-install.tfplan"
