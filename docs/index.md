# Car Tracking

Localizzatore GPS per auto basato su ESP32 con piattaforma multi-utente per la posizione in
tempo reale, lo storico, i costi dei viaggi, le scadenze del veicolo e l'antifurto. App web e
Android dallo stesso codice Flutter. Tutto open source, senza servizi a pagamento: mappe
OpenStreetMap, nessun token Google.

```text
[Tracker ESP32] --wss /tracker (frame binari cifrati)--+
[Telefono Android] --HTTPS (posizioni del telefono)-----+
                                                        v
[App Android / Browser] --HTTPS + WebSocket--> [Traefik, porta 443] --> [backend Node.js] --> [TimescaleDB]
                                                                                 API REST, realtime,
                                                                                 gateway dei tracker,
                                                                                 app web, push FCM
```

## Cosa fa

- **Tracker hardware** ([dispositivi](devices/index.md)): GPS e LTE, campionamento adattivo,
  coda offline, antifurto con accelerometro, risveglio dal sotto chiave, aggiornamenti a
  distanza (anche automatici).
- **Telefono come localizzatore** ([telefono e veicoli](app/phone-vehicles.md)): senza
  hardware, il telefono condivide la posizione della persona oppure quella di un **veicolo**
  dell'utente, che ha viaggi, costi, contachilometri e scadenze come un tracker.
- **Piattaforma**: utenti invitati dall'amministratore (nessuna registrazione pubblica),
  passkey o password + TOTP, amici e condivisioni temporanee, aree di arrivo, notifiche push.
- **Analisi** ([funzioni](app/features.md)): viaggi, registro viaggi per i rimborsi, costi con
  storico di prezzo, consumo e usura, prezzo medio nazionale dei carburanti, statistiche nel
  tempo, scadenze (tagliando, revisione, assicurazione, bollo).

## Componenti del repository

| Cartella | Contenuto |
| :--- | :--- |
| `firmware/` | Firmware Arduino del tracker (ESP32 + modem SIMCom A76xx) |
| `backend/` | Node.js 24 + TypeScript (Fastify): API, autenticazione, realtime, gateway dei tracker |
| `app/` | App Flutter Android e web |
| `hardware/` | Distinta della scheda di alimentazione, portachiavi del proprietario |
| `docs/` | Questa documentazione (GitHub Pages) |
| `docker-compose.yml`, `traefik/`, `backup/` | Stack di produzione |

Un solo container applicativo più il database: niente broker, proxy di autenticazione o
Redis separati.

## Da dove cominciare

1. [Installa il server](server/install.md) con Docker Compose.
2. [Scegli e monta un dispositivo](devices/index.md), oppure usa solo il telefono.
3. [Installa l'app](app/index.md) Android (APK delle release, Obtainium) o usa quella web.
