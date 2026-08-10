#!/usr/bin/env bash
set -Eeuo pipefail

readonly STATE_DIR='/var/lib/research-web-hosting'
readonly STAGING_ROOT='/home/.virtualmin-data/backup-staging'
readonly LOCK_FILE='/run/lock/virtualmin-blob-backup.lock'

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo 'Another Virtualmin backup is already running.' >&2
  exit 1
fi

source /etc/research-web-hosting.conf
: "${BACKUP_STORAGE_ACCOUNT:?Missing BACKUP_STORAGE_ACCOUNT}"
: "${BACKUP_CONTAINER:?Missing BACKUP_CONTAINER}"

timestamp=$(date -u +'%Y/%m/%d/%Y%m%dT%H%M%SZ')
staging_directory="${STAGING_ROOT}/$(date -u +'%Y%m%dT%H%M%SZ')"
destination="https://${BACKUP_STORAGE_ACCOUNT}.blob.core.windows.net/${BACKUP_CONTAINER}/${timestamp}/"

install -d -m 0700 "${STATE_DIR}" "${STAGING_ROOT}" "${staging_directory}"
rm -f "${STATE_DIR}/last-backup-failed"

on_error() {
  local exit_code=$?
  date --iso-8601=seconds > "${STATE_DIR}/last-backup-failed"
  echo "Virtualmin backup failed; staging retained at ${staging_directory}." >&2
  exit "${exit_code}"
}
trap on_error ERR

domain_output=$(virtualmin list-domains --name-only 2>/dev/null || true)
if [[ -z "${domain_output//[[:space:]]/}" ]]; then
  date --iso-8601=seconds > "${STATE_DIR}/last-backup-empty"
  rmdir "${staging_directory}"
  echo 'No Virtualmin domains exist yet; no backup was created.'
  exit 0
fi

virtualmin backup-domain \
  --dest "${staging_directory}/" \
  --all-domains \
  --all-features \
  --newformat \
  --all-virtualmin

export AZCOPY_AUTO_LOGIN_TYPE=MSI
azcopy copy "${staging_directory}" "${destination}" --recursive=true
azcopy list "${destination}"

case "${staging_directory}" in
  "${STAGING_ROOT}"/*)
    rm -rf -- "${staging_directory}"
    ;;
  *)
    echo "Unsafe staging path; refusing cleanup: ${staging_directory}" >&2
    exit 1
    ;;
esac

date --iso-8601=seconds > "${STATE_DIR}/last-backup-success"
rm -f "${STATE_DIR}/last-backup-failed" "${STATE_DIR}/last-backup-empty"
echo "Virtualmin backup uploaded to ${destination}"

