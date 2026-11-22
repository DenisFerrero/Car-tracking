# Aggiornamenti del server

A ogni release pubblicata su GitHub la pipeline (`.github/workflows/release.yml`) costruisce
l'immagine del backend, con l'app web inclusa, per **amd64 e arm64** e la pubblica sul GitHub
Container Registry:

```text
ghcr.io/<proprietario>/<repository>:2.5.0   versione esatta
ghcr.io/<proprietario>/<repository>:2.5     ultima patch della 2.5
ghcr.io/<proprietario>/<repository>:2       ultima versione della 2.x
ghcr.io/<proprietario>/<repository>:latest  ultima release
```

## Usare l'immagine delle release

Nel `.env` del server:

```sh
BACKEND_IMAGE=ghcr.io/<proprietario>/<repository>:2
```

```sh
docker compose pull backend
docker compose --profile traefik up -d      # senza --build
```

Fissa la **versione maggiore** (`:2`), non `latest`: le versioni minori e le patch restano
compatibili, un cambio di versione maggiore (es. un passaggio di TimescaleDB o un cambio di
configurazione) va letto nelle note di rilascio e applicato a mano.

!!! warning "Visibilità del pacchetto"
    Al primo push GitHub crea il pacchetto `ghcr.io/<proprietario>/<repository>` come privato.
    Per scaricarlo senza credenziali rendilo pubblico una volta da **Packages → il pacchetto →
    Package settings → Change visibility**. In alternativa sul server
    `docker login ghcr.io` con un token con il solo permesso `read:packages`.

## Aggiornamento automatico con Watchtower

Il profilo `autoupdate` aggiunge [Watchtower](https://github.com/nicholas-fedor/watchtower)
(il fork mantenuto: il progetto originale `containrrr/watchtower` è archiviato da dicembre
2025):

```sh
docker compose --profile traefik --profile autoupdate up -d
```

- Ogni notte alle 4:00 (`WATCHTOWER_SCHEDULE`, formato cron con i secondi) controlla il tag di
  `BACKEND_IMAGE`; se è cambiato scarica la nuova immagine, ricrea **solo il backend** (unico
  container con l'etichetta `com.centurylinklabs.watchtower.enable`) e cancella la vecchia.
- L'orario viene dopo il backup giornaliero delle 3:30 (`BACKUP_TIME`): c'è sempre un dump del
  database precedente all'aggiornamento.
- Le migrazioni del database girano all'avvio del nuovo container.
- `WATCHTOWER_NOTIFICATION_URL` (formato [shoutrrr](https://shoutrrr.nickfedor.com/):
  `telegram://`, `ntfy://`, `smtp://`...) manda un resoconto di ogni aggiornamento.

### Valutazione

| Aspetto | Valutazione |
| :--- | :--- |
| Affidabilità | Buona per un'istanza personale: confronta il digest del tag e ricrea il container con la stessa configurazione di Compose |
| Rischi | Accesso al socket Docker (equivale a root sul server: usa l'immagine ufficiale con versione fissata); nessun rollback automatico se il nuovo backend non parte |
| Mitigazioni | Tag della versione maggiore, backup prima dell'aggiornamento, notifiche, release pubblicate solo dopo i test della pipeline |
| Limiti di GitHub Free | Nessuno per i repository pubblici: i pacchetti pubblici di GHCR non hanno limiti di spazio né di traffico, i runner Linux (anche arm64) sono gratuiti. Con un repository privato GHCR conta spazio e traffico sulla quota gratuita (500 MB) |

### Tornare alla versione precedente

```sh
# .env: BACKEND_IMAGE=ghcr.io/<proprietario>/<repository>:2.4.1
docker compose up -d backend
```

Se la nuova versione ha applicato migrazioni non compatibili con quella vecchia, ripristina
anche il backup della notte (vedi [Backup](backup.md#ripristino)).

## Firmware e app

Gli aggiornamenti dei tracker e dell'app Android non passano da qui: il backend legge le
release di `GITHUB_REPO` (vedi [Firmware](../firmware/index.md#aggiornamento-a-distanza-ota) e
[App](../app/index.md#aggiornamenti)).
