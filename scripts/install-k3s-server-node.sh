#!/usr/bin/env bash
set -euo pipefail

: "${K3S_URL:?Set K3S_URL, for example https://10.0.0.10:6443}"

K3S_VERSION="${K3S_VERSION:-v1.36.2+k3s1}"
K3S_INSTALL_SCRIPT_SHA256="${K3S_INSTALL_SCRIPT_SHA256:-46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad}"
K3S_TOKEN_FILE="${K3S_TOKEN_FILE:-/root/k3s-cluster-token}"
K3S_DATA_DIR="/mnt/data/k3s"
K3S_LOCAL_STORAGE_PATH="/mnt/data/local-path"

if ! sudo test -r "${K3S_TOKEN_FILE}"; then
  echo "k3s token file is not readable: ${K3S_TOKEN_FILE}" >&2
  exit 1
fi

if ! mountpoint -q /mnt/data; then
  echo "/mnt/data must be mounted before installing k3s" >&2
  exit 1
fi

if [[ -n "$(swapon --show --noheadings)" ]]; then
  echo "Swap must be disabled before installing k3s" >&2
  exit 1
fi

if findmnt --fstab --types swap --noheadings | grep -q .; then
  echo "Swap entries must be removed or commented out in /etc/fstab before installing k3s" >&2
  exit 1
fi

install_script="$(mktemp)"
trap 'rm -f "${install_script}"' EXIT
k3s_version_url="${K3S_VERSION//+/%2B}"
curl -fsSL \
  "https://raw.githubusercontent.com/k3s-io/k3s/${k3s_version_url}/install.sh" \
  -o "${install_script}"
printf '%s  %s\n' "${K3S_INSTALL_SCRIPT_SHA256}" "${install_script}" | sha256sum -c -

sudo env \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_URL="${K3S_URL}" \
  K3S_TOKEN_FILE="${K3S_TOKEN_FILE}" \
  sh "${install_script}" server \
    "--data-dir=${K3S_DATA_DIR}" \
    "--default-local-storage-path=${K3S_LOCAL_STORAGE_PATH}" \
    --secrets-encryption \
    --etcd-snapshot-compress \
    --etcd-snapshot-retention=14 \
    --write-kubeconfig-mode=0640 \
    --write-kubeconfig-group=k3s-admin \
    --node-label=storage.asol.io/data=true
