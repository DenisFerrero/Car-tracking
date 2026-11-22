#!/bin/sh
# Copy of /backups off the server with restic (service "offsite", profile "offsite"):
# encrypted with RESTIC_PASSWORD, deduplicated, to RESTIC_REPOSITORY (sftp:, s3:, b2:,
# rest:, rclone:...). Every day at OFFSITE_TIME, after the dump of the night.
set -eu

: "${OFFSITE_TIME:=04:30}"
: "${BACKUP_KEEP_DAILY:=7}"
: "${BACKUP_KEEP_WEEKLY:=4}"
: "${BACKUP_KEEP_MONTHLY:=6}"

restic snapshots > /dev/null 2>&1 || restic init

copy () {
	restic backup --host car-tracking --tag database /backups &&
		restic forget --host car-tracking --keep-daily "$BACKUP_KEEP_DAILY" --keep-weekly "$BACKUP_KEEP_WEEKLY" \
			--keep-monthly "$BACKUP_KEEP_MONTHLY" --prune &&
		restic check --read-data-subset=5% &&
		date -Iseconds > /backups/last-offsite ||
		echo "$(date -Iseconds) offsite copy FAILED" >&2
}

if [ "${1:-}" = now ]; then
	copy
	exit
fi

last=""
while true; do
	sleep 30
	if [ "$(date +%H:%M)" = "$OFFSITE_TIME" ] && [ "$(date +%F)" != "$last" ]; then
		last=$(date +%F)
		copy
	fi
done
