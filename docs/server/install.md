# Installazione del server

Requisiti: un server Linux con Docker e Docker Compose (amd64 o arm64, anche un Raspberry Pi
4/5), un dominio e, per i tracker, la porta 443 raggiungibile da Internet (o un Cloudflare
Tunnel).

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
| `CF_DNS_API_TOKEN` | Solo con `letsencrypt-dns` e Cloudflare: *My Profile → API Tokens → Create Token → Edit zone DNS*, limitato alla zona del dominio |
| `CLOUDFLARE_TUNNEL_TOKEN` | Solo con il profilo `tunnel`: *Zero Trust → Networks → Tunnels → Create a tunnel* (tipo Cloudflared), il token è nel comando di installazione mostrato (`--token ...`) |
| `ANDROID_CERT_SHA256` | Impronta del certificato che firma l'APK: `keytool -list -v -keystore car-tracking-release.jks -alias car-tracking`, riga `SHA256:` (es. `AB:CD:...`). Il keystore si crea come descritto in [Release e pipeline](../development/releases.md#firma-dellapk-obbligatori); per più certificati separa con la virgola |
| `GITHUB_REPO` | `proprietario/nome` del repository con le release (es. `mionome/car-tracking`) |
| `GITHUB_TOKEN` | Facoltativo: *Settings → Developer settings → Fine-grained tokens*, accesso *Public repositories (read-only)*, nessun permesso aggiuntivo; con un repository privato *Contents: read* su quel repository |
| `AWS_*` / `B2_*` | Chiavi del bucket per `offsite`: utente IAM con accesso al solo bucket (S3) o *Application Key* limitata al bucket (Backblaze B2) |
| `FCM_SERVICE_ACCOUNT_FILE` | Facoltativo: console Firebase → *Impostazioni progetto → Account di servizio → Genera nuova chiave privata*, salva il JSON in `secrets/fcm.json` |

I segreti della pipeline di GitHub (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) non vanno nel `.env`: vedi
[Release e pipeline](../development/releases.md#segreti-e-variabili).

## 2. Esposizione

Il backend deve essere raggiungibile in HTTPS su un dominio vero: lo richiedono le passkey
(WebAuthn) e il tracker, che si collega in `wss://<dominio>/tracker`.

- **Traefik** (`--profile traefik`): server con le porte 80/443 aperte, certificati
  Let's Encrypt automatici (TLS 1.2+, `traefik/dynamic.yml`). Con
  `TRAEFIK_CERTRESOLVER=letsencrypt-dns` il certificato si ottiene con la sfida DNS
  (`ACME_DNS_PROVIDER`, ad esempio Cloudflare con `CF_DNS_API_TOKEN`): serve se la porta 80
  non è raggiungibile da Internet.
- **Cloudflare Tunnel** (`--profile tunnel`): nessuna porta aperta. Nel pannello Cloudflare
  crea il tunnel, metti il token in `CLOUDFLARE_TUNNEL_TOKEN` e aggiungi la *public hostname*
  `DOMAIN` → `http://backend:4000`. Il tracker verifica le CA di `firmware/certificates.h`,
  che includono quelle usate da Cloudflare.
- **VPN** (NetBird o simili): va bene per l'app e il browser, ma il tracker non può entrare
  nella VPN, quindi almeno `/tracker` deve restare pubblico. Soluzione tipica: Traefik con
  sfida DNS e porta 443 aperta.

## 3. Avvio

```sh
docker compose --profile traefik up -d --build     # oppure --profile tunnel
docker compose exec backend node scripts/create-admin.ts admin@mydomain.com "Nome"
```

L'immagine compila l'app web Flutter e la serve dallo stesso backend. Le migrazioni del
database vengono applicate all'avvio. `create-admin` stampa un **link di invito**: aprilo,
scegli la password e configura l'app di autenticazione (2FA obbligatoria). Poi aggiungi una
passkey per accedere con impronta o blocco schermo.

Per non compilare sul server usa l'immagine delle release: vedi [Aggiornamenti](updates.md).

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
