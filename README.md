# Car tracking

Localizzatore GPS per auto basato su ESP32 (LilyGO T-Call A7670) con piattaforma
multi-utente per la posizione in tempo reale, lo storico, l'analisi dei dati e
l'antifurto. App web e Android dallo stesso codice Flutter.

```text
[Tracker ESP32] --wss /tracker (frame binari cifrati)-+
                                                    v
[App Android / Browser] --HTTPS + WebSocket--> [Traefik o Cloudflare Tunnel] --> [backend Node.js] --> [TimescaleDB]
                                                                                  API REST, realtime,
                                                                                  gateway dei tracker,
                                                                                  app web, push FCM
```

- **firmware/**: firmware Arduino del tracker (GPS, sensori, antifurto, coda offline)
- **backend/**: Node.js 24 + TypeScript (Fastify): API, autenticazione, WebSocket
  realtime, gateway WebSocket dei tracker, notifiche push
- **app/**: app Flutter (Android e web): mappa realtime, storico, analisi, procedura
  guidata per aggiungere un tracker, gestione utenti
- **docker-compose.yml**, **traefik/**: stack di produzione

Un solo container applicativo più il database: niente broker, proxy di
autenticazione o Redis separati.

---

## 🚀 Produzione

### 1. Variabili d'ambiente

Copia `.env.example` in `.env` e sostituisci **tutti** i valori (valori casuali:
`openssl rand -base64 32`):

- **DOMAIN**: dominio pubblico, ad esempio *tracking.mydomain.com*. Le passkey sono
  legate a questo dominio: cambiarlo significa registrarle di nuovo
- **POSTGRES_\***: database, raggiungibile solo dalla rete interna `db`
- **CRYPTO_MASTER_KEY**: segreto (min 32 caratteri) da cui derivano chiavi, password del
  e codici di abbinamento dei tracker, e con cui sono cifrati i segreti TOTP.
  Se cambia, i tracker vanno riprogrammati e le app di autenticazione riconfigurate:
  **fanne un backup**
- **RETENTION_DAYS**, **SIM_BUDGET_MB**, **OFFLINE_AFTER_HOURS**: conservazione dei dati,
  piano dati della SIM (grafico del traffico), avviso di tracker non raggiungibile
- **PHONE_RETENTION_DAYS** (default 30): conservazione delle posizioni dei telefoni,
  più breve di quella dei tracker (dati personali)
- **ANDROID_PACKAGE** / **ANDROID_CERT_SHA256**: per usare le passkey anche nell'app
  (vedi *App Android*)
- **GITHUB_REPO** (es. *utente/car-tracking*, opzionale) e **GITHUB_TOKEN**: firmware e
  versioni dell'app dalle release del repository (vedi *Aggiornamento a distanza*); se il
  repository cambia nome si aggiorna solo questa variabile
- **FUEL_PRICES_URL**: prezzi medi settimanali dei carburanti del MASE per i costi dei
  viaggi (vuoto per disattivarli)

I file con segreti (`.env`, `firmware/secrets.h`, `secrets/`, keystore Android) sono
esclusi da git. I vecchi `.env`, `mosquitto/config/passwd` e `nginx/.htpasswd` erano
stati committati: **ruota quei valori**, restano nella cronologia del repository.

### 2. Esposizione

Il backend deve essere raggiungibile in HTTPS su un dominio vero: lo richiedono le
passkey (WebAuthn) e il tracker, che si collega in `wss://<dominio>/tracker`.

- **Traefik** (`--profile traefik`): server con le porte 80/443 aperte, certificati
  Let's Encrypt automatici (TLS 1.2+, `traefik/dynamic.yml`). Con
  `TRAEFIK_CERTRESOLVER=letsencrypt-dns` il certificato si ottiene con la sfida DNS
  (`ACME_DNS_PROVIDER`, ad esempio Cloudflare con `CF_DNS_API_TOKEN`): serve se la
  porta 80 non è raggiungibile da Internet.
- **Cloudflare Tunnel** (`--profile tunnel`): nessuna porta aperta. Nel pannello
  Cloudflare crea il tunnel, metti il token in `CLOUDFLARE_TUNNEL_TOKEN` e aggiungi
  la *public hostname* `DOMAIN` → `http://backend:4000`. Il tracker verifica le CA di
  `firmware/certificates.h`, che includono quelle usate da Cloudflare.
- **NetBird** (o altra VPN): va bene per l'app e il browser, ma il tracker non può
  entrare nella VPN, quindi almeno `/tracker` deve restare pubblico. Soluzione tipica:
  Traefik con sfida DNS sul server e porta 443 aperta. Le passkey funzionano anche con
  un dominio che risolve su un IP privato della VPN, purché il certificato sia valido
  (sfida DNS).

### 3. Avvio

```sh
docker compose --profile traefik up -d --build     # oppure --profile tunnel
docker compose exec backend node scripts/create-admin.ts admin@mydomain.com "Nome"
```

L'immagine compila l'app web Flutter e la serve dallo stesso backend. Le migrazioni del
database vengono applicate all'avvio. `create-admin` stampa un **link di invito**:
aprilo, scegli la password e configura l'app di autenticazione (2FA obbligatoria).
Poi aggiungi una passkey per accedere con impronta o blocco schermo.

### 4. Utenti e accesso

- Nessuna registrazione pubblica: l'amministratore invita gli utenti da
  **Account → Amministrazione** e manda il link (valido 72 ore, monouso). Non serve un
  server email.
- Accesso con **passkey** (impronta/volto, anche sincronizzate su Google/Apple) oppure
  **password + TOTP**. La 2FA è obbligatoria: senza TOTP configurato non si entra.
- 10 **codici di recupero** monouso; se si perdono telefono e codici, l'amministratore
  genera un link di ripristino (nuova password e nuova 2FA).
- Le modifiche sensibili (password, passkey, codici, app TOTP) richiedono di nuovo il
  codice TOTP se l'accesso risale a più di 15 minuti.
- Ogni utente vede solo i propri dispositivi e quelli condivisi con lui (ruoli
  *proprietario* / *solo visione*). L'amministratore gestisce gli utenti ma non vede i
  loro dispositivi.
- **Amici** (**Account → Amici**): gli utenti non si vedono tra loro. Ognuno ha un codice
  personale (`ABCDE-FGHJK`, anche come QR code): chi lo inserisce o lo inquadra invia una
  **richiesta di amicizia**, che l'altro accetta o rifiuta (notifica in tempo reale; il
  rifiuto non viene comunicato, chi ha inviato può ritirarla). Due richieste incrociate
  diventano subito amicizia; al massimo 20 richieste in sospeso. Il codice si può
  rigenerare (il vecchio smette di funzionare, gli amici restano); rimuovere un amico
  chiude le condivisioni tra i due, in entrambe le direzioni.
- **I tuoi dati** (**Account**): *Esporta i miei dati* scarica un JSON con profilo,
  accessi, amici, dispositivi con posizioni, aree e notifiche. *Elimina account* chiede di
  riscrivere l'email (e il codice TOTP se l'accesso è vecchio): elimina telefoni,
  posizioni, condivisioni, amici, aree e notifiche; i tracker tornano liberi e si
  riabbinano con il codice dell'etichetta. L'ultimo amministratore non può eliminarsi.
- **Condivisione** (*Impostazioni* del dispositivo → *Condivisione*): il proprietario
  condivide in sola visione con un amico, per sempre o fino a
  una data e ora (scelte rapide 1 h, 3 h, 8 h, 24 h, 3 giorni, 7 giorni, oppure data e
  ora a piacere). Può cambiare la scadenza o revocare in ogni momento; chi riceve può
  rinunciare. Alla revoca o alla scadenza la schermata del dispositivo si chiude subito
  (evento realtime). Chi riceve vede solo nome, posizione, stato (in movimento /
  fermo), velocità, ultimo contatto, nome del proprietario e scadenza: niente IMEI,
  segnale, batteria, eventi d'allarme, storico precedente alla condivisione, analisi o
  comandi, e non attiva la modalità live del tracker (nessun consumo extra sulla SIM).
- **Aree di arrivo** (scheda *Aree*): ogni utente, proprietario o destinatario di una
  condivisione, imposta una o più aree circolari (centro scelto sulla mappa, raggio da
  50 m a 50 km) e riceve una notifica quando il dispositivo entra (e, se vuole, quando
  esce). Le aree sono personali: gli altri utenti non le vedono. Un'area può avvisare
  **solo in certi orari** (giorni della settimana e fascia oraria nel fuso `TIMEZONE`; se la
  fine è prima dell'inizio la fascia passa la mezzanotte, es. 23:00-6:00 per «avvisami se
  l'auto esce dal garage di notte»): fuori fascia lo stato dentro/fuori viene seguito ma
  non notificato.
- **Avvisi personali**, scelti da ogni utente per ogni dispositivo che vede (il proprietario
  da *Impostazioni*, chi riceve una condivisione dal menu ⋮ del dispositivo):
  - **Sosta prolungata**: avviso se il dispositivo resta fermo più di 1-48 ore **fuori dalle
    aree di quell'utente** (disattivato di default). Una notifica per sosta; non scatta se il
    tracker è già segnalato come non raggiungibile o se il telefono è in pausa o non invia
    da 30 minuti (controllo ogni 10 minuti).
  - **Batteria bassa** di un telefono condiviso: soglia 10-50% (default 20%) o disattivato.
    Una notifica per scarica: la successiva dopo una ricarica di 10 punti sopra la soglia.
    Il proprietario del telefono non la riceve.
- **Avvisi dell'auto** (proprietario del tracker, attivabili come le altre notifiche):
  - **Salute della batteria**: ogni giorno si calcola la tensione mediana a motore spento
    da almeno 2 ore (senza la carica superficiale dell'alternatore). Media degli ultimi 7
    giorni: ≥ 12,4 V buona, 12,2-12,4 V da tenere d'occhio, < 12,2 V debole (avviso, al
    massimo ogni 14 giorni). Le statistiche mostrano anche l'andamento in V al mese.
  - **Scadenze**: tagliando e gomme a km, revisione, assicurazione e bollo a data (o
    entrambi), oppure **personalizzate** con una descrizione (bollino blu, estintore...),
    ricorrenti o una tantum; avviso quando mancano `remind` giorni / km e alla scadenza.
- **Lingua**: italiano e inglese. Al primo accesso l'app usa la lingua del telefono o del
  browser (inglese se non è una delle due) e la salva nell'account; si cambia da
  **Account → Lingua**. Le notifiche push arrivano nella lingua dell'utente.

### 5. Provisioning di un tracker

Ogni tracker ha una chiave propria, derivata da `CRYPTO_MASTER_KEY` e dal suo IMEI
(stampato sul modulo o mostrato sulla seriale all'avvio):

```sh
docker compose exec backend node scripts/provision.ts 863820040182648 --label /tmp/label.svg
```

```text
IMEI:          863820040182648
Pairing code:  7KQ2-M9XA
QR code:       CT1:863820040182648:7KQ2M9XA

firmware/secrets.h:
#define DEVICE_KEY "3f9a..."
```

1. Copia `firmware/secrets.example.h` in `firmware/secrets.h` e inserisci
   `DEVICE_KEY` e APN. Non serve registrare nulla sul server: il backend ricalcola la
   chiave dall'IMEI.
2. Regola `firmware/configurations.h` (scheda, `SERVER_HOST` = `DOMAIN`, porta 443,
   campionamento) e programma la scheda (*ESP32 Dev Module*). Per la scheda
   reale commenta `COMPILING_WITH_STANDARD_TINYGSM` e usa la libreria TinyGSM di
   [LilyGO](https://github.com/Xinyuan-LilyGO/LilyGO-T-A76XX/tree/main/lib/TinyGSM).
3. Stampa l'etichetta (`--label`, SVG con QR code, IMEI e codice) e applicala al
   tracker o alla scatola.
4. L'utente apre **Dispositivi → Aggiungi** nell'app: la **procedura guidata** legge il
   QR (o IMEI e codice a mano), chiede nome e colore, poi attende in tempo reale il
   primo collegamento del tracker. Il codice dimostra il possesso fisico: conoscere
   solo l'IMEI non basta.

Al primo avvio il firmware salva `DEVICE_KEY` nella memoria NVS: gli aggiornamenti a
distanza, compilati senza chiave, la riprendono da lì.

### 6. Aggiornamento a distanza (OTA)

**Dalle release di GitHub (consigliato)**: con `GITHUB_REPO=<proprietario>/<repository>`
nel `.env` il backend legge ogni 6 ore l'ultima release del repository (il nome viene
dalla variabile: se il repository cambia nome basta aggiornarla). Le immagini
`firmware-<variante>.bin` allegate da `.github/workflows/release.yml` entrano fra gli
aggiornamenti disponibili (verificate con lo SHA-256 calcolato da GitHub) e i proprietari
dei tracker di quella variante ricevono la notifica *Nuovo firmware*. Controllo immediato:
`POST /api/admin/releases/check` (amministratore).

**Immagini pubbliche senza credenziali**: le immagini delle release sono compilate con
`SERVER_HOST ""` e senza chiave, WiFi o APN (`firmware/release/`). Il tracker salva in NVS
la chiave e le impostazioni di rete (server, WiFi, APN, PIN) della prima installazione fatta
con il proprio `secrets.h` e le riusa con queste immagini (`firmware/settings.cpp`). La
prima installazione resta quindi via USB con una build personale che riporta la stessa
variante (`FIRMWARE_VARIANT "lilygo-sim"` o `"lilygo-wifi-sim"`); da lì in poi bastano
le release.

**Aggiornamenti automatici**: le build con `AUTO_UPDATE 1` (le immagini ufficiali) una
volta al giorno, dopo l'ACK, mandano un frame `UPDATE_CHECK` (~100 B sulla rete, ~3 KB al
mese): se il proprietario non li ha disattivati (*Impostazioni → Aggiornamenti automatici*)
il server offre la versione più recente della variante e il tracker la installa da solo
(~1,3 MB di SIM per aggiornamento, circa lo 0,7% di 200 MB). Un'immagine che ha già fallito
su quel tracker (rollback, hash errato) non viene riproposta. **Firmware personalizzati**:
lasciano `AUTO_UPDATE 0` in `configurations.h` e non chiedono mai aggiornamenti, così una
versione modificata non viene sostituita da quella ufficiale; l'installazione manuale resta
possibile.

**A mano, senza GitHub**:

1. Compila il firmware con `DEVICE_KEY` tutta a zero (`0000...`, 64 cifre), la nuova
   `FIRMWARE_VERSION` e la `FIRMWARE_VARIANT` dei tracker (`default` se non cambiata),
   con uno schema di partizioni con due slot OTA (quello predefinito o `min_spiffs`).
   L'immagine non contiene segreti del singolo tracker.
2. Caricala sul server:
   ```sh
   docker compose cp build/firmware.ino.bin backend:/tmp/fw.bin
   docker compose exec backend node scripts/firmware.ts /tmp/fw.bin 2.4.0 default "Note"
   ```
3. Il proprietario apre *Impostazioni* del tracker → *Installa*. Alla connessione
   successiva il tracker riceve l'offerta (firmata con la sua chiave), scarica
   l'immagine a blocchi da 1 KB (~1,2-1,5 MB di SIM), verifica lo SHA-256, la scrive
   nello slot libero e si riavvia. Il nuovo firmware diventa definitivo solo al primo
   ACK del server: se non riesce a collegarsi il bootloader torna alla versione
   precedente (stato *non applicato*). Avanzamento in tempo reale nell'app; si può
   annullare finché il download non è finito. Le immagini si eliminano da
   **Account → Amministrazione**.
4. Il download dura al massimo `OTA_MAX_SEC` (15 minuti) per ciclo e riprende dal punto
   raggiunto alla connessione successiva.

**TLS**: il tracker si collega in `wss://` sulla porta 443 e verifica il certificato
con le CA radice di `firmware/certificates.h` (Let's Encrypt, Google Trust Services,
SSL.com). Il file si rigenera con `npm run ca-bundle` (cartella `backend`).

**Schede supportate**: il codice comune usa solo l'interfaccia del modem
(`firmware/modem.h`) e le macro `BOARD_*` della scheda scelta con `BOARD` in
`configurations.h`. Oggi c'è il **LilyGO T-Call A7670 V1.0** (`boards/lilygo_t_call_a7670_v1_0.h`,
driver `modem_a76xx.cpp`, solo 4G con `MODEM_LTE_ONLY`). Una nuova scheda richiede un
file in `firmware/boards/` e la sua riga in `firmware/board.h`; un modem di un'altra
famiglia anche un `modem_<famiglia>.cpp`. La V1.1 del T-Call ha pin diversi e richiede
un proprio file.

### 7. Backup del database

Il servizio `backup` (stessa immagine TimescaleDB, nessun container in più da scaricare)
fa ogni giorno alle `BACKUP_TIME` (fuso `TIMEZONE`) un `pg_dump` compresso, lo verifica
rileggendone l'indice e lo mette in `volumes/backups/daily/`; il lunedì una copia va in
`weekly/`, il primo del mese in `monthly/`. Si tengono `BACKUP_KEEP_DAILY` /
`BACKUP_KEEP_WEEKLY` / `BACKUP_KEEP_MONTHLY` copie (7 / 4 / 6). Se all'avvio l'ultimo
backup riuscito ha più di 24 ore ne fa subito uno. Lo stato è in
**Account → Amministrazione** (ultimo backup, dimensione, copia fuori dal server, avviso
se nessun backup è riuscito nelle ultime 26 ore) e nell'healthcheck del container.

```sh
docker compose exec backup sh /scripts/backup.sh now          # backup immediato
docker compose exec backup ls -R /backups                     # copie presenti
```

**Copia fuori dal server** (consigliata: un backup sullo stesso disco non protegge da un
guasto o da un furto del server). Il servizio `offsite` (profilo `offsite`, immagine
`restic`) copia ogni giorno alle `OFFSITE_TIME` la cartella dei backup in un repository
**cifrato** restic (S3, Backblaze B2, SFTP, un disco di rete...), tiene le stesse copie
giornaliere, settimanali e mensili dei backup locali e verifica a campione i dati già
caricati:

```sh
# .env: RESTIC_REPOSITORY (es. s3:https://s3.eu-central-1.amazonaws.com/bucket/car-tracking
#        o sftp:utente@nas:/backup/car-tracking), RESTIC_PASSWORD, chiavi AWS_* / B2_*
docker compose --profile offsite up -d offsite
docker compose run --rm offsite now                          # prima copia subito
```

Per SFTP la chiave SSH va in `secrets/ssh/` (montata in sola lettura). **Conserva
`RESTIC_PASSWORD` e `CRYPTO_MASTER_KEY` in un gestore di password fuori dal server**:
senza la prima il repository non si legge, senza la seconda i tracker non si collegano
più al server ripristinato.

**Ripristino** (verificato: dump e ripristino completo con hypertable e aggregati):

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

---

## 📱 App Android

```sh
cd app
flutter build apk --release --dart-define=API_URL=https://tracking.mydomain.com   # opzionale
```

Senza `API_URL` l'app chiede l'indirizzo del server al primo avvio. Requisiti e note:

- **Android 9+** (minSdk 28, richiesto dal Credential Manager delle passkey).
- **Firma**: crea un keystore e `android/key.properties` (`storeFile`, `storePassword`,
  `keyAlias`, `keyPassword`; escluso da git). Senza, la release è firmata con la chiave
  di debug.
- **Passkey nell'app**: imposta `ANDROID_CERT_SHA256` con l'impronta SHA-256 del
  certificato di firma (`keytool -list -v -keystore <keystore>`). Il backend pubblica
  `/.well-known/assetlinks.json` e accetta l'origine `android:apk-key-hash:` dell'app.
- **Notifiche push** (al posto di Telegram), opzionali: crea un progetto Firebase con
  un'app Android `com.cartracking.app`, salva il service account in `secrets/fcm.json`,
  imposta `FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json` e compila l'app con
  `--dart-define=FIREBASE_API_KEY=...`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
  `FIREBASE_PROJECT_ID` (non serve `google-services.json`). Senza Firebase le
  notifiche arrivano solo con l'app aperta.
- **Aggiornamenti dell'app**: l'APK allegato alle release (`car-tracking-<versione>.apk`,
  compilato con `--dart-define=APP_VERSION`) viene letto dal backend insieme al firmware;
  l'app Android confronta la sua versione con l'ultima release e mostra un banner con
  *Scarica* (una volta per versione, *Più tardi* lo nasconde). L'app web è servita dal
  backend ed è sempre aggiornata.
- **Store alternativi** (Obtainium, GitHub Store e simili): leggono le release di un
  repository **pubblico** e propongono l'APK allegato. Bastano la pipeline di release e:
  tag `vX.Y.Z` con `versionCode` crescente (la pipeline lo ricava dal tag:
  `MAJOR×10000 + MINOR×100 + PATCH`), una release non *draft* e non *pre-release* con un
  solo `.apk` fra gli allegati (i `.bin` del firmware vengono ignorati), e **sempre la stessa
  chiave di firma** (segreti `ANDROID_KEYSTORE_*`): con una chiave diversa Android rifiuta
  l'aggiornamento e le passkey dell'app smettono di funzionare. In Obtainium si aggiunge
  l'URL del repository; GitHub Store elenca da solo i repository pubblici con un APK
  nell'ultima release (descrizione e *topic* del repository aiutano a trovarlo).
- **Web**: `app/web/passkeys_bundle.js` è il `bundle.js` del pacchetto `passkeys_web`
  2.11.0, compilato dal suo sorgente (`javascript/`, `npm ci && rollup -c`): va
  ricompilato se si aggiorna il pacchetto.

### Schermate

- **Mappa**: tutti i dispositivi visibili (propri e condivisi) con l'ultima posizione,
  aggiornata in tempo reale. Filtri: miei / condivisi con me, proprietario, in movimento /
  fermi / non raggiungibili (tracker silenzioso oltre `OFFLINE_AFTER_HOURS`, telefono che
  ha smesso di condividere), tracker / telefoni, ricerca per nome; contatore dei
  dispositivi mostrati e pulsante per inquadrare quelli filtrati. I dispositivi vicini si
  raggruppano con il numero: il tocco ingrandisce, oppure elenca quelli nello stesso punto.
- **Questo telefono** (*Dispositivi → Aggiungi → Questo telefono*): senza hardware, il
  telefono condivide la propria posizione e diventa un dispositivo come gli altri
  (condivisione con gli amici, aree di arrivo, storico), anche se l'utente ha già dei
  tracker. Dati più poveri di un tracker: posizione, precisione, velocità e altitudine,
  niente satelliti, segnale, batteria, allarmi o comandi. Solo nell'app Android (il
  browser non può inviare la posizione in background): un servizio in primo piano con
  notifica fissa, in un isolate separato, continua anche con l'app chiusa dalle app
  recenti; con la posizione consentita «Sempre» riparte da solo dopo un riavvio o un
  aggiornamento dell'app. Un punto ogni 15 s o 20 m, da fermo l'ultima posizione ogni 5
  minuti. Invia anche il livello della batteria del telefono (visibile agli amici); *Pausa
  1 ora* (dall'app o dalla notifica) sospende l'invio e mostra agli amici «in pausa fino
  alle ...», poi riprende da solo. Le posizioni dei telefoni si conservano
  `PHONE_RETENTION_DAYS` giorni. Il servizio invia con un **token di caricamento** del telefono, non con la
  sessione: vale solo per le posizioni di quel telefono, cambia a ogni avvio della
  condivisione e smette di funzionare quando il telefono viene eliminato. Si ferma con
  *Interrompi*, eliminando il telefono o uscendo dall'account. I punti senza rete restano
  in coda e partono a lotti; quelli con precisione peggiore di 250 m non fanno scattare le
  aree.
- **Live**: posizione in tempo reale (per il proprietario attiva la modalità live del
  tracker per 10 minuti, rinnovata finché la schermata è aperta), scia delle ultime 2 ore,
  segnale, satelliti, batteria, temperatura; comandi *Live 30 min*, *Localizza*, *Pausa
  antifurto*. Chi riceve una condivisione vede posizione, stato e scadenza.
  **Raggiungi a piedi** apre Google Maps (app o browser) con il percorso a piedi da dove
  sei fino all'ultima posizione dell'auto o dell'amico (non c'è per il proprio telefono).
- **Storico**: percorso del periodo colorato per velocità, **segnale LTE** o
  **satelliti** (per vedere dove il tracker perde copertura), interruzioni tratteggiate,
  eventi, cursore per ripercorrere i punti.
- **Analisi**: km, tempo di guida, viaggi; velocità; segnale LTE con soglia -105 dBm;
  satelliti con soglia 6; altitudine; tensione della batteria dell'auto con soglia
  11,8 V; temperatura e pressione; punti ricevuti e senza fix; qualità del fix;
  distribuzioni di segnale, satelliti e velocità; **mappa di copertura** (segnale medio
  per zona di ~100 m); **dati SIM** per giorno con proiezione a fine mese rispetto al
  piano. Ogni viaggio si apre sulla mappa (partenza e arrivo); **esportazione** del
  periodo in GPX (un tracciato per viaggio) o CSV (tutti i punti). Per un telefono solo
  viaggi ed esportazione (soste sotto i 5 minuti non spezzano il viaggio).
  - **Registro viaggi**: ogni viaggio si segna come *lavoro* o *personale* con una nota;
    *Registro viaggi del mese* scarica un CSV (in italiano con `;` e virgola decimale, per
    Excel) con data, orari, partenza, arrivo, km, durata, tipo e note, e i totali lavoro /
    personali / non indicati (rimborsi chilometrici, uso promiscuo dell'auto aziendale);
    con i costi impostati anche litri, carburante, usura e costo di ogni viaggio e dei totali.
  - **Costi dei viaggi** (proprietario, tracker e telefoni): modello e carburante del
    veicolo, unità del consumo (*l/100 km* oppure *km/l*, i valori si convertono) e tre
    **storici**: prezzo del carburante, **consumo** e **usura** in €/km (pneumatici,
    manutenzione, svalutazione, senza carburante). Ogni valore vale dalla sua data fino al
    successivo (grafico dell'andamento, correzione o cancellazione); ogni viaggio usa i
    valori del giorno in cui è partito, quelli precedenti al primo valore usano il primo.
    Non esiste un'API pubblica delle tabelle ACI dei costi chilometrici: *Cerca il costo
    chilometrico ACI* apre la ricerca per il modello e il valore si inserisce a mano.
    **Prezzo medio nazionale**: il backend scarica la rilevazione settimanale del
    Ministero dell'Ambiente (MASE, open data, ogni lunedì; `FUEL_PRICES_URL`, vuoto per
    disattivarla) di benzina, gasolio e GPL; la scheda la mostra con *Usa* e, se attivato
    *Prezzo dalla media nazionale*, ogni nuova settimana entra da sola nello storico (un
    prezzo inserito a mano lo stesso giorno ha la precedenza). Ogni viaggio mostra il costo
    stimato (carburante + usura, o i soli litri senza prezzo), l'analisi e il registro del
    mese i totali come somma dei viaggi.
  - **Dati aggiuntivi** (tracker, proprietario): campi letti dal tracker da un'altra scheda
    del veicolo (frame `EXTRA`, vedi il protocollo), mostrati come arrivano: ultimo valore
    di ogni campo e letture con data e ora, senza grafici. Conservati come le posizioni
    (`RETENTION_DAYS`) e inclusi nell'esportazione dei dati.
  - **Statistiche nel tempo**: per 12 mesi o 26 settimane km (con la parte di lavoro e
    personale), ore di guida e viaggi; per i tracker anche salute della batteria con la
    tensione a riposo degli ultimi 90 giorni, MB sulla SIM rispetto al piano e allarmi. Si
    basano su un riepilogo giornaliero calcolato ogni ora (gli ultimi 3 giorni ricalcolati
    per i punti arrivati in ritardo), conservato 3 anni per i tracker e 400 giorni per i
    telefoni, anche quando le posizioni sono già state cancellate.
  - **Scadenze e manutenzione** (tracker): contachilometri (si inserisce la lettura del
    cruscotto, poi segue i km dei viaggi; si corregge a mano quando serve, ad esempio dopo
    giorni con il tracker spento, e il conteggio riparte dal nuovo valore), scadenze
    standard o personalizzate con lo stato (ok / vicina / scaduta), *Fatto* (le ricorrenti
    si spostano in avanti di mesi o km), storico degli interventi.
- **Aree**: aree di arrivo dell'utente su mappa ed elenco, con editor (tocco sulla mappa
  per il centro, raggio, avviso di arrivo e di uscita).
- **Impostazioni** del dispositivo (solo proprietario): nome, colore, notifiche per tipo,
  condivisione con altri utenti (scadenza, revoca), aggiornamento del firmware,
  rimozione.
- Un dispositivo condiviso mostra solo **Live** e **Aree**, più il comando *Rinuncia alla
  condivisione*.

---

## 💻 Sviluppo Locale

Il backend richiede **Node.js 24** (`engines`, LTS). Se in locale hai un'altra versione
usa il container `node:24`.

```bash
# Database
docker run -d --name ct-db -p 5432:5432 -e POSTGRES_PASSWORD=dev timescale/timescaledb:2.24.0-pg17

# Backend (legge ../.env: DATABASE_URL, CRYPTO_MASTER_KEY, PUBLIC_URL=http://localhost:4000)
cd backend && npm ci
npm run migrate && npm run create-admin -- admin@example.com Admin
npm run dev

# App (web su http://localhost:8080, API sul backend locale)
cd app && flutter run -d web-server --web-port 8080 --dart-define=API_URL=http://localhost:4000
```

Con `PUBLIC_URL` in `http://` i cookie non sono `Secure` e le passkey funzionano solo su
`localhost`. Per servire l'app dal backend: `flutter build web` e `WEB_ROOT=../app/build/web`.

### Simulare un tracker

Senza hardware, il simulatore usa lo stesso protocollo binario del firmware:
```bash
cd backend && npm run simulate -- 356938035643809 ws://localhost:4000/tracker 30
```
Registra il dispositivo (HELLO → ACK), invia un breve percorso a lotti e resta
collegato per ricevere i comandi, stampando i byte trasmessi. Per vederlo nell'app,
aggiungilo con il codice stampato da `npm run provision -- 356938035643809`.

### Test

```bash
# Backend: test end-to-end su un database vuoto dedicato (lo schema viene ricreato)
docker run -d --name ct-test-db -p 55432:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=ct_test timescale/timescaledb:2.24.0-pg17
cd backend && npm run typecheck
TEST_DATABASE_URL=postgres://postgres:test@localhost:55432/ct_test npm run test:coverage   # soglia 98% delle righe

# App: analisi statica, test dei widget sull'app completa (backend e WebSocket simulati)
cd app && flutter analyze && flutter test --coverage && python tool/coverage.py 98
```
I test del backend avviano il server vero (HTTP, WebSocket di app e tracker) con un tracker
simulato, un autenticatore WebAuthn software e server finti per FCM e celle. I test
dell'app girano sul router reale con backend, canale realtime, passkey e tile della mappa
simulati. Dalla copertura dell'app sono esclusi il codice generato (`lib/l10n`) e quello
che gira solo su dispositivo o browser (`main.dart`, `push.dart`, `phone_service.dart`, `ws_connect_*`).
Test incrociato firmware ↔ backend (stesso encoder C++ del firmware, compilato sul
PC con MSVC o g++, decodificato con il codice TypeScript del backend):
```bash
g++ -o protocol_test firmware/test/protocol_test.cpp firmware/protocol.cpp firmware/chacha_poly.cpp firmware/owner_code.cpp
node firmware/test/cross-check.ts ./protocol_test
# Campionamento adattivo, parser NMEA e AT+CPSI, codice del portachiavi
g++ -o units_test firmware/test/units_test.cpp firmware/track_filter.cpp firmware/nmea.cpp firmware/cell.cpp firmware/owner_code.cpp && ./units_test
```
Compilazione del firmware con tutte le opzioni attive o con la libreria LilyGO, senza
modificare `configurations.h` (i file `firmware/test/config_*.h` sovrascrivono le
impostazioni):
```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs firmware \
  --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=\"test/config_full.h\""
arduino-cli compile --fqbn esp32:esp32:esp32 firmware --library <LilyGO-T-A76XX>/lib/TinyGSM \
  --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=\"test/config_lilygo.h\""
```

### Schermate per il controllo dell'interfaccia

`app/screenshots/screens_test.dart` apre le pagine principali con i dati dei test (font
reali, dimensioni di un telefono, tema chiaro e scuro) e le salva come immagini in
`app/screenshots/out/` (non in git); le mappe mostrano tasselli finti, senza rete:

```sh
cd app && flutter test screenshots --update-goldens
```

### Integrazione continua e dipendenze

`.github/workflows/ci.yml` gira a ogni push e pull request: backend (tipi, test su
TimescaleDB con soglia di copertura, `npm audit` delle dipendenze di produzione), app
(testi allineati a `tool/strings.py`, analisi, test con copertura ≥ 98%) e firmware
(compilazione della variante predefinita e completa, test unitari e test incrociato del
protocollo con g++). Le action sono fissate per commit.

`.github/workflows/release.yml` parte alla pubblicazione di una release con tag
`vX.Y.Z`: ripete i controlli della CI, compila le immagini ufficiali del firmware
(`firmware/release/<variante>.h`, versione dal tag, TinyGSM di LilyGO fissata per commit)
e l'APK firmato (keystore dai segreti `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; senza segreti la pipeline si ferma) e li
allega alla release con `gh release upload` sul repository corrente (`github.repository`,
nessun nome scritto nei file). Le pagine web per ora restano servite dal backend.

`renovate.json` (app [Renovate](https://github.com/apps/renovate) da installare sul
repository) propone il lunedì gli aggiornamenti di npm, pub, immagini Docker e action,
**solo per versioni pubblicate da almeno 14 giorni** (`minimumReleaseAge`), con versioni
esatte; gli aggiornamenti maggiori di TimescaleDB, il core ESP32 e Flutter si fanno a mano.

---

## 📡 Protocollo Binario (v2)

Ogni messaggio è un frame binario cifrato con **ChaCha20-Poly1305** (RFC 8439). La
specifica completa è in `backend/src/protocol/protocol.ts`, l'implementazione del firmware in
`firmware/protocol.cpp`.

| Campo | Dimensione | Note |
| :--- | :--- | :--- |
| Header | 1 B | versione (4 bit) + tipo: HELLO, TELEMETRY, ACK, COMMAND, COMMAND_RESULT, FW_*, UPDATE_CHECK, EXTRA |
| Dispositivo | 8 B / 1-2 B / 0 | HELLO: IMEI, TELEMETRY, COMMAND_RESULT, UPDATE_CHECK ed EXTRA: id (varint), ACK e COMMAND: nessuno (lo identifica la connessione) |
| Contatore | 4 B | mai ripetuto con la stessa chiave (riservato a blocchi in NVS) |
| Timestamp | 4 B | secondi UNIX del primo punto |
| Payload | variabile | cifrato, header usato come AAD (autenticato) |
| Tag | 8 B | Poly1305 troncato (probabilità di falsificazione 2⁻⁶⁴) |

Nel payload TELEMETRY i punti sono codificati come **differenze dal punto
precedente** (varint zigzag): coordinate a 1e-5 gradi (~1 m), altitudine in metri,
pressione in decimi di hPa, temperatura in decimi di °C, velocità in km/h. Seguono, se
presenti, satelliti usati nel fix, potenza del segnale (dBm), tensione della batteria
dell'auto, eventi (movimento, auto sollevata, alimentazione staccata, batteria scarica),
cella servente (MCC, MNC, area, id cella) e il flag *stale* (posizione dell'ultimo fix,
il GNSS ora non ha fix). Un punto completo costa ~22 byte, i successivi ~8-10 byte. Campi
mancanti (es. sensore BMP390 assente) non occupano spazio.

**Canale**: un WebSocket per tracker su `/tracker`, un frame per messaggio binario; il
tipo è nel primo byte del frame, il tracker è quello che si è autenticato sulla
connessione. Ogni connessione comincia con l'HELLO (entro 10 s), il server risponde con
l'ACK e poi manda i comandi in attesa; seguono telemetria (`TELEMETRY`), esiti
(`COMMAND_RESULT`), la richiesta giornaliera di aggiornamento (`UPDATE_CHECK`, senza
payload) e i dati aggiuntivi (`EXTRA`).

**Dati aggiuntivi (`EXTRA`)**: il payload è un oggetto JSON in UTF-8 (al massimo 400 byte
sul firmware, 50 campi, valori qualsiasi anche annidati), il timestamp è l'ora della
lettura (se il tracker non ha ancora l'ora, il server usa quella di ricezione). Il
firmware li mette in coda con `uplinkQueueExtra("{\"rpm\":820}")` e li invia appena la
connessione è pronta (al massimo 4 in RAM, persi con il deep sleep). La lettura dalla
scheda (es. seriale) non è ancora implementata: chi la scrive passa il JSON a quella
funzione e il resto (protocollo, backend, app) non cambia quando si aggiungono campi.
Costo: ~95 byte sulla rete più il JSON (una lettura di 60 byte ogni 5 minuti di guida,
~50 ore al mese, ≈ 0,1 MB). Keepalive con i ping WebSocket del tracker (`KEEP_ALIVE_SEC`, 60 s
quando il server tace); il server chiude le connessioni silenziose da 3 minuti.

### Comandi verso il tracker

I comandi restano in attesa nel database (tabella `commands`). Appena il tracker è
collegato e ha ricevuto l'ACK, il backend gli invia un frame COMMAND cifrato con
tutti i comandi in attesa; il tracker li applica una sola volta (contatore crescente
salvato in NVS: il backend usa max(secondi UNIX, precedente + 1), unico anche per gli
ACK) e risponde con un frame COMMAND_RESULT con l'esito (ok, comando sconosciuto, scaduto). Un nuovo comando
sostituisce quelli dello stesso tipo ancora in attesa. Le durate sono relative all'ora
del frame: un comando arrivato tardi dura solo il tempo rimasto.

| Comando | Parametro | Effetto |
| :--- | :--- | :--- |
| `LIVE` | secondi (0 = stop) | Ogni campione è registrato e inviato subito, senza filtro adattivo né lotti (guida e allarme) |
| `ANTITHEFT` | secondi (0 = riattiva) | Allarmi sospesi (es. auto dal meccanico); il tracker si risveglia alla scadenza e riarma |
| `LOCATE` | - | Una posizione appena possibile (scade dopo un'ora) |

Con l'auto parcheggiata il tracker dorme: un comando arriva al risveglio successivo
(heartbeat, movimento o accensione). Il tracker resta collegato ~1,5 s dopo l'ACK per
ricevere i comandi in attesa.

**Orologio**: l'ora UTC arriva dal GNSS o, senza fix, dal timestamp autenticato degli
ACK e dei comandi (solo in avanti: un frame vecchio ripetuto non la sposta indietro).

### Flusso

1. **Registrazione**: a ogni accensione il tracker invia un HELLO (IMEI e dati del
   modem) cifrato con la propria chiave. Il server deriva la chiave dall'IMEI,
   verifica il tag, registra o aggiorna il dispositivo e risponde con un ACK cifrato
   contenente l'id, salvato dal tracker in NVS.
2. **Telemetria**: il GPS è letto ogni 5 secondi, ma con il **campionamento adattivo**
   sono registrati solo i punti necessari a ridisegnare il percorso (tolleranza 10 m):
   ogni campione nelle curve, uno ogni 30 secondi in rettilineo. Pressione, temperatura e
   tensione sono inviate al massimo una volta al minuto. I punti partono a lotti
   (`BATCH_SIZE` 3, o dopo 30 secondi al massimo). Il server verifica il tag, scarta punti
   non validi e inserisce il lotto in un'unica query.
3. **Coda offline**: senza rete i punti sono salvati in chiaro (40 byte l'uno) nella
   flash (LittleFS, 192 KB ≈ 4900 punti, molte ore di guida con il campionamento
   adattivo). Al ritorno della rete sono inviati in pochi frame grandi, in ordine
   cronologico. Se la coda si riempie vengono scartati i punti più vecchi.
4. **Senza fix** (garage, galleria, parcheggio sotterraneo): i punti portano l'ultima
   posizione nota marcata *stale* e la cella servente (`AT+CPSI?`), da cui il server può
   stimare la posizione. In guida uno ogni `CELL_FALLBACK_INTERVAL_SEC` (60 s) senza fix.

### Sicurezza

- **Chiave per dispositivo**: `HMAC-SHA256(CRYPTO_MASTER_KEY, IMEI)`. La chiave
  estratta da un tracker non permette di falsificare i dati degli altri.
- **TLS** fino al proxy (`wss://`, certificato verificato), oltre alla cifratura
  end-to-end dei frame.
- **Nonce unici**: contatore persistente + timestamp + direzione (uplink/downlink).
  Il contatore downlink è unico per ACK e comandi; il tracker scarta i comandi con
  contatore non crescente.
- **Nessun fallback in chiaro**: i frame non autenticati sono scartati.
- **Replay**: un frame ripetuto produce gli stessi punti, ignorati dalla chiave
  primaria `(device_id, time)`.
- **Gateway dei tracker**: nessuna password, la credenziale è la chiave: il primo frame
  deve essere un HELLO autenticato con la chiave del suo IMEI, altrimenti la connessione
  è chiusa e il tentativo contato. Poi sono accettati solo TELEMETRY e COMMAND_RESULT con
  l'id del dispositivo autenticato (un altro tipo di frame chiude la connessione); frame
  massimo 1 KB, coda limitata, una sola connessione per tracker (la nuova sostituisce la
  vecchia).
- **Web e app**: password argon2id, TOTP obbligatorio (anti-replay, segreto cifrato
  AES-GCM), passkey WebAuthn, blocco temporaneo dopo tentativi falliti e rate limit.
  Sessioni opache (solo l'hash nel database): cookie `HttpOnly`/`Secure`/`SameSite=Strict`
  con controllo dell'Origin nel browser, token bearer nell'app. CSP restrittiva,
  HSTS. Ogni API controlla l'accesso al singolo dispositivo (404 per quelli altrui) e
  il realtime arriva solo agli utenti del dispositivo.
- **Trasporto**: REST su HTTPS (HTTP/2 tramite Traefik, compressione) per le richieste e
  un solo WebSocket (`/api/live`) per il realtime: posizioni, stato, comandi, notifiche,
  condivisioni concesse o revocate. Meno latenza e meno overhead del polling, e niente
  protocolli aggiuntivi da proteggere.
- **Validazione**: ogni chiamata (body, query, parametri e messaggi WebSocket) è
  validata con schemi zod *strict*: campi sconosciuti, tipi errati e valori fuori
  intervallo sono rifiutati con 400 prima di raggiungere la logica.
- **Rate limit e DoS**: limite globale per IP (`RATE_LIMIT`, 300/min) applicato **prima**
  dell'autenticazione, così anche le richieste anonime e i token falsi lo consumano;
  limiti stretti su login, TOTP, recupero, inviti e codici amico (`AUTH_RATE_LIMIT`; i codici
  hanno 50 bit casuali).
  Body massimo 64 KB, timeout di richiesta e connessione, limite di connessioni realtime
  per utente, rifiuto di `__proto__`/`constructor` nel JSON. Davanti, Traefik limita
  richieste al secondo e richieste contemporanee per IP, e a parte le connessioni a
  `/tracker` (10/min per IP); il gateway accetta 30 connessioni al minuto per IP e banna
  per 30 minuti chi manda 10 HELLO non validi.
- **Database**: hypertable TimescaleDB compresse dopo 7 giorni, retention
  `RETENTION_DAYS`. Le hypertable (`positions`, `traffic`) non hanno chiave esterna verso
  `devices`: la creazione di un nuovo chunk aggiungerebbe il trigger della chiave
  bloccando `devices` e andrebbe in deadlock con l'invio dei comandi. La pulizia dei dati
  alla rimozione di un dispositivo è fatta dal backend.
- **Dipendenze**: versioni esatte pubblicate da almeno 14 giorni, anche le transitive
  (`overrides` in `backend/package.json`, `dependency_overrides` in `app/pubspec.yaml`),
  senza vulnerabilità note (`npm audit`, OSV). Il `.dockerignore` tiene fuori dal
  contesto di build segreti, `.env` e dati del database.

---

## ⚡ Gestione Energetica e Antifurto

| Evento | Comportamento |
| :--- | :--- |
| Quadro acceso | Campionamento ogni 5s, invio a lotti, coda offline senza rete |
| Quadro spento (dopo 5s) | Invio della posizione di parcheggio e della coda, poi deep sleep |
| Ogni 4 ore | Risveglio, posizione di standby (heartbeat), di nuovo in deep sleep |
| Movimento (LIS3DH) | Allarme: tracciamento per 60s, esteso finché l'auto si sposta (max 15 min) |
| Auto sollevata | Inclinazione oltre 4° rispetto al parcheggio (carro attrezzi, cric): allarme. Controllata a ogni movimento e ogni 15 minuti |
| Alimentazione staccata | Con la [scheda di alimentazione](hardware/README.md): allarme e tracciamento a batteria |
| Portachiavi vicino | Con `OWNER_TAG`: il movimento è ignorato se il portachiavi del proprietario è nel raggio Bluetooth ([dettagli](hardware/README.md#portachiavi-del-proprietario-opzionale)) |
| Antifurto in pausa | Comando `ANTITHEFT`: nessun allarme fino alla scadenza |

- Il rilevamento di movimento si arma solo **3 minuti dopo lo spegnimento**
  (portiere, sedili) e resta in pausa per **10 minuti dopo un allarme**, per limitare
  i dati in caso di falsi allarmi (vento, mezzi pesanti).
- Senza fix GPS (garage) heartbeat e allarmi usano l'ultima posizione nota, marcata
  *stale*, con la cella servente.
- Il sotto chiave risveglia sempre il tracker, anche con logica attiva bassa
  (optoisolatore).

---

## 🔋 Scheda di Alimentazione

Il progetto completo per l'installazione in auto (protezioni, batteria tampone, misura
della tensione, ingresso sotto chiave isolato, GNSS esterno opzionale) è in
[hardware/README.md](hardware/README.md), con la distinta in
[hardware/bom.csv](hardware/bom.csv). Le sezioni seguenti descrivono il montaggio base
senza batteria tampone.

> Solo le varianti **A7670E-FASE** e **A7670SA-FASE** del modem hanno il GNSS integrato
> (verificabile con il comando `AT+SIMCOMATI`). La variante globale **A7670G** non lo ha:
> serve un modulo GNSS esterno (`GNSS_SOURCE_EXTERNAL`).

---

## 🛒 Lista dei Materiali (Bill of Materials)

Di seguito trovi la lista completa dei componenti hardware necessari per assemblare un localizzatore. I prezzi sono indicativi e possono variare in base al rivenditore.

### Componenti Principali

| # | Componente | Descrizione / Ruolo | Q.tà | Prezzo Indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 1 | **LilyGO TTGO T-CALL A7670** | Microcontrollore ESP32 con modem LTE-M/GPRS integrato (SIM7670). Cuore del localizzatore: gestisce GPS, connettività verso il server e cifratura ChaCha20-Poly1305. | 1 | ~€ 25–35 |
| 2 | **Modulo GPS (integrato nel T-CALL A7670)** | Il modulo A7670 include un ricevitore GNSS integrato compatibile con GPS, GLONASS e BeiDou. Non è necessario un modulo GPS esterno separato. | — | (incluso) |
| 3 | **BMP390** | Sensore barometrico/altimetrico a precisione elevata (I2C). Misura pressione atmosferica e temperatura. Connesso al bus I2C (GPIO 21/22). | 1 | ~€ 5–10 |
| 4 | **LIS3DH** | Accelerometro triassiale digitale a basso consumo (I2C). Usato per il rilevamento di vibrazioni/movimento (antifurto) con wakeup hardware via INT1 (GPIO 33). | 1 | ~€ 3–8 |

### Alimentazione & Protezione

| # | Componente | Descrizione / Ruolo | Q.tà | Prezzo Indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 5 | **Convertitore Step-Down DC-DC (12V → 5V, ≥ 1A)** | Riduce la tensione dell'impianto elettrico dell'auto (+12V/+14.4V) a 5V stabili per alimentare il LilyGO via USB o VIN. Consigliato un modulo a bassissima dissipazione termica (es. MP1584EN o LM2596). | 1 | ~€ 2-5 |
| 6 | **Portafusibile inline + Fusibile 1A** | Protezione indispensabile sul positivo (+12V) preso direttamente dalla batteria o dal quadro. Protegge l'impianto in caso di cortocircuito. | 1 | ~€ 1–3 |
| 7 | **Optoisolatore PC817** *(consigliato)* | Garantisce isolamento galvanico completo tra l'impianto 12V sotto chiave e il GPIO 32 del LilyGO. Protegge l'ESP32 da picchi di tensione dell'alternatore. | 1 | ~€ 0,50–1 |
| 8 | **Resistenza 1 kΩ** | Resistenza di limitazione corrente per il fotodiodo dell'optoisolatore (lato +12V). | 1 | ~€ 0,10 |
| — | **Alternativa: Resistenze 12 kΩ + 3.3 kΩ** | Se non si usa l'optoisolatore, si utilizza un partitore resistivo per abbassare il segnale da 12-14.4V a ~2.6-3.1V per il GPIO 32. | 1+1 | ~€ 0,20 |

### Connettività & Accessori

| # | Componente | Descrizione / Ruolo | Q.tà | Prezzo Indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 9 | **SIM Card IoT/M2M (100 MB/mese)** | SIM dati per la connettività cellulare del modulo A7670. Qualsiasi operatore IoT è compatibile. 100 MB/mese sono ampiamente sufficienti anche per le flotte aziendali (vedi sezione Stima Dati). | 1 | ~€ 5–15/anno |
| 10 | **Antenna GPS esterna (opzionale)** | Antenna esterna a patch o attiva per migliorare la ricezione GPS in ambienti con scarsa visibilità del cielo (es. sotto cruscotto). | 1 | ~€ 3–8 |
| 11 | **Antenna LTE esterna (opzionale)** | Antenna esterna per migliorare il segnale cellulare in aree con copertura debole. | 1 | ~€ 3–8 |
| 12 | **Cavi Dupont/Jumper M-F (20 cm)** | Per il collegamento dei sensori BMP390 e LIS3DH ai pin I2C e di alimentazione del LilyGO. | 8–10 | ~€ 2–4 |
| 13 | **Breadboard o PCB prototipale** | Per assemblare e fissare i sensori durante il test. Per l'installazione definitiva in auto si consiglia una piccola PCB personalizzata. | 1 | ~€ 2–5 |
| 14 | **Scatola/box impermeabile (opzionale)** | Contenitore per proteggere l'elettronica da umidità, polvere e vibrazioni nell'ambiente auto. | 1 | ~€ 3–10 |

### 💰 Costo Totale Stimato

| Configurazione | Costo Stimato |
| :--- | :---: |
| **Minima** (solo componenti essenziali, partitore resistivo) | **~€ 40–55** |
| **Raccomandata** (con optoisolatore, antenne esterne, box) | **~€ 55–80** |

> [!TIP]
> Acquistando i componenti su marketplace asiatici (AliExpress, Banggood) è possibile ridurre il costo della configurazione raccomandata a **meno di € 40**. Se si preferisce spedizione rapida, si trovano su Amazon IT a prezzi leggermente superiori.

> [!NOTE]
> Il costo della SIM IoT non è incluso nel totale poiché è una spesa ricorrente annuale. Operatori come **Onomondo**, **1NCE** o **Tele2 IoT** offrono piani da pochi euro l'anno per bassi volumi di dati.

---

## 🔌 Schema Elettrico & Connessioni Hardware

Per facilitare l'assemblaggio e il cablaggio del localizzatore all'interno
della vettura, segui lo schema delle connessioni riportato di seguito. Il
sistema utilizza un bus I2C condiviso per i sensori (BMP390 e LIS3DH) e due
linee di input dedicate per il monitoraggio dello stato del veicolo.

### 1. Tabella delle Connessioni (Pinout Mapping)

| Sensore / Linea | Pin Sensore | Pin LilyGO | Descrizione |
| :--- | :--- | :--- | :--- |
| **Alimentazione** | VCC / VIN | **3V3** | Alimentazione a 3.3V |
| **Alimentazione** | GND | **GND** | Massa di riferimento comune |
| **Bus I2C (SDA)** | SDA | **GPIO 21** | Linea Dati (BMP + LIS) |
| **Bus I2C (SCL)** | SCL | **GPIO 22** | Linea Clock (BMP + LIS) |
| **Allarme LIS3DH** | INT1 | **GPIO 33** | Risveglio per movimento |
| **Sotto Chiave** | Segnale * | **GPIO 32** | Accensione (via opto) |

---

### 2. Schema Elettrico a Blocchi (ASCII Diagram)

```text
+------------------+          +------------------+
|   LIS3DH (Acc.)  |          |   BMP390 (Baro.) |
|                  |          |                  |
|  [VCC]  [GND]    |          |  [VCC]  [GND]    |
+────┬──────┬──────+          +────┬──────┬──────+
     │      │                       │      │
     │      │     +─────────────────┘      │
     │      └─────┼─────────┐              │
     │            │         │              │
  [SDA]   [SCL]   │      [SDA]   [SCL]     │
 ┌───┴──────┴─────┼─────────┼──────┴───────┤
 │                │         │              │
 │                ▼         ▼              ▼
 │           +────────+ +────────+    +────────+
 │           | GPIO21 | | GPIO22 |    |  3.3V  |
 │           |  (SDA) | |  (SCL) |    |  (VCC) |
 │           +────────+ +────────+    +────────+
 │                ▲
 │   [INT1]       │
 └───┬────────────┘
     │
     ▼
+────────+
| GPIO33 | (Risveglio Antifurto / Motion Alarm)
+────────+

+───────────────────────+        +────────+
| Sotto Chiave (+12V)  |──[Opto]──►| GPIO32 | (Ignition Sense Input)
+───────────────────────+        +────────+
```

---

### 3. Circuiti di Protezione per il Sotto Chiave (+12V -> 3.3V)

L'ESP32 lavora esclusivamente con segnali a **3.3V massimo**. Collegare
direttamente la tensione della vettura (+12V / +14.4V ad alternatore attivo)
brucerà l'ESP32. Si consiglia di utilizzare uno dei seguenti circuiti:

#### Opzione A: Fotoaccoppiatore (Altamente Consigliata)

L'uso di un optoisolatore (es. **PC817**) garantisce l'isolamento galvanico
completo tra l'impianto elettrico dell'auto e il tracciatore, proteggendo
l'ESP32 da sovratensioni ed extracorrenti causate da alternatore o motorino.

- Collega il +12V sotto chiave all'anodo del fotodiodo dell'optoisolatore
  tramite una resistenza da **1 kΩ** (per limitare la corrente a ~10-12mA).
- Collega il catodo del fotodiodo a massa dell'auto (GND).
- Sul lato dell'ESP32: collega il collettore del fototransistor al GPIO 32 e
  l'emettitore a GND, configurando la porta con una resistenza di pull-up
  software (o fisica) a 3.3V. Con questo schema il segnale è attivo basso:
  imposta `IGNITION_ACTIVE_LEVEL LOW` in `firmware/configurations.h` (il
  firmware abilita il pull-up interno, anche durante il deep sleep).

#### Opzione B: Partitore di Tensione Resistivo (Economica)

Se non disponi di un optoisolatore, puoi utilizzare un partitore di tensione
con due resistenze per ridurre il segnale a un valore di sicurezza di ~3.3V:

- **R1 (lato +12V)**: **12 kΩ**
- **R2 (lato GND)**: **3.3 kΩ**
- Il segnale prelevato dal punto centrale del partitore (tra le due resistenze)
  sarà di circa **2.6V** a motore spento (12V) e **3.1V** con l'alternatore
  attivo (14.4V): sempre letto come `HIGH` e sotto il limite di 3.6V dei GPIO.
  Con 10 kΩ al posto di 12 kΩ, a 14.4V si arriverebbe a 3.57V, al limite
  assoluto dell'ESP32. Va cablato al GPIO 32 con `IGNITION_ACTIVE_LEVEL HIGH`.

---


## 📊 Stima e Utilizzo Dati (Consumo Mensile SIM)

Valori misurati sui frame reali, includendo tutto ciò che la SIM trasmette e
riceve per ogni invio: WebSocket (6 B), record TLS (29 B), TCP/IP (40 B) e l'ACK TCP
del server (40 B).

### 1. Peso di un Invio

| Configurazione | Frame | Sulla rete | Per ora di guida |
| :--- | :---: | :---: | :---: |
| Protocollo precedente (JSON + hex, 1 punto ogni 5s) | ~238 B | ~339 B | ~244 KB |
| **v2, `BATCH_SIZE 1`** (posizione ogni 5s) | 35 B | 126 B | 91 KB |
| **v2, `BATCH_SIZE 3`** (default, ogni 15s) | 51 B | 142 B | 34 KB |
| **v2, `BATCH_SIZE 6`** (ogni 30s) | 75 B | 166 B | 20 KB |

A parità di campionamento, la configurazione di default consuma circa **7 volte
meno** del protocollo precedente.

### 2. Profili di Utilizzo

- **A. Pendolare**: 41 ore di guida al mese
- **B. Professionista**: 84 ore di guida al mese
- **C. Flotta / Taxi**: 208 ore di guida al mese (8 ore al giorno, 26 giorni)

| Profilo | `BATCH_SIZE 1` | `BATCH_SIZE 3` | `BATCH_SIZE 6` |
| :--- | :---: | :---: | :---: |
| **A. Pendolare** | 3,7 MB | **1,4 MB** | 0,8 MB |
| **B. Professionista** | 7,6 MB | **2,9 MB** | 1,7 MB |
| **C. Flotta** | 18,9 MB | **7,1 MB** | 4,1 MB |

A questi valori si aggiungono:

| Voce | Consumo mensile |
| :--- | :---: |
| Connessione a ogni accensione (TCP, WebSocket, HELLO/ACK ≈ 1,5 KB, 4 al giorno) | ~0,2 MB |
| Heartbeat ogni 4 ore (connessione + 1 punto) | ~0,3 MB |
| TLS (handshake ~5 KB a connessione, ~29 B per frame) | ~2 MB |
| Allarmi: caso peggiore, un falso allarme ogni 10 minuti per tutto il mese | ~11 MB |
| Richiesta giornaliera di aggiornamento (`AUTO_UPDATE 1`) | ~3 KB |
| Un aggiornamento del firmware (quando esce una versione) | ~1,3 MB |

**Caso peggiore realistico** (profilo C, posizione ogni 5 secondi, falsi allarmi
continui, TLS): **~35 MB/mese**, ben sotto una SIM da **200 MB/mese**. Una sessione
`LIVE` costa come `BATCH_SIZE 1`, ~90 KB per ora.

### 3. Ottimizzazioni Integrate

1. **Protocollo binario a differenze**: ~8 byte per punto, contro ~238 byte di JSON
   cifrato e codificato in esadecimale.
2. **Invio a lotti**: l'overhead fisso di ~85 byte per invio (TCP/IP, WebSocket) è
   diviso fra più punti.
3. **Una sola scrittura per frame WebSocket**: header e payload nello stesso
   segmento TCP.
4. **Filtro di distanza**: in sosta o in coda nessun punto, salvo uno ogni 5 minuti
   (`THRESHOLD_DISTANCE`, `STATIONARY_INTERVAL_SEC`).
5. **Coda offline compatta**: al ritorno della rete fino a 40 punti per frame.
6. **Riconnessione con back-off esponenziale** (5s → 2 min): con copertura scarsa i
   tentativi non consumano dati inutilmente.
7. **Keep-alive a 60s** solo quando non ci sono altri invii (Cloudflare chiude i
   WebSocket inattivi dopo 100s).
8. **Limiti sugli allarmi**: armamento ritardato e pausa dopo ogni allarme.
