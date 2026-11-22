#!/bin/sh
# Daily dump of the database (service "backup" of docker-compose.yml), with the pg_dump of
# the same image as the server. Every day at BACKUP_TIME (TZ), and at start when the last
# dump is older than a day (server off at that time):
#   /backups/daily/<date>.dump     custom format, compressed, checked with pg_restore --list
#   /backups/weekly/  (Mondays)    /backups/monthly/  (1st of the month)
#   /backups/last-success          time of the last good dump (healthcheck, admin page)
# Copies off the server: service "offsite" (restic) or any sync of ./volumes/backups.
set -eu

: "${BACKUP_TIME:=03:30}"
: "${BACKUP_KEEP_DAILY:=7}"
: "${BACKUP_KEEP_WEEKLY:=4}"
: "${BACKUP_KEEP_MONTHLY:=6}"
: "${PGHOST:=timescaledb}"
DIR=/backups

mkdir -p "$DIR/daily" "$DIR/weekly" "$DIR/monthly"

# Keeps the newest $2 files of a folder
prune () {
	ls -1t "$1"/*.dump 2>/dev/null | tail -n +"$(($2 + 1))" | while read -r old; do rm -f "$old"; done
}

dump () {
	stamp=$(date +%Y-%m-%d_%H%M)
	tmp="$DIR/.partial.dump"
	rm -f "$tmp"
	if ! pg_dump -h "$PGHOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -Z 6 -f "$tmp" || ! pg_restore --list "$tmp" > /dev/null; then
		echo "$(date -Iseconds) backup FAILED" >&2
		rm -f "$tmp"
		return 1
	fi
	mv "$tmp" "$DIR/daily/$stamp.dump"
	[ "$(date +%u)" = 1 ] && cp "$DIR/daily/$stamp.dump" "$DIR/weekly/$stamp.dump"
	[ "$(date +%d)" = 01 ] && cp "$DIR/daily/$stamp.dump" "$DIR/monthly/$stamp.dump"
	prune "$DIR/daily" "$BACKUP_KEEP_DAILY"
	prune "$DIR/weekly" "$BACKUP_KEEP_WEEKLY"
	prune "$DIR/monthly" "$BACKUP_KEEP_MONTHLY"
	date -Iseconds > "$DIR/last-success"
	echo "$(date -Iseconds) backup $stamp.dump $(wc -c < "$DIR/daily/$stamp.dump") bytes"
}

# One-off: docker compose run --rm backup now | restore <file> [--yes]
if [ "${1:-}" = restore ]; then
	shift
	exec sh /scripts/restore.sh "$@"
fi
if [ "${1:-}" = now ]; then
	dump
	exit
fi

until pg_isready -h "$PGHOST" -U "$POSTGRES_USER" -q; do sleep 5; done
if [ -z "$(find "$DIR/last-success" -mmin -1440 2>/dev/null)" ]; then dump || true; fi
last=$(date +%F)
while true; do
	sleep 30
	if [ "$(date +%H:%M)" = "$BACKUP_TIME" ] && [ "$(date +%F)" != "$last" ]; then
		last=$(date +%F)
		dump || true
	fi
done
