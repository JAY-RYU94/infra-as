#!/usr/bin/env bash
set -euo pipefail

ASOLADMIN_PASSWORD_FILE="${ASOLADMIN_PASSWORD_FILE:-}"
EXPIRE_ASOLADMIN_PASSWORD="${EXPIRE_ASOLADMIN_PASSWORD:-false}"
DATA_MOUNT="/mnt/data"
K3S_QUOTA_PERCENT="${K3S_QUOTA_PERCENT:-15}"
LOCAL_PATH_QUOTA_PERCENT="${LOCAL_PATH_QUOTA_PERCENT:-50}"
LONGHORN_MAX_PERCENT=30

if [[ "${EXPIRE_ASOLADMIN_PASSWORD}" != "true" && "${EXPIRE_ASOLADMIN_PASSWORD}" != "false" ]]; then
  echo "EXPIRE_ASOLADMIN_PASSWORD must be true or false" >&2
  exit 1
fi

if [[ -n "${ASOLADMIN_PASSWORD_FILE}" ]]; then
  if ! sudo test -r "${ASOLADMIN_PASSWORD_FILE}"; then
    echo "Initial asoladmin password file is not readable: ${ASOLADMIN_PASSWORD_FILE}" >&2
    exit 1
  fi
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

if [[ ",${data_options}," != *,prjquota,* && ",${data_options}," != *,pquota,* ]]; then
  echo "${DATA_MOUNT} must be mounted with the XFS prjquota option" >&2
  exit 1
fi

for quota_percent in \
  "${K3S_QUOTA_PERCENT}" \
  "${LOCAL_PATH_QUOTA_PERCENT}"; do
  if [[ ! "${quota_percent}" =~ ^([1-9]|[1-9][0-9])$ ]]; then
    echo "XFS quota percentages must be integers from 1 to 99" >&2
    exit 1
  fi
done

k3s_quota_percent_decimal=$((10#${K3S_QUOTA_PERCENT}))
local_path_quota_percent_decimal=$((10#${LOCAL_PATH_QUOTA_PERCENT}))
quota_total_percent=$((
  k3s_quota_percent_decimal +
    local_path_quota_percent_decimal +
    LONGHORN_MAX_PERCENT
))
if ((quota_total_percent > 95)); then
  echo "k3s, local-path, and Longhorn capacity percentages must total 95 or less" >&2
  exit 1
fi

if [[ -n "$(swapon --show --noheadings)" ]]; then
  echo "Swap must be disabled in the running system and /etc/fstab before installing k3s" >&2
  exit 1
fi

if findmnt --fstab --types swap --noheadings | grep -q .; then
  echo "Swap entries must be removed or commented out in /etc/fstab before installing k3s" >&2
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

if [[ -n "${ASOLADMIN_PASSWORD_FILE}" ]]; then
  initial_password="$(sudo cat -- "${ASOLADMIN_PASSWORD_FILE}")"
  if [[ -z "${initial_password}" ]]; then
    echo "Initial asoladmin password must not be empty" >&2
    exit 1
  fi

  printf 'asoladmin:%s\n' "${initial_password}" | sudo chpasswd
  unset initial_password
fi

if [[ -n "${ASOLADMIN_PASSWORD_FILE}" || "${EXPIRE_ASOLADMIN_PASSWORD}" == "true" ]]; then
  sudo chage --lastday 0 asoladmin
fi

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

data_size_kib="$(
  df --block-size=1K --output=size "${DATA_MOUNT}" |
    tail -n 1 |
    tr -d '[:space:]'
)"
k3s_quota_kib=$((data_size_kib * k3s_quota_percent_decimal / 100))
local_path_quota_kib=$((data_size_kib * local_path_quota_percent_decimal / 100))
k3s_used_kib="$(sudo du --block-size=1K --summarize "${DATA_MOUNT}/k3s" | awk '{print $1}')"
local_path_used_kib="$(sudo du --block-size=1K --summarize "${DATA_MOUNT}/local-path" | awk '{print $1}')"

if ((k3s_quota_kib <= k3s_used_kib)); then
  echo "Requested k3s quota is not larger than its current ${k3s_used_kib} KiB usage" >&2
  exit 1
fi
if ((local_path_quota_kib <= local_path_used_kib)); then
  echo "Requested local-path quota is not larger than its current ${local_path_used_kib} KiB usage" >&2
  exit 1
fi

sudo xfs_quota -x \
  -c "project -s -p ${DATA_MOUNT}/k3s 11001" \
  -c "limit -p bhard=${k3s_quota_kib}k 11001" \
  "${DATA_MOUNT}"
sudo xfs_quota -x \
  -c "project -s -p ${DATA_MOUNT}/local-path 11002" \
  -c "limit -p bhard=${local_path_quota_kib}k 11002" \
  "${DATA_MOUNT}"
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

printf \
  'Capacity limits: XFS k3s=%s%%, XFS local-path=%s%%, Longhorn scheduler=%s%%; unallocated headroom=%s%%.\n' \
  "${K3S_QUOTA_PERCENT}" \
  "${LOCAL_PATH_QUOTA_PERCENT}" \
  "${LONGHORN_MAX_PERCENT}" \
  "$((100 - quota_total_percent))"
