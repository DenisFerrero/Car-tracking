# Backup del database

Il servizio `backup` (stessa immagine TimescaleDB, nessun container in più da scaricare) fa
ogni giorno alle `BACKUP_TIME` (fuso `TIMEZONE`) un `pg_dump` compresso, lo verifica
rileggendone l'indice e lo mette in `volumes/backups/daily/`; il lunedì una copia va in
`weekly/`, il primo del mese in `monthly/`. Si tengono `BACKUP_KEEP_DAILY` /
`BACKUP_KEEP_WEEKLY` / `BACKUP_KEEP_MONTHLY` copie (7 / 4 / 6). Se all'avvio l'ultimo backup
riuscito ha più di 24 ore ne fa subito uno. Lo stato è in **Account → Amministrazione**
(ultimo backup, dimensione, copia fuori dal server, avviso se nessun backup è riuscito nelle
ultime 26 ore) e nell'healthcheck del container.

```sh
docker compose exec backup sh /scripts/backup.sh now          # backup immediato
docker compose exec backup ls -R /backups                     # copie presenti
```

## Copia fuori dal server

Consigliata: un backup sullo stesso disco non protegge da un guasto o da un furto del server.
Il servizio `offsite` (profilo `offsite`, immagine `restic`) copia ogni giorno alle
`OFFSITE_TIME` la cartella dei backup in un repository **cifrato** restic (S3, Backblaze B2,
SFTP, un disco di rete...), tiene le stesse copie giornaliere, settimanali e mensili dei
backup locali e verifica a campione i dati già caricati:

```sh
# .env: RESTIC_REPOSITORY (es. s3:https://s3.eu-central-1.amazonaws.com/bucket/car-tracking
#        o sftp:utente@nas:/backup/car-tracking), RESTIC_PASSWORD, chiavi AWS_* / B2_*
docker compose --profile offsite up -d offsite
docker compose run --rm offsite now                          # prima copia subito
```

Per SFTP la chiave SSH va in `secrets/ssh/` (montata in sola lettura). **Conserva
`RESTIC_PASSWORD` e `CRYPTO_MASTER_KEY` in un gestore di password fuori dal server**: senza
la prima il repository non si legge, senza la seconda i tracker non si collegano più al
server ripristinato.

## Ripristino

Verificato: dump e ripristino completo con hypertable e aggregati.

```sh
# Prova su un database separato, senza toccare quello in uso
docker compose exec -e RESTORE_DB=ct_restore backup sh /scripts/backup.sh restore /backups/daily/<file>.dump
# Ripristino vero: ferma il backend, sostituisce il database, riavvia
docker compose stop backend
docker compose exec backup sh /scripts/backup.sh restore /backups/daily/<file>.dump --yes
docker compose start backend
# Da restic, su un altro server: prima recupera i file
docker compose run --rm --entrypoint restic offsite restore latest --target /backups/restored
```
