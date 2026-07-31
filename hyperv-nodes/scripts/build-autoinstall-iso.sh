#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_DIR="$(cd -- "${MODULE_DIR}/.." && pwd)"
ARTIFACT_DIR="${ASOL_ARTIFACT_DIR:-${REPOSITORY_DIR}/.artifacts}"

UBUNTU_ISO_VERSION="${UBUNTU_ISO_VERSION:-24.04.4}"
UBUNTU_ISO_URL="${UBUNTU_ISO_URL:-https://releases.ubuntu.com/24.04/ubuntu-${UBUNTU_ISO_VERSION}-live-server-amd64.iso}"
UBUNTU_ISO_SHA256="${UBUNTU_ISO_SHA256:-e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433}"
UBUNTU_ISO_CACHE="${UBUNTU_ISO_CACHE:-${ARTIFACT_DIR}/ubuntu-${UBUNTU_ISO_VERSION}-live-server-amd64.iso}"
OUTPUT_ISO="${OUTPUT_ISO:-${ARTIFACT_DIR}/asol-k3s-ubuntu-${UBUNTU_ISO_VERSION}-autoinstall.iso}"

required_commands=(base64 curl envsubst grep openssl python3 realpath sed sha256sum stat wc xorriso)
for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command is missing: ${command_name}" >&2
    echo "On Ubuntu/WSL install: sudo apt-get install curl gettext-base openssl xorriso" >&2
    exit 1
  fi
done

