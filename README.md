# Car tracking

Localizzatore GPS per auto basato su ESP32 con piattaforma multi-utente per la posizione in
tempo reale, lo storico, i costi dei viaggi, le scadenze del veicolo e l'antifurto. App web e
Android dallo stesso codice Flutter. Tutto open source, senza servizi a pagamento (mappe
OpenStreetMap).

*GPS tracker for cars based on the ESP32, with a multi-user platform, Android and web app.
The documentation is in Italian and English.*

```text
[Tracker ESP32] --wss /tracker (frame binari cifrati)--+
[Telefono Android] --HTTPS (posizioni del telefono)-----+
                                                        v
[App Android / Browser] --HTTPS + WebSocket--> [Traefik, porta 443] --> [backend Node.js] --> [TimescaleDB]
```

## Documentazione

La documentazione completa è pubblicata su GitHub Pages dalla cartella [`docs/`](docs/index.md)
(sorgente in Markdown, leggibile anche qui su GitHub):

| Sezione | Contenuto |
| :--- | :--- |
| [Installazione del server](docs/server/install.md) | Variabili d'ambiente, esposizione con una sola porta (Traefik), avvio, utenti |
| [Aggiornamenti](docs/server/updates.md) | Immagine delle release su GHCR, aggiornamento automatico con Watchtower, ritorno alla versione precedente |
| [Backup](docs/server/backup.md) | Backup giornalieri, copia cifrata fuori dal server, ripristino |
| [App](docs/app/index.md) | Installazione Android, store alternativi, aggiornamenti, [funzioni](docs/app/features.md) |
| [Telefono e veicoli](docs/app/phone-vehicles.md) | Il telefono come localizzatore, veicoli senza tracker |
| [Dashboard](docs/app/dashboards.md) | Dashboard personalizzate, dashboard corrente, condivisione del layout con gli amici |
| [Dispositivi](docs/devices/index.md) | Catalogo delle schede supportate, distinte, collegamenti, accessori |
| [Firmware](docs/firmware/index.md) | Configurazione, provisioning, aggiornamenti a distanza, antifurto |
| [Riferimento](docs/reference/protocol.md) | Protocollo binario, [sicurezza](docs/reference/security.md), [consumo dati SIM](docs/reference/data-usage.md) |
| [Sviluppo](docs/development/index.md) | Ambiente locale, test, [release e segreti della pipeline](docs/development/releases.md) |

## Avvio rapido

```sh
cp .env.example .env        # e sostituisci tutti i valori
docker compose --profile traefik up -d --build
docker compose exec backend node scripts/create-admin.ts admin@mydomain.com "Nome"
```

## Repository

| Cartella | Contenuto |
| :--- | :--- |
| `firmware/` | Firmware Arduino del tracker (ESP32 + modem SIMCom A76xx) |
| `backend/` | Node.js 24 + TypeScript (Fastify): API, autenticazione, realtime, gateway dei tracker |
| `app/` | App Flutter Android e web |
| `hardware/` | Distinta della scheda di alimentazione, portachiavi del proprietario |
| `docs/`, `mkdocs.yml` | Documentazione (GitHub Pages) |
| `docker-compose.yml`, `traefik/`, `backup/` | Stack di produzione |

Le regole per chi contribuisce (anche con assistenti AI) sono in [`CLAUDE.md`](CLAUDE.md).
