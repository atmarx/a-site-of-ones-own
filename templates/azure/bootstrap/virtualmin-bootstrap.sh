#!/usr/bin/env bash
set -Eeuo pipefail

readonly HOST_FQDN='__HOST_FQDN__'
readonly ADMIN_USERNAME='__ADMIN_USERNAME__'
readonly BACKUP_STORAGE_ACCOUNT='__BACKUP_STORAGE_ACCOUNT__'
readonly BACKUP_CONTAINER='__BACKUP_CONTAINER__'
readonly ADMIN_SOURCE_CIDRS='__ADMIN_SOURCE_CIDRS__'
readonly STATE_DIR='/var/lib/research-web-hosting'
readonly LOG_FILE='/var/log/research-web-hosting-bootstrap.log'
readonly COMPLETE_MARKER="${STATE_DIR}/bootstrap-complete"
readonly FAILED_MARKER="${STATE_DIR}/bootstrap-failed"
readonly SERVICE_SCRIPT='/usr/local/sbin/research-web-hosting-bootstrap'

install_bootstrap_service() {
  install -d -m 0700 "${STATE_DIR}"
  install -m 0700 "$0" "${SERVICE_SCRIPT}"

  cat > /etc/systemd/system/virtualmin-bootstrap.service <<'UNIT'
[Unit]
Description=Provision the Research Web Hosting Virtualmin server
Wants=network-online.target
After=network-online.target cloud-final.service

[Service]
Type=oneshot
Environment=RWH_BOOTSTRAP_SERVICE=1
ExecStart=/usr/local/sbin/research-web-hosting-bootstrap
RemainAfterExit=yes
TimeoutStartSec=90min

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable virtualmin-bootstrap.service
  systemctl start --no-block virtualmin-bootstrap.service
}

if [[ "${RWH_BOOTSTRAP_SERVICE:-0}" != '1' ]]; then
  install_bootstrap_service
  exit 0
fi

install -d -m 0700 "${STATE_DIR}"
touch "${LOG_FILE}"
chmod 0600 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}" | systemd-cat -t virtualmin-bootstrap) 2>&1

on_error() {
  local exit_code=$?
  printf 'Bootstrap failed at line %s with exit code %s\n' "${BASH_LINENO[0]}" "${exit_code}"
  date --iso-8601=seconds > "${FAILED_MARKER}"
  exit "${exit_code}"
}
trap on_error ERR

if [[ -f "${COMPLETE_MARKER}" ]]; then
  echo 'Bootstrap has already completed; refusing to reinstall Virtualmin.'
  exit 0
fi
rm -f "${FAILED_MARKER}"

require_expected_value() {
  local value=$1
  local label=$2
  if [[ -z "${value}" || "${value}" == __*__ ]]; then
    echo "Missing deployment value: ${label}" >&2
    return 1
  fi
}

require_expected_value "${HOST_FQDN}" HOST_FQDN
require_expected_value "${ADMIN_USERNAME}" ADMIN_USERNAME
require_expected_value "${BACKUP_STORAGE_ACCOUNT}" BACKUP_STORAGE_ACCOUNT
require_expected_value "${BACKUP_CONTAINER}" BACKUP_CONTAINER
require_expected_value "${ADMIN_SOURCE_CIDRS}" ADMIN_SOURCE_CIDRS

echo "Starting Virtualmin bootstrap for ${HOST_FQDN}"
date --iso-8601=seconds
cat /etc/os-release
uname -a

