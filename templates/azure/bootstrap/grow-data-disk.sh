#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOG_TAG='grow-research-web-data'
exec > >(systemd-cat -t "${LOG_TAG}") 2>&1

resolve_data_disk() {
  local candidate
  for candidate in \
    /dev/disk/azure/data/by-lun/0 \
    /dev/disk/azure/scsi1/lun0; do
    if [[ -b "${candidate}" ]]; then
      readlink -f "${candidate}"
      return 0
    fi
  done
  echo 'Azure data disk LUN 0 is unavailable.' >&2
  return 1
}

data_disk=$(resolve_data_disk)
if [[ "${data_disk}" =~ [0-9]$ ]]; then
  data_partition="${data_disk}p1"
else
  data_partition="${data_disk}1"
fi

if [[ ! -b "${data_partition}" ]]; then
  echo "Expected LVM partition is missing: ${data_partition}" >&2
  exit 1
fi
if [[ $(pvs --noheadings -o vg_name "${data_partition}" | xargs) != 'vg_webdata' ]]; then
  echo "${data_partition} is not a vg_webdata physical volume." >&2
  exit 1
fi
if [[ ! -b /dev/vg_webdata/lv_webdata ]]; then
  echo 'Expected logical volume /dev/vg_webdata/lv_webdata is missing.' >&2
  exit 1
fi
if [[ $(findmnt -n -o SOURCE /home) != '/dev/mapper/vg_webdata-lv_webdata' && \
      $(findmnt -n -o SOURCE /home) != '/dev/vg_webdata/lv_webdata' ]]; then
  echo '/home is not mounted from lv_webdata; refusing to grow anything.' >&2
  exit 1
fi
if [[ ! -f /home/.research-web-hosting-volume ]]; then
  echo 'The Research Web Hosting volume marker is missing.' >&2
  exit 1
fi

disk_bytes=$(blockdev --getsize64 "${data_disk}")
partition_bytes=$(blockdev --getsize64 "${data_partition}")

# Leave room for GPT metadata when deciding whether the partition needs growth.
if (( disk_bytes - partition_bytes > 16777216 )); then
  echo "Growing partition 1 on ${data_disk}."
  growpart "${data_disk}" 1
  partprobe "${data_disk}"
  udevadm settle
  pvresize "${data_partition}"
fi

free_extents=$(vgs --noheadings --units e --nosuffix -o vg_free_count vg_webdata | xargs)
if [[ "${free_extents}" =~ ^[0-9]+$ ]] && (( free_extents > 0 )); then
  echo "Extending lv_webdata by ${free_extents} free extents."
  lvextend --extents +100%FREE /dev/vg_webdata/lv_webdata
fi

xfs_growfs /home
xfs_quota -x -c 'state' /home
df -hT /home