artifact_directory_realpath="$(realpath -m "${ARTIFACT_DIR}")"
ubuntu_iso_cache_realpath="$(realpath -m "${UBUNTU_ISO_CACHE}")"
output_iso_realpath="$(realpath -m "${OUTPUT_ISO}")"
case "${ubuntu_iso_cache_realpath}" in
  "${artifact_directory_realpath}"/*) ;;
  *)
    echo "UBUNTU_ISO_CACHE must be inside ${ARTIFACT_DIR}" >&2
    exit 1
    ;;
esac
case "${output_iso_realpath}" in
  "${artifact_directory_realpath}"/*) ;;
  *)
    echo "OUTPUT_ISO must be inside ${ARTIFACT_DIR}" >&2
    exit 1
    ;;
esac
case "${artifact_directory_realpath}" in
  /mnt/[A-Za-z]/*)
    echo "ARTIFACT_DIR must be on the WSL Linux filesystem, not a Windows /mnt drive" >&2
    exit 1
    ;;
esac

required_variables=(
  ASOLADMIN_PASSWORD_FILE
  ASOLADMIN_SSH_PUBLIC_KEY_FILE
  K3S_TOKEN_FILE
  VM_HOSTNAME
  VM_MAC_ADDRESS
  VM_ADDRESS_CIDR
  VM_GATEWAY
  VM_DNS_SERVERS
  VM_DNS_SEARCH
  K3S_TLS_SAN
)
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Required environment variable is empty: ${variable_name}" >&2
    exit 1
  fi
done

for secret_file in "${ASOLADMIN_PASSWORD_FILE}" "${K3S_TOKEN_FILE}"; do
  if [[ ! -f "${secret_file}" || ! -r "${secret_file}" ]]; then
    echo "Secret file is not readable: ${secret_file}" >&2
    exit 1
  fi
  file_mode="$(stat -c '%a' "${secret_file}")"
  if (( (8#${file_mode} & 8#077) != 0 )); then
    echo "Secret file must not be accessible by group or others: ${secret_file} (${file_mode})" >&2
    exit 1
  fi
done

if [[ ! -f "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" || ! -r "${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" ]]; then
  echo "SSH public key is not readable: ${ASOLADMIN_SSH_PUBLIC_KEY_FILE}" >&2
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
python3 - <<'PY'
import ipaddress
import os
import re


def dns_name(value: str, variable: str) -> str:
    if len(value) > 253 or value.endswith("."):
        raise SystemExit(f"{variable} must be a DNS name without a trailing dot")
    labels = value.split(".")
    label_pattern = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
    if not labels or any(not label_pattern.fullmatch(label) for label in labels):
        raise SystemExit(f"{variable} contains an invalid DNS label")
    return value


interface = ipaddress.ip_interface(os.environ["VM_ADDRESS_CIDR"])
if interface.version != 4:
    raise SystemExit("VM_ADDRESS_CIDR must be IPv4")

gateway = ipaddress.ip_address(os.environ["VM_GATEWAY"])
if gateway.version != 4 or gateway not in interface.network:
    raise SystemExit("VM_GATEWAY must be IPv4 in the VM_ADDRESS_CIDR subnet")
if gateway in (interface.network.network_address, interface.network.broadcast_address):
    raise SystemExit("VM_GATEWAY cannot be the subnet network or broadcast address")

dns_values = os.environ["VM_DNS_SERVERS"].split(",")
if not dns_values or any(value != value.strip() or not value for value in dns_values):
    raise SystemExit("VM_DNS_SERVERS must be a comma-separated list without spaces")
for value in dns_values:
    if ipaddress.ip_address(value).version != 4:
        raise SystemExit("VM_DNS_SERVERS entries must be IPv4")

dns_name(os.environ["VM_DNS_SEARCH"], "VM_DNS_SEARCH")
tls_san = os.environ["K3S_TLS_SAN"]
try:
    ipaddress.ip_address(tls_san)
except ValueError:
    dns_name(tls_san, "K3S_TLS_SAN")
PY

ASOLADMIN_SSH_PUBLIC_KEY="$(tr -d '\r\n' <"${ASOLADMIN_SSH_PUBLIC_KEY_FILE}")"
if [[ ! "${ASOLADMIN_SSH_PUBLIC_KEY}" =~ ^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com)[[:space:]] ]]; then
  echo "Use an Ed25519, ECDSA, or security-key Ed25519 SSH public key" >&2
  exit 1
fi

if [[ ! -s "${ASOLADMIN_PASSWORD_FILE}" ]]; then
  echo "The asoladmin initial password file is empty" >&2
  exit 1
fi
if [[ ! -s "${K3S_TOKEN_FILE}" ]]; then
  echo "The k3s token file is empty" >&2
  exit 1
fi
if (( $(wc -c <"${K3S_TOKEN_FILE}") < 32 )); then
  echo "The k3s token must contain at least 32 bytes" >&2
  exit 1
fi

ASOLADMIN_PASSWORD_HASH="$(
  tr -d '\r\n' <"${ASOLADMIN_PASSWORD_FILE}" |
    openssl passwd -6 -stdin
)"
PREPARE_NODE_SCRIPT_BASE64="$(base64 -w 0 "${REPOSITORY_DIR}/scripts/prepare-ubuntu-node.sh")"
INSTALL_K3S_SCRIPT_BASE64="$(base64 -w 0 "${REPOSITORY_DIR}/scripts/install-k3s-initial-server.sh")"

dns_server_yaml=()
IFS=',' read -r -a dns_servers <<<"${VM_DNS_SERVERS}"
for dns_server in "${dns_servers[@]}"; do
  dns_server_yaml+=("\"${dns_server}\"")
done
VM_DNS_SERVERS_YAML="[$(IFS=,; echo "${dns_server_yaml[*]}")]"
VM_DNS_SEARCH_YAML="$(printf '["%s"]' "${VM_DNS_SEARCH}")"

export ASOLADMIN_PASSWORD_HASH
export ASOLADMIN_SSH_PUBLIC_KEY
export INSTALL_K3S_SCRIPT_BASE64
export PREPARE_NODE_SCRIPT_BASE64
export VM_DNS_SEARCH_YAML
export VM_DNS_SERVERS_YAML

mkdir -p -- "${ARTIFACT_DIR}"
chmod 0700 "${ARTIFACT_DIR}"
artifact_filesystem_type="$(stat -f -c '%T' "${ARTIFACT_DIR}")"
case "${artifact_filesystem_type}" in
  9p | drvfs | fuse*)
    echo "ARTIFACT_DIR filesystem ${artifact_filesystem_type} is not an approved WSL Linux filesystem" >&2
    exit 1
    ;;
esac
artifact_directory_mode="$(stat -c '%a' "${ARTIFACT_DIR}")"
if (( (8#${artifact_directory_mode} & 8#077) != 0 )); then
  echo "ARTIFACT_DIR must not be accessible by group or others: ${ARTIFACT_DIR}" >&2
  exit 1
fi
if [[ ! -d /dev/shm || ! -w /dev/shm ]]; then
  echo "/dev/shm must be available for sensitive temporary installer data" >&2
  exit 1
fi
temporary_directory="$(mktemp -d /dev/shm/asol-autoinstall.XXXXXXXX)"
trap 'rm -rf -- "${temporary_directory}"' EXIT

rendered_autoinstall="${temporary_directory}/autoinstall.yaml"
# The single-quoted list is intentionally passed verbatim to envsubst.
# shellcheck disable=SC2016
envsubst \
  '${VM_HOSTNAME} ${ASOLADMIN_PASSWORD_HASH} ${ASOLADMIN_SSH_PUBLIC_KEY} ${VM_MAC_ADDRESS} ${VM_ADDRESS_CIDR} ${VM_GATEWAY} ${VM_DNS_SERVERS_YAML} ${VM_DNS_SEARCH_YAML} ${PREPARE_NODE_SCRIPT_BASE64} ${INSTALL_K3S_SCRIPT_BASE64} ${K3S_TLS_SAN}' \
  <"${MODULE_DIR}/autoinstall/autoinstall.yaml.tpl" \
  >"${rendered_autoinstall}"

if [[ ! -f "${UBUNTU_ISO_CACHE}" ]]; then
  echo "Downloading Ubuntu Server ${UBUNTU_ISO_VERSION}..."
  curl --fail --location --retry 3 \
    --proto '=https' \
    --proto-redir '=https' \
    --output "${UBUNTU_ISO_CACHE}.part" \
    "${UBUNTU_ISO_URL}"
  mv -- "${UBUNTU_ISO_CACHE}.part" "${UBUNTU_ISO_CACHE}"
fi
printf '%s  %s\n' "${UBUNTU_ISO_SHA256}" "${UBUNTU_ISO_CACHE}" | sha256sum -c -

mkdir -p -- "${temporary_directory}/boot/grub"
xorriso -osirrox on \
  -indev "${UBUNTU_ISO_CACHE}" \
  -extract /boot/grub/grub.cfg "${temporary_directory}/boot/grub/grub.cfg" \
  -extract /boot/grub/loopback.cfg "${temporary_directory}/boot/grub/loopback.cfg"

for grub_configuration in \
  "${temporary_directory}/boot/grub/grub.cfg" \
  "${temporary_directory}/boot/grub/loopback.cfg"; do
  sed -E \
    '/^[[:space:]]*linux[[:space:]]/ { /(^|[[:space:]])autoinstall([[:space:]]|$)/! s/[[:space:]]+---/ autoinstall ---/; }' \
    "${grub_configuration}" >"${grub_configuration}.patched"
  # Files extracted from the Ubuntu ISO are mode 0444. Force replacement so
  # an interactive shell cannot stop unattended builds with an mv prompt.
  mv --force -- "${grub_configuration}.patched" "${grub_configuration}"
  if ! grep -Eq '^[[:space:]]*linux[[:space:]].*[[:space:]]autoinstall([[:space:]]|$)' "${grub_configuration}"; then
    echo "Failed to add the autoinstall kernel argument to ${grub_configuration}" >&2
    exit 1
  fi
done

rm -f -- "${OUTPUT_ISO}"
xorriso \
  -indev "${UBUNTU_ISO_CACHE}" \
  -outdev "${OUTPUT_ISO}" \
  -boot_image any replay \
  -map "${rendered_autoinstall}" /autoinstall.yaml \
  -map "${K3S_TOKEN_FILE}" /k3s-cluster-token \
  -map "${temporary_directory}/boot/grub/grub.cfg" /boot/grub/grub.cfg \
  -map "${temporary_directory}/boot/grub/loopback.cfg" /boot/grub/loopback.cfg
chmod 0600 "${OUTPUT_ISO}"

export OUTPUT_ISO UBUNTU_ISO_SHA256 UBUNTU_ISO_VERSION
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

iso_path = Path(os.environ["OUTPUT_ISO"])
digest = hashlib.sha256()
with iso_path.open("rb") as iso_file:
    for chunk in iter(lambda: iso_file.read(1024 * 1024), b""):
        digest.update(chunk)

manifest = {
    "schema_version": 1,
    "iso_sha256": digest.hexdigest(),
    "ubuntu_iso_version": os.environ["UBUNTU_ISO_VERSION"],
    "ubuntu_base_iso_sha256": os.environ["UBUNTU_ISO_SHA256"],
    "vm_hostname": os.environ["VM_HOSTNAME"],
    "vm_mac_address": os.environ["VM_MAC_ADDRESS"].lower(),
    "vm_address_cidr": os.environ["VM_ADDRESS_CIDR"],
    "vm_gateway": os.environ["VM_GATEWAY"],
    "vm_dns_servers": os.environ["VM_DNS_SERVERS"].split(","),
    "vm_dns_search": os.environ["VM_DNS_SEARCH"],
    "k3s_tls_san": os.environ["K3S_TLS_SAN"],
}
manifest_path = Path(f"{iso_path}.manifest.json")
temporary_manifest_path = Path(f"{manifest_path}.tmp")
with temporary_manifest_path.open("w", encoding="utf-8") as manifest_file:
    json.dump(manifest, manifest_file, indent=2, sort_keys=True)
    manifest_file.write("\n")
os.chmod(temporary_manifest_path, 0o600)
temporary_manifest_path.replace(manifest_path)
PY

unset ASOLADMIN_PASSWORD_HASH
echo "Created sensitive unattended installer: ${OUTPUT_ISO}"
echo "Created non-secret identity manifest: ${OUTPUT_ISO}.manifest.json"
echo "Keep it mode 0600 and delete the runner copy after the Hyper-V install is verified."
