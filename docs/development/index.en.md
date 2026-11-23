# Development environment and tests

The backend needs **Node.js 24** (`engines`, LTS). With another local version use the
`node:24` container.

```bash
# Database
docker run -d --name ct-db -p 5432:5432 -e POSTGRES_PASSWORD=dev timescale/timescaledb:2.24.0-pg17 postgres -c shared_preload_libraries=timescaledb,pg_stat_statements

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
docker run -d --name ct-test-db -p 55432:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=ct_test timescale/timescaledb:2.24.0-pg17 postgres -c shared_preload_libraries=timescaledb,pg_stat_statements
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

## End-to-end tests on the web

`e2e/run.sh` tries the web app as a person uses it: it builds the image of the backend (backend
and web app, as the release), starts a TimescaleDB, creates the first administrator with
`create-admin` and runs Playwright (Chromium, official image) on the same Docker network. The
scenarios, one after the other on the same account: invite with password, authenticator app
and recovery codes; vehicle without a tracker; two full tanks and the real consumption;
polygon area drawn on the map; monthly summary; logout and login with the second factor. The
maps use tiles of the backend itself (no requests to the OSM servers).

```sh
sh e2e/run.sh                                         # builds the image and tests
E2E_IMAGE=ct-e2e:local sh e2e/run.sh                  # image already built
E2E_IMAGE=ct-e2e:local E2E_WEB=app/build/web sh e2e/run.sh   # web app of a local flutter build
```

Flutter draws on a canvas: the tests turn on the semantics (the accessibility tree gives the
DOM texts, buttons and fields) and look for the elements by role and label, with the Italian
texts read from `app/lib/l10n/app_it.arb`. Screenshots and traces of the failed tests in
`e2e/results/`, report in `e2e/report/`; the CI attaches them to the `e2e` job.

## Load test

`npm run load` (in `backend/`) fills a database with trackers, users and history, then keeps
the trackers connected (HELLO → ACK, positions in batches) and has the users use the app
(devices, positions, trips, statistics, coverage, trends, deadlines, dashboards, realtime
channel open); at the end it prints for every page count, errors by HTTP status, p50 / p95 /
p99 / max and the heaviest queries of `pg_stat_statements`. It refuses non-local addresses
without `--allow-remote`; `--cleanup` deletes the data of the test.

```sh
# Dedicated database and backend (never the production ones)
DATABASE_URL=postgres://... CRYPTO_MASTER_KEY=... npm run load -- --trackers 200 --users 40 --days 90 --minutes 12
npm run load -- --skip-seed --minutes 3                # again, on the same data
```

Result with the backend on 1 CPU / 512 MB and TimescaleDB on 2 CPUs / 2 GB, 200 trackers, 40
users, 90 days of history (10 million positions; the compressed chunks go from 645 to 79 MB,
974 MB in all with the last 14 days uncompressed): about 19
requests per second with no errors, p95 under 100 ms for every page (30-day dashboard 95 ms,
coverage 60 ms, the rest under 35 ms).

What it found and fixed:

- **Latest position of the devices**: a `DISTINCT ON` decompressed every chunk of the period
  (36 ms); now a `LATERAL` with `ORDER BY time DESC LIMIT 1` per device reads only the newest
  chunk (0.4 ms). Same pattern for the data export.
- **Cleanup of the positions of the phones**: with a subquery on the ids TimescaleDB
  decompressed every compressed chunk to look for them, went over the limit of 100,000 rows
  and the hourly job stopped there (expired sessions and invites never cleaned). Now the ids
  are constants and the deletes in compressed chunks (cleanup, device removed, tracker paired
  in a vehicle) lift the limit only in their own transaction.
- **Extra data** (`device_extra`) compressed after 30 days like the traffic.

## Screenshots to check the interface

`app/screenshots/screens_test.dart` opens the main pages with the test data (real fonts, Android
phone size and a 1280×800 desktop browser with the navigation rail, light and dark theme;
the `d*` files are the desktop ones) and saves them as images in `app/screenshots/out/` (not in git);
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
