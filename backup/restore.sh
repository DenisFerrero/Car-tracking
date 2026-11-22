#!/bin/sh
# Restores a dump into the database, replacing everything in it:
#   docker compose stop backend
#   docker compose run --rm backup restore /backups/daily/<file>.dump --yes
#   docker compose start backend
# RESTORE_DB restores into another database instead (test of a backup, nothing replaced).
# The backend must run with the same CRYPTO_MASTER_KEY of the backup (tracker keys, TOTP).
set -eu

: "${PGHOST:=timescaledb}"
file=${1:-}
target=${RESTORE_DB:-$POSTGRES_DB}
if [ ! -f "$file" ]; then
	echo "Usage: restore <file.dump> --yes   (files: ls /backups/daily /backups/weekly /backups/monthly)" >&2
	exit 2
fi
pg_restore --list "$file" > /dev/null
if [ "$target" = "$POSTGRES_DB" ] && [ "${2:-}" != --yes ]; then
	echo "This replaces every data of the database $target with $file: add --yes" >&2
	exit 2
fi

psql_db () { psql -h "$PGHOST" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 -q "$@"; }

echo "Restoring $file into $target"
psql_db -d postgres -c "DROP DATABASE IF EXISTS \"$target\" WITH (FORCE)"
psql_db -d postgres -c "CREATE DATABASE \"$target\""
psql_db -d "$target" -c "CREATE EXTENSION IF NOT EXISTS timescaledb" -c "SELECT timescaledb_pre_restore()" > /dev/null
pg_restore -h "$PGHOST" -U "$POSTGRES_USER" -d "$target" --no-owner "$file"
psql_db -d "$target" -c "SELECT timescaledb_post_restore()" > /dev/null
psql_db -d "$target" -t -c "SELECT 'users: ' || count(*) FROM users" -c "SELECT 'positions: ' || count(*) FROM positions"
echo "Done"
