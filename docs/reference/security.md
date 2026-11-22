# Sicurezza

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
  è chiusa e il tentativo contato. Poi sono accettati solo TELEMETRY, COMMAND_RESULT,
  UPDATE_CHECK ed EXTRA con l'id del dispositivo autenticato (un altro tipo di frame chiude la connessione); frame
  massimo 1 KB, coda limitata, una sola connessione per tracker (la nuova sostituisce la
  vecchia).
- **Web e app**: password argon2id, TOTP obbligatorio (anti-replay, segreto cifrato
  AES-GCM), passkey WebAuthn, blocco temporaneo dopo tentativi falliti e rate limit.
  Sessioni opache (solo l'hash nel database): cookie `HttpOnly`/`Secure`/`SameSite=Strict`
  con controllo dell'Origin nel browser, token bearer nell'app. CSP restrittiva,
  HSTS. Ogni API controlla l'accesso al singolo dispositivo (404 per quelli altrui) e
  il realtime arriva solo agli utenti del dispositivo.
- **Telefoni**: le posizioni si caricano con un token valido solo per quel telefono,
  rinnovato a ogni avvio della condivisione; un punto può indicare solo un veicolo del
  proprietario del telefono, gli altri vengono scartati.
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
  `RETENTION_DAYS` (`PHONE_RETENTION_DAYS` per le posizioni personali dei telefoni). Le hypertable (`positions`, `traffic`) non hanno chiave esterna verso
  `devices`: la creazione di un nuovo chunk aggiungerebbe il trigger della chiave
  bloccando `devices` e andrebbe in deadlock con l'invio dei comandi. La pulizia dei dati
  alla rimozione di un dispositivo è fatta dal backend.
- **Dipendenze**: versioni esatte pubblicate da almeno 14 giorni, anche le transitive
  (`overrides` in `backend/package.json`, `dependency_overrides` in `app/pubspec.yaml`),
  senza vulnerabilità note (`npm audit`, OSV). Il `.dockerignore` tiene fuori dal
  contesto di build segreti, `.env` e dati del database.
