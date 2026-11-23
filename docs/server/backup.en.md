# Database backups

The `backup` service (same TimescaleDB image, no extra container to download) takes every day
at `BACKUP_TIME` (time zone `TIMEZONE`) a compressed `pg_dump`, checks it by reading its index
back and stores it in `volumes/backups/daily/`; on Mondays a copy goes to `weekly/`, on the
first of the month to `monthly/`. It keeps `BACKUP_KEEP_DAILY` / `BACKUP_KEEP_WEEKLY` /
`BACKUP_KEEP_MONTHLY` copies (7 / 4 / 6). If at startup the last good backup is older than 24
hours it takes one at once. The state is in **Account → Administration** (last backup, size,
copy off the server, warning when no backup succeeded in the last 26 hours) and in the
healthcheck of the container.

```sh
docker compose exec backup sh /scripts/backup.sh now          # backup now
docker compose exec backup ls -R /backups                     # copies
```

## Copy off the server

Recommended: a backup on the same disk doesn't protect from a failure or a theft of the
server. The `offsite` service (`offsite` profile, `restic` image) copies every day at
`OFFSITE_TIME` the backup folder to an **encrypted** restic repository (S3, Backblaze B2,
SFTP, a network disk...), keeps the same daily, weekly and monthly copies as the local
backups and checks a sample of the uploaded data:

```sh
# .env: RESTIC_REPOSITORY (e.g. s3:https://s3.eu-central-1.amazonaws.com/bucket/car-tracking
#        or sftp:user@nas:/backup/car-tracking), RESTIC_PASSWORD, AWS_* / B2_* keys
docker compose --profile offsite up -d offsite
docker compose run --rm offsite now                          # first copy now
```

For SFTP the SSH key goes in `secrets/ssh/` (mounted read-only). **Keep `RESTIC_PASSWORD` and
`CRYPTO_MASTER_KEY` in a password manager off the server**: without the first the repository
can't be read, without the second the trackers no longer connect to the restored server.

## Automatic restore test

A backup never restored is only a hope. Every week, on day `BACKUP_VERIFY_DAY` (1 Monday ... 7
Sunday, default 7; `off` for never) after the backup, and anyway when the last test is older
than 8 days, the service restores the newest dump into a separate database
(`<POSTGRES_DB>_verify`, then dropped) and checks that it has the same migrations and
hypertables as the database in use and at least one user. The result (time, file, duration,
users, devices, positions, error) goes to `/backups/last-verify` and to **Account →
Administration**, with a warning when the last test failed or is older than 9 days.

```sh
docker compose exec backup sh /scripts/backup.sh verify       # test now
```

Tried on a database of 200 trackers with 90 days of history: an 85 MB dump, restore and checks
in 9 seconds (10 million positions, compressed chunks included). For a few seconds the test
database takes the same space as the one in use: keep it in mind on the disk.

## Restore

Verified: dump and full restore with hypertables and aggregates.

```sh
# Try on a separate database, without touching the one in use
docker compose exec -e RESTORE_DB=ct_restore backup sh /scripts/backup.sh restore /backups/daily/<file>.dump
# Real restore: stops the backend, replaces the database, starts again
docker compose stop backend
docker compose exec backup sh /scripts/backup.sh restore /backups/daily/<file>.dump --yes
docker compose start backend
# From restic, on another server: get the files first
docker compose run --rm --entrypoint restic offsite restore latest --target /backups/restored
```