hostnamectl set-hostname "${HOST_FQDN}"
private_ipv4=$(ip -4 route get 168.63.129.16 | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')
short_hostname=${HOST_FQDN%%.*}
if [[ -n "${private_ipv4}" ]] && ! grep -Fq "${HOST_FQDN}" /etc/hosts; then
  printf '%s %s %s\n' "${private_ipv4}" "${HOST_FQDN}" "${short_hostname}" >> /etc/hosts
fi

dnf install -y \
  cloud-utils-growpart \
  curl \
  firewalld \
  jq \
  lvm2 \
  nvme-cli \
  parted \
  policycoreutils-python-utils \
  rsync \
  xfsprogs

# Recent Azure images normally include this. Install it when the package is
# available so NVMe and SCSI VMs expose the same stable by-LUN paths.
dnf install -y azure-vm-utils || true
udevadm control --reload-rules
udevadm trigger
udevadm settle

resolve_data_disk() {
  local candidate
  local attempt
  for attempt in $(seq 1 60); do
    for candidate in \
      /dev/disk/azure/data/by-lun/0 \
      /dev/disk/azure/scsi1/lun0; do
      if [[ -b "${candidate}" ]]; then
        readlink -f "${candidate}"
        return 0
      fi
    done
    sleep 2
    udevadm trigger
    udevadm settle
  done
  echo 'Azure data disk LUN 0 did not appear under a stable Azure path.' >&2
  return 1
}

data_disk=$(resolve_data_disk)
if [[ ! -b "${data_disk}" ]]; then
  echo "Resolved LUN 0 path is not a block device: ${data_disk}" >&2
  exit 1
fi

if [[ "${data_disk}" =~ [0-9]$ ]]; then
  data_partition="${data_disk}p1"
else
  data_partition="${data_disk}1"
fi

echo "Azure LUN 0 resolves to ${data_disk}; expected partition is ${data_partition}"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS "${data_disk}"

new_data_volume=false
if [[ ! -b "${data_partition}" ]]; then
  if [[ $(lsblk -nr -o TYPE "${data_disk}" | grep -c '^part$' || true) -ne 0 ]]; then
    echo "LUN 0 has an unexpected partition layout; refusing to modify ${data_disk}." >&2
    exit 1
  fi
  if wipefs --noheadings "${data_disk}" | grep -q .; then
    echo "LUN 0 contains an unexpected signature; refusing to format ${data_disk}." >&2
    wipefs "${data_disk}"
    exit 1
  fi

  parted --script --align optimal "${data_disk}" \
    mklabel gpt \
    mkpart primary 1MiB 100% \
    set 1 lvm on
  partprobe "${data_disk}"
  udevadm settle

  if [[ ! -b "${data_partition}" ]]; then
    echo "Partition ${data_partition} was not created." >&2
    exit 1
  fi

  pvcreate --yes "${data_partition}"
  vgcreate vg_webdata "${data_partition}"
  lvcreate --name lv_webdata --extents 100%FREE vg_webdata
  mkfs.xfs -L VM_DATA /dev/vg_webdata/lv_webdata
  new_data_volume=true
else
  existing_vg=$(pvs --noheadings -o vg_name "${data_partition}" 2>/dev/null | xargs || true)
  if [[ "${existing_vg}" != 'vg_webdata' ]]; then
    echo "Existing partition ${data_partition} is not the expected vg_webdata PV." >&2
    exit 1
  fi
  vgchange -ay vg_webdata
  if [[ ! -b /dev/vg_webdata/lv_webdata ]]; then
    echo 'Expected logical volume /dev/vg_webdata/lv_webdata is missing.' >&2
    exit 1
  fi
  if [[ $(blkid -s TYPE -o value /dev/vg_webdata/lv_webdata) != 'xfs' ]]; then
    echo 'Existing lv_webdata does not contain XFS; refusing to continue.' >&2
    exit 1
  fi
fi

temporary_mount='/mnt/research-web-hosting-data'
install -d -m 0755 "${temporary_mount}"
mount /dev/vg_webdata/lv_webdata "${temporary_mount}"

volume_marker="${temporary_mount}/.research-web-hosting-volume"
if [[ "${new_data_volume}" == true ]]; then
  rsync -aHAX /home/ "${temporary_mount}/"
  cat > "${volume_marker}" <<EOF
schema=1
volume_group=vg_webdata
logical_volume=lv_webdata
created=$(date --iso-8601=seconds)
EOF
  chmod 0600 "${volume_marker}"
elif [[ ! -f "${volume_marker}" ]]; then
  echo 'Existing data volume lacks the expected ownership marker; refusing to mount it.' >&2
  umount "${temporary_mount}"
  exit 1
fi

# Preserve Azure-created SSH access when attaching a known existing data disk
# to a replacement OS disk.
if [[ -d "/home/${ADMIN_USERNAME}" ]]; then
  install -d "${temporary_mount}/${ADMIN_USERNAME}"
  rsync -aHAX --ignore-existing "/home/${ADMIN_USERNAME}/" "${temporary_mount}/${ADMIN_USERNAME}/"
fi
umount "${temporary_mount}"

filesystem_uuid=$(blkid -s UUID -o value /dev/vg_webdata/lv_webdata)
if [[ -z "${filesystem_uuid}" ]]; then
  echo 'Unable to read the lv_webdata filesystem UUID.' >&2
  exit 1
fi

cp -a /etc/fstab "${STATE_DIR}/fstab.before-data-mount"
if ! grep -Eq "^[[:space:]]*UUID=${filesystem_uuid}[[:space:]]+/home[[:space:]]" /etc/fstab; then
  printf 'UUID=%s /home xfs defaults,noatime,uquota,gquota,nofail 0 0\n' "${filesystem_uuid}" >> /etc/fstab
fi
if ! mountpoint -q /home; then
  mount /home
fi

if [[ ! -f "/home/${ADMIN_USERNAME}/.ssh/authorized_keys" ]]; then
  echo 'Admin authorized_keys was not preserved on the data volume.' >&2
  exit 1
fi
chmod 0700 "/home/${ADMIN_USERNAME}/.ssh"
chmod 0600 "/home/${ADMIN_USERNAME}/.ssh/authorized_keys"
chown -R "${ADMIN_USERNAME}:${ADMIN_USERNAME}" "/home/${ADMIN_USERNAME}/.ssh"

install -d -m 0750 /home/.virtualmin-data/mysql
install -d -m 0755 /var/lib/mysql
mysql_bind_line='/home/.virtualmin-data/mysql /var/lib/mysql none bind,x-systemd.requires-mounts-for=/home,nofail 0 0'
if ! grep -Fqx "${mysql_bind_line}" /etc/fstab; then
  printf '%s\n' "${mysql_bind_line}" >> /etc/fstab
fi
if ! mountpoint -q /var/lib/mysql; then
  mount /var/lib/mysql
fi

semanage fcontext -a -t mysqld_db_t '/home/.virtualmin-data/mysql(/.*)?' 2>/dev/null || \
  semanage fcontext -m -t mysqld_db_t '/home/.virtualmin-data/mysql(/.*)?'
restorecon -RF /home
restorecon -RF /var/lib/mysql

findmnt /home
findmnt /var/lib/mysql
xfs_quota -x -c 'state' /home
mount_options=$(findmnt -n -o OPTIONS /home)
if [[ "${mount_options}" != *usrquota* || "${mount_options}" != *grpquota* ]]; then
  echo "XFS user/group quotas are not active on /home: ${mount_options}" >&2
  exit 1
fi

cat > /etc/ssh/sshd_config.d/60-research-web-hosting.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sshd -t
systemctl reload sshd

if ! rpm -q webmin-virtual-server >/dev/null 2>&1; then
  virtualmin_installer='/root/virtualmin-install.sh'
  curl -fsSL https://download.virtualmin.com/virtualmin-install -o "${virtualmin_installer}"
  chmod 0700 "${virtualmin_installer}"
  sha256sum "${virtualmin_installer}" | tee "${STATE_DIR}/virtualmin-installer.sha256"
  /bin/sh "${virtualmin_installer}" \
    --bundle LEMP \
    --type mini \
    --branch stable \
    --hostname "${HOST_FQDN}" \
    --yes \
    --no-banner
else
  echo 'Virtualmin is already installed; the installer will not be rerun.'
fi

if ! rpm -q webmin-virtual-server >/dev/null 2>&1; then
  echo 'The Virtualmin GPL virtual-server module was not installed.' >&2
  exit 1
fi
if ! rpm -q webmin-virtualmin-nginx webmin-virtualmin-nginx-ssl >/dev/null 2>&1; then
  echo 'The Virtualmin Nginx website modules were not installed.' >&2
  exit 1
fi

# Virtualmin disables SELinux persistently on Enterprise Linux. Preserve its
# non-enforcing runtime expectation while retaining labels and audit visibility.
sed -ri 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

for unwanted_service in \
  httpd.service \
  cockpit.service \
  cockpit.socket \
  postfix.service \
  dovecot.service \
  named.service \
  proftpd.service \
  spamassassin.service \
  spamd.service \
  clamd.service \
  clamav-daemon.service; do
  if systemctl list-unit-files "${unwanted_service}" --no-legend 2>/dev/null | grep -q .; then
    systemctl disable --now "${unwanted_service}" || true
  fi
done

cat > /etc/my.cnf.d/90-research-web-hosting-bind.cnf <<'EOF'
[mysqld]
bind-address=127.0.0.1
EOF
systemctl restart mariadb

systemctl enable --now firewalld
for unwanted_firewall_service in \
  cockpit dns dns-over-tls ftp imap imaps pop3 pop3s smtp smtp-submission smtps ssh; do
  firewall-cmd --permanent --zone=public --remove-service="${unwanted_firewall_service}" || true
done
for unwanted_port in \
  20/tcp 21/tcp 25/tcp 53/tcp 53/udp 110/tcp 143/tcp 465/tcp 587/tcp \
  993/tcp 995/tcp 2222/tcp 3306/tcp 9090/tcp 10000-10100/tcp 20000/tcp \
  49152-65535/tcp; do
  firewall-cmd --permanent --zone=public --remove-port="${unwanted_port}" || true
done
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https

IFS=',' read -r -a administrator_cidrs <<< "${ADMIN_SOURCE_CIDRS}"
for administrator_cidr in "${administrator_cidrs[@]}"; do
  if [[ ! "${administrator_cidr}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
    echo "Invalid IPv4 administrator CIDR: ${administrator_cidr}" >&2
    exit 1
  fi
  for admin_port in 22 10000; do
    rich_rule="rule family=\"ipv4\" source address=\"${administrator_cidr}\" port port=\"${admin_port}\" protocol=\"tcp\" accept"
    if ! firewall-cmd --permanent --zone=public --query-rich-rule="${rich_rule}"; then
      firewall-cmd --permanent --zone=public --add-rich-rule="${rich_rule}"
    fi
  done
done
firewall-cmd --reload

# Install a pinned official AzCopy release only after Virtualmin has completed
# its clean-OS installation. AzCopy uses the VM identity; no key is stored here.
azcopy_version='10.32.4'
azcopy_sha256='8f859a0dbbc117660c249fb3569694fc8a0f33b68701f5b2b92ccc001ee50784'
if ! command -v azcopy >/dev/null 2>&1; then
  azcopy_work_dir=$(mktemp -d)
  azcopy_archive="${azcopy_work_dir}/azcopy.tar.gz"
  curl -fsSL \
    "https://github.com/Azure/azure-storage-azcopy/releases/download/v${azcopy_version}/azcopy_linux_amd64_${azcopy_version}.tar.gz" \
    -o "${azcopy_archive}"
  printf '%s  %s\n' "${azcopy_sha256}" "${azcopy_archive}" | sha256sum --check
  tar -xzf "${azcopy_archive}" -C "${azcopy_work_dir}"
  azcopy_binary=$(find "${azcopy_work_dir}" -type f -name azcopy -print -quit)
  if [[ -z "${azcopy_binary}" ]]; then
    echo 'AzCopy archive did not contain the expected executable.' >&2
    exit 1
  fi
  install -m 0755 "${azcopy_binary}" /usr/local/bin/azcopy
  rm -rf -- "${azcopy_work_dir}"
fi
azcopy --version | tee "${STATE_DIR}/azcopy-version.txt"

cat > /etc/research-web-hosting.conf <<EOF
BACKUP_STORAGE_ACCOUNT=${BACKUP_STORAGE_ACCOUNT}
BACKUP_CONTAINER=${BACKUP_CONTAINER}
EOF
chmod 0600 /etc/research-web-hosting.conf

printf '%s' '__GROW_SCRIPT_BASE64__' | base64 --decode > /usr/local/sbin/grow-research-web-data
printf '%s' '__BACKUP_SCRIPT_BASE64__' | base64 --decode > /usr/local/sbin/backup-virtualmin-to-blob
chmod 0700 /usr/local/sbin/grow-research-web-data /usr/local/sbin/backup-virtualmin-to-blob

cat > /etc/systemd/system/grow-research-web-data.service <<'UNIT'
[Unit]
Description=Grow the Research Web Hosting LVM data volume when its Azure disk expands
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/grow-research-web-data

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/virtualmin-blob-backup.service <<'UNIT'
[Unit]
Description=Back up Virtualmin domains to Azure Blob Storage
Wants=network-online.target
After=network-online.target mariadb.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/backup-virtualmin-to-blob
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT

cat > /etc/systemd/system/virtualmin-blob-backup.timer <<'UNIT'
[Unit]
Description=Nightly Virtualmin backup schedule

[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable grow-research-web-data.service virtualmin-blob-backup.timer
systemctl start virtualmin-blob-backup.timer

nginx -t

for required_service in nginx mariadb php-fpm webmin firewalld; do
  if ! systemctl is-active --quiet "${required_service}"; then
    echo "Required service is not active: ${required_service}" >&2
    systemctl status "${required_service}" --no-pager || true
    exit 1
  fi
done

for unwanted_service in httpd.service cockpit.service cockpit.socket postfix dovecot named proftpd spamassassin spamd clamd; do
  if systemctl is-active --quiet "${unwanted_service}"; then
    echo "Unwanted service is active: ${unwanted_service}" >&2
    exit 1
  fi
done

if ss -lntup | grep -Eq ':(21|25|53|110|143|465|587|993|995|9090)[[:space:]]'; then
  echo 'An unwanted public-facing service port is listening.' >&2
  ss -lntup
  exit 1
fi

while IFS= read -r mariadb_listener; do
  case "${mariadb_listener}" in
    127.*:3306|'[::1]':3306)
      ;;
    *)
      echo "MariaDB is listening beyond loopback: ${mariadb_listener}" >&2
      ss -lntup
      exit 1
      ;;
  esac
done < <(ss -H -lnt 'sport = :3306' | awk '{ print $4 }')

virtualmin check-config | tee "${STATE_DIR}/virtualmin-check-config.log" || \
  echo 'Virtualmin reported a configuration warning; review the saved log during handoff.'

date --iso-8601=seconds > "${COMPLETE_MARKER}"
rm -f "${FAILED_MARKER}"
echo 'Research Web Hosting Virtualmin bootstrap completed successfully.'
