# Installazione del server

Requisiti: un server Linux con Docker e Docker Compose (amd64 o arm64, anche un Raspberry Pi
4/5), un dominio e, per i tracker, la porta 443 raggiungibile da Internet, inoltrata dal router al server.

## 1. Variabili d'ambiente

Copia `.env.example` in `.env` e sostituisci **tutti** i valori (valori casuali:
`openssl rand -hex 32`, vedi [Generare i segreti](#generare-i-segreti)):

| Variabile | Significato |
| :--- | :--- |
| `DOMAIN` | Dominio pubblico, es. *tracking.mydomain.com*. Le passkey sono legate a questo dominio: cambiarlo significa registrarle di nuovo |
| `POSTGRES_*` | Database, raggiungibile solo dalla rete interna `db` |
| `CRYPTO_MASTER_KEY` | Segreto (min 32 caratteri) da cui derivano le chiavi e i codici di abbinamento dei tracker, e con cui sono cifrati i segreti TOTP. Se cambia, i tracker vanno riprogrammati e le app di autenticazione riconfigurate: **fanne un backup** |
| `RETENTION_DAYS`, `SIM_BUDGET_MB`, `OFFLINE_AFTER_HOURS` | Conservazione dei dati, piano dati della SIM (grafico del traffico), avviso di tracker non raggiungibile |
| `PHONE_RETENTION_DAYS` | Conservazione delle posizioni personali dei telefoni (default 30), più breve di quella dei veicoli |
| `TIMEZONE` | Fuso dei giorni delle statistiche, degli orari delle aree e dei backup |
| `LOG_RETENTION_DAYS`, `LOG_SLOW_REQUEST_MS`, `LOG_SLOW_QUERY_MS` | [Log della piattaforma](logs.md): giorni di conservazione (default 30), soglie di richiesta e query lenta |
| `ANDROID_PACKAGE`, `ANDROID_CERT_SHA256` | Passkey anche nell'app Android (vedi [App](../app/index.md)) |
| `GITHUB_REPO`, `GITHUB_TOKEN` | Firmware e versioni dell'app dalle release del repository (`proprietario/nome`); se il repository cambia nome si aggiorna solo questa variabile. Token opzionale (limite di richieste) |
| `FUEL_PRICES_URL` | Prezzi medi settimanali dei carburanti del MASE; vuoto per disattivarli |
| `MAP_TILE_URL`, `MAP_ATTRIBUTION` | Tasselli della mappa (OpenStreetMap di default, vedi sotto) |
| `CELL_GEOLOCATION_URL` | Posizione stimata dalla cella senza fix GNSS, es. `https://api.beacondb.net/v1/geolocate` |
| `FCM_SERVICE_ACCOUNT_FILE` | Notifiche push Android (Firebase, opzionali) |
| `BACKEND_IMAGE` | Immagine delle release al posto della compilazione locale (vedi [Aggiornamenti](updates.md)) |

I file con segreti (`.env`, `firmware/secrets.h`, `secrets/`, keystore Android) sono esclusi
da git.

!!! note "Mappe"
    L'app usa [flutter_map](https://github.com/fleaflet/flutter_map) (l'equivalente Flutter di
    Leaflet) con i tasselli di OpenStreetMap: nessuna chiave e nessun costo. I server di
    OpenStreetMap sono per un uso leggero ([tile usage policy](https://operations.osmfoundation.org/policies/tiles/)):
    con molti utenti imposta in `MAP_TILE_URL` un fornitore compatibile o un proprio server di
    tasselli. Google Maps richiede invece una chiave API legata a un account di fatturazione.

## Generare i segreti

Valori da creare una volta e conservare in un gestore di password **fuori dal server**.
I valori casuali in esadecimale vanno bene ovunque, anche dentro un URL:

```sh
openssl rand -hex 32      # 64 caratteri esadecimali
```

| Variabile | Come ottenerla |
| :--- | :--- |
| `POSTGRES_PASSWORD` | `openssl rand -hex 32`. Finisce dentro `DATABASE_URL`: evita `/`, `+`, `=` (quindi niente base64). Cambiarla dopo il primo avvio richiede anche `ALTER USER` nel database |
| `CRYPTO_MASTER_KEY` | `openssl rand -hex 32`. **Non cambiarla mai**: da essa derivano le chiavi dei tracker e cifra i segreti TOTP |
| `RESTIC_PASSWORD` | `openssl rand -hex 32` (solo con il profilo `offsite`). Senza di essa la copia fuori dal server non si legge |
| `ACME_EMAIL` | Un tuo indirizzo: Let's Encrypt lo usa per gli avvisi di scadenza |
| `ANDROID_CERT_SHA256` | Impronta del certificato che firma l'APK: `keytool -list -v -keystore car-tracking-release.jks -alias car-tracking`, riga `SHA256:` (es. `AB:CD:...`). Il keystore si crea come descritto in [Release e pipeline](../development/releases.md#firma-dellapk-obbligatori); per più certificati separa con la virgola |
| `GITHUB_REPO` | `proprietario/nome` del repository con le release (es. `mionome/car-tracking`) |
| `GITHUB_TOKEN` | Facoltativo: *Settings → Developer settings → Fine-grained tokens*, accesso *Public repositories (read-only)*, nessun permesso aggiuntivo; con un repository privato *Contents: read* su quel repository |
| `AWS_*` / `B2_*` | Chiavi del bucket per `offsite`: utente IAM con accesso al solo bucket (S3) o *Application Key* limitata al bucket (Backblaze B2) |
| `FCM_SERVICE_ACCOUNT_FILE` | Facoltativo: console Firebase → *Impostazioni progetto → Account di servizio → Genera nuova chiave privata*, salva il JSON in `secrets/fcm.json` |

I segreti della pipeline di GitHub (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) non vanno nel `.env`: vedi
[Release e pipeline](../development/releases.md#segreti-e-variabili).

## 2. Esposizione: una sola porta sul router

Il backend deve essere raggiungibile in HTTPS su un dominio vero: lo richiedono le passkey
(WebAuthn) e il tracker, che si collega in `wss://<dominio>/tracker`.

1. Il dominio (record DNS `A`/`AAAA`) punta all'IP pubblico di casa; con un IP dinamico usa
   un servizio DNS dinamico.
2. Sul router inoltra **solo la porta TCP 443** all'IP del server. La porta 80 serve solo al
   reindirizzamento verso HTTPS e può restare chiusa.
3. Traefik (`--profile traefik`) ottiene il certificato Let's Encrypt con la sfida
   **TLS-ALPN** sulla 443 (TLS 1.2+, `traefik/dynamic.yml`) e lo rinnova da solo.

Esposta c'è solo la 443: il tracker si autentica con la sua chiave a ogni frame, l'app con
passkey o password + TOTP; Traefik e il backend limitano le richieste per indirizzo.

## 3. Avvio

```sh
docker compose --profile traefik up -d --build
docker compose exec backend node scripts/create-admin.ts admin@mydomain.com "Nome"
```

L'immagine compila l'app web Flutter e la serve dallo stesso backend. Le migrazioni del
database vengono applicate all'avvio. `create-admin` stampa un **link di invito**: aprilo,
scegli la password e configura l'app di autenticazione (2FA obbligatoria). Poi aggiungi una
passkey per accedere con impronta o blocco schermo.

Per non compilare sul server usa l'immagine delle release: vedi [Aggiornamenti](updates.md).

`GET /healthz` risponde `200 {"ok": true, "database": true}` solo se il database risponde
entro 3 secondi, altrimenti `503`: lo usano l'healthcheck del container e un eventuale
monitoraggio esterno (es. Uptime Kuma). Finché il database non è raggiungibile (fermo, in
riavvio o in avvio) anche le chiamate alle API rispondono `503` con `Retry-After: 10` e la app
mostra *Servizio momentaneamente non disponibile*; il backend si ricollega da solo appena il
database torna, senza riavvii.

## 4. Utenti e accesso

- Nessuna registrazione pubblica: l'amministratore invita gli utenti da
  **Account → Amministrazione** e manda il link (valido 72 ore, monouso). Non serve un server
  email.
- Accesso con **passkey** (impronta/volto, anche sincronizzate su Google/Apple) oppure
  **password + TOTP**. La 2FA è obbligatoria.
- 10 **codici di recupero** monouso; se si perdono telefono e codici, l'amministratore genera
  un link di ripristino (nuova password e nuova 2FA).
- Le modifiche sensibili (password, passkey, codici, app TOTP) richiedono di nuovo il codice
  TOTP se l'accesso risale a più di 15 minuti.
- Ogni utente vede solo i propri dispositivi e quelli condivisi con lui. L'amministratore
  gestisce gli utenti ma non vede i loro dispositivi.
- **Lingua**: italiano e inglese, scelta dal telefono o dal browser al primo accesso e salvata
  nell'account; le notifiche push arrivano nella lingua dell'utente.

## 5. Primo tracker

Il provisioning (chiave del tracker, etichetta con QR code) è descritto in
[Firmware](../firmware/index.md#provisioning). L'utente aggiunge poi il tracker da
**Dispositivi → Aggiungi** con la procedura guidata.
