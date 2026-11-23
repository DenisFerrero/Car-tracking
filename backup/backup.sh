#!/bin/sh
# Daily dump of the database (service "backup" of docker-compose.yml), with the pg_dump of
# the same image as the server. Every day at BACKUP_TIME (TZ), and at start when the last
# dump is older than a day (server off at that time):
#   /backups/daily/<date>.dump     custom format, compressed, checked with pg_restore --list
#   /backups/weekly/  (Mondays)    /backups/monthly/  (1st of the month)
#   /backups/last-success          time of the last good dump (healthcheck, admin page)
#   /backups/last-verify           result of the last restore test (admin page)
# Restore test: every BACKUP_VERIFY_DAY (1 Monday ... 7 Sunday, default 7, "off" never)
# after the dump, and after a dump when the last test is older than 8 days, the newest dump
# is restored into a separate database (<POSTGRES_DB>_verify, then dropped) and checked:
# same migrations and hypertables as the database in use, at least one user.
# Copies off the server: service "offsite" (restic) or any sync of ./volumes/backups.
set -eu

: "${BACKUP_TIME:=03:30}"
: "${BACKUP_KEEP_DAILY:=7}"
: "${BACKUP_KEEP_WEEKLY:=4}"
: "${BACKUP_KEEP_MONTHLY:=6}"
: "${BACKUP_VERIFY_DAY:=7}"
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

# Restores the newest dump into a separate database and checks it; writes last-verify (JSON)
verify () {
	file=$(ls -1t "$DIR"/daily/*.dump 2>/dev/null | head -n 1)
	[ -n "$file" ] || { echo "$(date -Iseconds) verify: no dump" >&2; return 1; }
	db="${POSTGRES_DB}_verify"
	started=$(date +%s)
	q () { psql -h "$PGHOST" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 -At -d "$1" -c "$2"; }
	check="SELECT (SELECT count(*) FROM schema_migrations) || ':' || (SELECT count(*) FROM timescaledb_information.hypertables)"
	ok=false
	reason=""
	counts="0 0 0"
	if ! RESTORE_DB="$db" sh /scripts/restore.sh "$file" > /dev/null 2> "$DIR/.verify.log"; then
		reason="restore failed: $(tail -n 1 "$DIR/.verify.log" | tr -d '"\\')"
	elif [ "$(q "$db" "$check")" != "$(q "$POSTGRES_DB" "$check")" ]; then
		reason="migrations or hypertables differ from the database in use"
	else
		counts=$(q "$db" "SELECT (SELECT count(*) FROM users) || ' ' || (SELECT count(*) FROM devices) || ' ' || (SELECT count(*) FROM positions)")
		if [ "${counts%% *}" -gt 0 ]; then ok=true; else reason="no users"; fi
	fi
	q postgres "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" > /dev/null || true
	rm -f "$DIR/.verify.log"
	set -- $counts
	printf '{"time":"%s","file":"%s","ok":%s,"seconds":%s,"users":%s,"devices":%s,"positions":%s,"error":"%s"}\n' \
		"$(date -Iseconds)" "${file#"$DIR"/}" "$ok" "$(($(date +%s) - started))" "$1" "$2" "$3" "$reason" > "$DIR/last-verify"
	echo "$(date -Iseconds) verify ${file#"$DIR"/}: $([ "$ok" = true ] && echo ok || echo "FAILED, $reason")"
	[ "$ok" = true ]
}

# A restore test after the dump: on the chosen day, or when the last one is old
verify_due () {
	[ "$BACKUP_VERIFY_DAY" != off ] || return 1
	[ "$(date +%u)" = "$BACKUP_VERIFY_DAY" ] || [ -z "$(find "$DIR/last-verify" -mmin -11520 2>/dev/null)" ]
}

# One-off: docker compose run --rm backup now | verify | restore <file> [--yes]
if [ "${1:-}" = verify ]; then
	verify
	exit
fi
if [ "${1:-}" = restore ]; then
	shift
	exec sh /scripts/restore.sh "$@"
fi
if [ "${1:-}" = now ]; then
	dump
	exit
fi

until pg_isready -h "$PGHOST" -U "$POSTGRES_USER" -q; do sleep 5; done
if [ -z "$(find "$DIR/last-success" -mmin -1440 2>/dev/null)" ]; then dump && verify_due && verify || true; fi
last=$(date +%F)
while true; do
	sleep 30
	if [ "$(date +%H:%M)" = "$BACKUP_TIME" ] && [ "$(date +%F)" != "$last" ]; then
		last=$(date +%F)
		dump && verify_due && verify || true
	fi
done
