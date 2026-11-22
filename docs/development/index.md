# Ambiente di sviluppo e test

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

## Simulare un tracker

Senza hardware, il simulatore usa lo stesso protocollo binario del firmware:
```bash
cd backend && npm run simulate -- 356938035643809 ws://localhost:4000/tracker 30
```
Registra il dispositivo (HELLO → ACK), invia un breve percorso a lotti e resta
collegato per ricevere i comandi, stampando i byte trasmessi. Per vederlo nell'app,
aggiungilo con il codice stampato da `npm run provision -- 356938035643809`.

## Test

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
arduino-cli compile --fqbn esp32:esp32:esp32 firmware --library <LilyGo-Modem-Series>/lib/TinyGSM \
  --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=\"test/config_lilygo.h\""
```

## Schermate per il controllo dell'interfaccia

`app/screenshots/screens_test.dart` apre le pagine principali con i dati dei test (font
reali, dimensioni di un telefono Android e di un browser desktop a 1280×800 con la barra di
navigazione laterale, tema chiaro e scuro; i file `d*` sono quelli desktop) e le salva come immagini in
`app/screenshots/out/` (non in git); le mappe mostrano tasselli finti, senza rete:

```sh
cd app && flutter test screenshots --update-goldens
```

## Documentazione

```sh
pip install -r docs/requirements.txt
mkdocs serve          # http://127.0.0.1:8000, italiano e inglese (/en/)
```

Ogni pagina ha la versione italiana (`pagina.md`) e quella inglese (`pagina.en.md`): vanno
aggiornate insieme. `mkdocs build --strict` fallisce con collegamenti rotti o pagine fuori
dalla navigazione.

