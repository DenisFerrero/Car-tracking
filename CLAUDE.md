# Car Tracking: project rules

GPS tracker for cars (ESP32 firmware), Node.js backend, Flutter app (Android + web) and a
bilingual documentation site. Full documentation: `docs/` (published on GitHub Pages).

## General rules

- Talk to the maintainer in **Italian**. Code, comments and commit messages in English.
- The app and the documentation are **bilingual, Italian and English**: every user-facing text
  and every doc page exists in both languages.
- **Dependencies**: exact versions published at least **14 days** earlier, with no known
  issues or vulnerabilities, transitive ones included (`overrides`, `dependency_overrides`).
  GitHub Actions pinned by commit SHA with the version in a comment.
- Everything **open source and free of charge**: no paid services or licenses (maps on
  OpenStreetMap via flutter_map, no Google Maps keys).
- **No public sign-up**: users are added only by the administrator.
- **SIM budget**: 200 MB/month at most; measure the bytes on the wire for any firmware or
  protocol change.
- Never touch `.env` or `firmware/secrets.h`; never commit secrets, keystores or build output.
- Commit only when asked, locally, without pushing.
- The repository name is never written in files: workflows use `github.repository`, the backend
  `GITHUB_REPO`.

## Backend (`backend/`)

- Node.js 24, Fastify 5, TypeScript, postgres.js, TimescaleDB.
- **zod validation on every call** (body, query, params, WebSocket messages), strict schemas.
- Migrations in `backend/migrations/NNN_name.sql`, applied at startup.
- **Migrations are additive**: they must upgrade a populated production database without
  losing data or breaking its integrity. Add tables, indexes, policies and columns that are
  nullable or have a default; never drop or rename tables or columns holding data, never
  narrow a type, never add a constraint (NOT NULL, CHECK, UNIQUE, FK) that existing rows could
  violate without fixing those rows in the same migration. Never edit an applied migration.
  Structural changes go expand → copy the data → drop the old part only once nothing uses it.
- Tests end-to-end on a real TimescaleDB (`TEST_DATABASE_URL`), coverage **≥ 98%** of lines.
- **Platform log** (`src/services/platform-log.ts`, `docs/server/logs.md`): every `warn` /
  `error` of `ctx.log` and of its children (`component` = source) is also saved for 30 days,
  with slow requests and slow queries. Report failures through the logger, never with
  personal data (bodies, query strings, IPs, emails, tokens): the fields `ip`, `email`,
  `token`… are dropped, but keep messages and fields free of them.

## App (`app/`)

- Strings live in `app/tool/strings.py` (Italian and English): run `python tool/strings.py`
  then `flutter gen-l10n`; never edit the generated `lib/l10n` files by hand.
- Theme "night road" in `lib/theme.dart` (petrol + amber, squared shapes): reuse its colors and
  widgets instead of hard-coded styles.
- Widget tests on the full app, coverage **≥ 98%** (`python tool/coverage.py 98`).
- Build the APK only when asked.

## Dashboards: keep the catalog current

Custom dashboards show the values of a catalog, the same in `backend/src/services/metrics.ts`
and `app/lib/screens/dashboards/catalog.dart`. **Every new value of the platform** (a sensor
or a column of the positions, a daily total, a cost, a state) gets its metric in both, with
the kinds of device, the views, the texts IT/EN, the tests and a row in the catalog of
`docs/app/dashboards.md` (+ `.en.md`). A metric removed or renamed drops the saved widgets
that use it: prefer adding to changing.

## Firmware (`firmware/`)

- Build in place (no temporary copies). Board selected with `BOARD` in `configurations.h`.
- Official images (`firmware/release/<variant>.h`) contain no credentials.

## Documentation (`docs/`, `mkdocs.yml`)

- MkDocs Material + mkdocs-static-i18n, suffix structure: `page.md` Italian (default),
  `page.en.md` English. **Update both** whenever a feature, an option, an endpoint or a
  procedure changes, in the same change as the code.
- New pages go in the `nav` of `mkdocs.yml`, with the English title in `nav_translations`.
- Check with `mkdocs build --strict` (broken links and anchors fail the build).
- `README.md` stays a short overview that links to the site.

### Devices section: keep it current

The **device catalog** (`docs/devices/index.md` + `.en.md`) lists every board the firmware
supports. When adding or changing a board:

1. `firmware/boards/<board>.h` with all the `BOARD_*` macros, registered in
   `firmware/board.h` (and `firmware/modem_<family>.cpp` for a new modem family).
2. For official images: `firmware/release/<variant>.h` and the variant in the matrix of
   `.github/workflows/release.yml`.
3. A row in the catalog tables (boards and, if any, release variants), both languages, with
   its status: *supported* (in the firmware with official images), *experimental* (in the
   firmware, no official images), *planned*.
4. A page `docs/devices/<board-slug>.md` + `.en.md` with: status badge, board file and
   variants, modem and GNSS notes, bill of materials with indicative prices, wiring table and
   diagram, ignition input, firmware settings, known limits. Add it to the `nav`.
5. Accessories (power boards, sensors, key fobs) get the same treatment and a row in the
   accessories table.

`docs/devices/new-device.md` (+ `.en.md`) is the end-to-end procedure for a new tracker
(hardware, provisioning, firmware, pairing, installation, moving between vehicles): update it
when any of these steps changes (provisioning script, pairing wizard, tracker settings).
