#!/usr/bin/env bash
set -euo pipefail

ASOLADMIN_PASSWORD_FILE="${ASOLADMIN_PASSWORD_FILE:-/root/asoladmin-initial-password}"
DATA_MOUNT="/mnt/data"

if ! sudo test -r "${ASOLADMIN_PASSWORD_FILE}"; then
  echo "Initial asoladmin password file is not readable: ${ASOLADMIN_PASSWORD_FILE}" >&2
  exit 1
fi

if ! mountpoint -q "${DATA_MOUNT}"; then
  echo "${DATA_MOUNT} must be a separate mount point before preparing the node" >&2
  exit 1
fi

root_source="$(findmnt -n -o SOURCE --target /)"
root_filesystem="$(findmnt -n -o FSTYPE --target /)"
data_source="$(findmnt -n -o SOURCE --target "${DATA_MOUNT}")"
data_filesystem="$(findmnt -n -o FSTYPE --target "${DATA_MOUNT}")"
data_options="$(findmnt -n -o OPTIONS --target "${DATA_MOUNT}")"

if [[ "${root_source}" == "${data_source}" ]]; then
  echo "${DATA_MOUNT} must use a separate partition or LVM logical volume from /" >&2
  exit 1
fi

if [[ "${root_filesystem}" != "ext4" ]]; then
  echo "/ must use ext4; detected ${root_filesystem}" >&2
  exit 1
fi

if [[ "${data_filesystem}" != "xfs" ]]; then
  echo "${DATA_MOUNT} must use XFS; detected ${data_filesystem}" >&2
  exit 1
fi

if [[ ",${data_options}," != *,rw,* ]]; then
  echo "${DATA_MOUNT} must be mounted read-write" >&2
  exit 1
fi

if [[ -n "$(swapon --show --noheadings)" ]]; then
  echo "Swap must be disabled in the running system and /etc/fstab before installing k3s" >&2
  exit 1
fi

sudo groupadd --force --system k3s-admin

if ! id asoladmin >/dev/null 2>&1; then
  sudo useradd \
    --create-home \
    --shell /bin/bash \
    --groups sudo,k3s-admin \
    asoladmin
else
  sudo usermod --append --groups sudo,k3s-admin asoladmin
fi

initial_password="$(sudo cat -- "${ASOLADMIN_PASSWORD_FILE}")"
if [[ -z "${initial_password}" ]]; then
  echo "Initial asoladmin password must not be empty" >&2
  exit 1
fi

printf 'asoladmin:%s\n' "${initial_password}" | sudo chpasswd
sudo chage --lastday 0 asoladmin
unset initial_password

sudo apt-get update
sudo apt-get install -y \
  cryptsetup \
  dmsetup \
  nfs-common \
  open-iscsi \
  xfsprogs

sudo systemctl enable --now iscsid
sudo modprobe iscsi_tcp

if ! sudo xfs_info "${DATA_MOUNT}" | grep -q 'ftype=1'; then
  echo "${DATA_MOUNT} XFS filesystem must have ftype=1" >&2
  exit 1
fi

sudo install -d -m 0755 \
  "${DATA_MOUNT}/k3s" \
  "${DATA_MOUNT}/local-path" \
  "${DATA_MOUNT}/longhorn"

cat <<'MESSAGE'
Node prerequisites are installed.

The asoladmin account was created. Its initial password must be changed at the
first Hyper-V console login. SSH password authentication was not enabled.

The data mount was verified. Platform data will use:
  /mnt/data/k3s
  /mnt/data/local-path
  /mnt/data/longhorn

The / and /mnt/data filesystems may share one Hyper-V VHDX, but they must be
separate partitions or LVM logical volumes. See docs/HYPER-V.md.
MESSAGE
