# Development environment and tests

The backend needs **Node.js 24** (`engines`, LTS). With another local version use the
`node:24` container.

```bash
# Database
docker run -d --name ct-db -p 5432:5432 -e POSTGRES_PASSWORD=dev timescale/timescaledb:2.24.0-pg17

# Backend (reads ../.env: DATABASE_URL, CRYPTO_MASTER_KEY, PUBLIC_URL=http://localhost:4000)
cd backend && npm ci
npm run migrate && npm run create-admin -- admin@example.com Admin
npm run dev

# App (web on http://localhost:8080, API on the local backend)
cd app && flutter run -d web-server --web-port 8080 --dart-define=API_URL=http://localhost:4000
```

With an `http://` `PUBLIC_URL` cookies aren't `Secure` and passkeys work only on `localhost`.
To serve the app from the backend: `flutter build web` and `WEB_ROOT=../app/build/web`.

## Simulating a tracker

Without hardware, the simulator uses the same binary protocol as the firmware:

```bash
cd backend && npm run simulate -- 356938035643809 ws://localhost:4000/tracker 30
```

It registers the device (HELLO → ACK), sends a short route in batches and stays connected to
receive commands, printing the bytes sent. To see it in the app, add it with the code printed
by `npm run provision -- 356938035643809`.

## Tests

```bash
# Backend: end-to-end tests on a dedicated empty database (the schema is recreated)
docker run -d --name ct-test-db -p 55432:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=ct_test timescale/timescaledb:2.24.0-pg17
cd backend && npm run typecheck
TEST_DATABASE_URL=postgres://postgres:test@localhost:55432/ct_test npm run test:coverage   # 98% line threshold

# App: static analysis, widget tests on the whole app (simulated backend and WebSocket)
cd app && flutter analyze && flutter test --coverage && python tool/coverage.py 98
```

The backend tests start the real server (HTTP, app and tracker WebSockets) with a simulated
tracker, a software WebAuthn authenticator and fake servers for FCM and cells. The app tests
run on the real router with simulated backend, realtime channel, passkeys and map tiles. The
app coverage excludes generated code (`lib/l10n`) and code that runs only on a device or in
the browser (`main.dart`, `push.dart`, `phone_service.dart`, `ws_connect_*`).

Firmware ↔ backend cross test (the same C++ encoder as the firmware, built on the PC with MSVC
or g++, decoded by the TypeScript code of the backend):

```bash
g++ -o protocol_test firmware/test/protocol_test.cpp firmware/protocol.cpp firmware/chacha_poly.cpp firmware/owner_code.cpp
node firmware/test/cross-check.ts ./protocol_test
# Adaptive sampling, NMEA and AT+CPSI parsers, key fob code
g++ -o units_test firmware/test/units_test.cpp firmware/track_filter.cpp firmware/nmea.cpp firmware/cell.cpp firmware/owner_code.cpp && ./units_test
```

Firmware build with every option on or with the LilyGO library, without changing
`configurations.h` (the `firmware/test/config_*.h` files override the settings):

```bash
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs firmware \
  --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=\"test/config_full.h\""
arduino-cli compile --fqbn esp32:esp32:esp32 firmware --library <LilyGo-Modem-Series>/lib/TinyGSM \
  --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=\"test/config_lilygo.h\""
```

## Screenshots to check the interface

`app/screenshots/screens_test.dart` opens the main pages with the test data (real fonts, phone
size, light and dark theme) and saves them as images in `app/screenshots/out/` (not in git);
maps show fake tiles, no network:

```sh
cd app && flutter test screenshots --update-goldens
```

## Documentation

```sh
pip install -r docs/requirements.txt
mkdocs serve          # http://127.0.0.1:8000, Italian and English (/en/)
```

Every page has the Italian version (`page.md`) and the English one (`page.en.md`): update
them together. `mkdocs build --strict` fails on broken links or pages missing from the
navigation.
