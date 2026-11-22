# Server installation

Requirements: a Linux server with Docker and Docker Compose (amd64 or arm64, also a Raspberry
Pi 4/5), a domain and, for the trackers, port 443 reachable from the Internet, forwarded by the router to the server.

## 1. Environment variables

Copy `.env.example` to `.env` and replace **all** the values (random values:
`openssl rand -hex 32`, see [Generating the secrets](#generating-the-secrets)):

| Variable | Meaning |
| :--- | :--- |
| `DOMAIN` | Public domain, e.g. *tracking.mydomain.com*. Passkeys are bound to it: changing it means registering them again |
| `POSTGRES_*` | Database, reachable only from the internal `db` network |
| `CRYPTO_MASTER_KEY` | Secret (min 32 characters) the keys and pairing codes of the trackers derive from, and that encrypts the TOTP secrets. If it changes, the trackers must be flashed again and the authenticator apps set up again: **back it up** |
| `RETENTION_DAYS`, `SIM_BUDGET_MB`, `OFFLINE_AFTER_HOURS` | Data retention, SIM data plan (traffic chart), unreachable tracker alert |
| `PHONE_RETENTION_DAYS` | Retention of the personal positions of the phones (default 30), shorter than the vehicles' |
| `TIMEZONE` | Time zone of the days of the statistics, of the area schedules and of the backups |
| `LOG_RETENTION_DAYS`, `LOG_SLOW_REQUEST_MS`, `LOG_SLOW_QUERY_MS` | [Platform log](logs.md): days kept (default 30), thresholds of a slow request and query |
| `ANDROID_PACKAGE`, `ANDROID_CERT_SHA256` | Passkeys in the Android app too (see [App](../app/index.md)) |
| `GITHUB_REPO`, `GITHUB_TOKEN` | Firmware and app versions from the releases of the repository (`owner/name`); if the repository is renamed only this variable changes. Optional token (rate limit) |
| `FUEL_PRICES_URL` | Weekly average fuel prices of the Italian ministry (MASE); empty to disable |
| `MAP_TILE_URL`, `MAP_ATTRIBUTION` | Map tiles (OpenStreetMap by default, see below) |
| `CELL_GEOLOCATION_URL` | Position estimated from the cell without a GNSS fix, e.g. `https://api.beacondb.net/v1/geolocate` |
| `FCM_SERVICE_ACCOUNT_FILE` | Android push notifications (Firebase, optional) |
| `BACKEND_IMAGE` | Release image instead of a local build (see [Updates](updates.md)) |

Files with secrets (`.env`, `firmware/secrets.h`, `secrets/`, Android keystore) are excluded
from git.

!!! note "Maps"
    The app uses [flutter_map](https://github.com/fleaflet/flutter_map) (the Flutter
    counterpart of Leaflet) with OpenStreetMap tiles: no key and no cost. The OpenStreetMap
    servers are for light use ([tile usage policy](https://operations.osmfoundation.org/policies/tiles/)):
    with many users set a compatible provider or your own tile server in `MAP_TILE_URL`.
    Google Maps instead needs an API key tied to a billing account.

## Generating the secrets

Values to create once and keep in a password manager **off the server**. Hex random values
are safe everywhere, URLs included:

```sh
openssl rand -hex 32      # 64 hex characters
```

| Variable | How to get it |
| :--- | :--- |
| `POSTGRES_PASSWORD` | `openssl rand -hex 32`. It goes inside `DATABASE_URL`: avoid `/`, `+`, `=` (so no base64). Changing it after the first start also needs `ALTER USER` in the database |
| `CRYPTO_MASTER_KEY` | `openssl rand -hex 32`. **Never change it**: the tracker keys derive from it and it encrypts the TOTP secrets |
| `RESTIC_PASSWORD` | `openssl rand -hex 32` (only with the `offsite` profile). Without it the copy off the server can't be read |
| `ACME_EMAIL` | One of your addresses: Let's Encrypt uses it for expiry warnings |
| `ANDROID_CERT_SHA256` | Fingerprint of the certificate signing the APK: `keytool -list -v -keystore car-tracking-release.jks -alias car-tracking`, `SHA256:` line (e.g. `AB:CD:...`). The keystore is created as described in [Releases and pipeline](../development/releases.md#apk-signing-required); separate several certificates with commas |
| `GITHUB_REPO` | `owner/name` of the repository with the releases (e.g. `myname/car-tracking`) |
| `GITHUB_TOKEN` | Optional: *Settings → Developer settings → Fine-grained tokens*, access *Public repositories (read-only)*, no extra permissions; with a private repository *Contents: read* on that repository |
| `AWS_*` / `B2_*` | Bucket keys for `offsite`: IAM user with access to that bucket only (S3) or an *Application Key* limited to the bucket (Backblaze B2) |
| `FCM_SERVICE_ACCOUNT_FILE` | Optional: Firebase console → *Project settings → Service accounts → Generate new private key*, save the JSON in `secrets/fcm.json` |

The GitHub pipeline secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) don't go in `.env`: see
[Releases and pipeline](../development/releases.md#secrets-and-variables).

## 2. Exposure: a single port on the router

The backend must be reachable over HTTPS on a real domain: passkeys (WebAuthn) need it, and so
does the tracker, which connects to `wss://<domain>/tracker`.

1. The domain (DNS `A`/`AAAA` record) points to the public IP of the home connection; with a
   dynamic IP use a dynamic DNS service.
2. On the router forward **only TCP port 443** to the IP of the server. Port 80 only redirects
   to HTTPS and can stay closed.
3. Traefik (`--profile traefik`) gets the Let's Encrypt certificate with the **TLS-ALPN**
   challenge on 443 (TLS 1.2+, `traefik/dynamic.yml`) and renews it on its own.

Only 443 is exposed: the tracker authenticates every frame with its key, the app with passkeys
or password + TOTP; Traefik and the backend rate-limit requests per address.

## 3. Start

```sh
docker compose --profile traefik up -d --build
docker compose exec backend node scripts/create-admin.ts admin@mydomain.com "Name"
```

The image builds the Flutter web app and serves it from the same backend. The database
migrations run at startup. `create-admin` prints an **invitation link**: open it, choose the
password and set up the authenticator app (2FA is mandatory). Then add a passkey to sign in
with fingerprint or screen lock.

To avoid building on the server use the release image: see [Updates](updates.md).

## 4. Users and access

- No public sign-up: the administrator invites the users from **Account → Administration**
  and sends the link (valid 72 hours, single use). No email server needed.
- Sign-in with a **passkey** (fingerprint/face, also synced on Google/Apple) or **password +
  TOTP**. 2FA is mandatory.
- 10 single-use **recovery codes**; if phone and codes are lost, the administrator creates a
  reset link (new password and new 2FA).
- Sensitive changes (password, passkeys, codes, TOTP app) ask for the TOTP code again when the
  sign-in is older than 15 minutes.
- Every user sees only their own devices and the ones shared with them. The administrator
  manages the users but doesn't see their devices.
- **Language**: Italian and English, taken from the phone or the browser at the first sign-in
  and saved in the account; push notifications arrive in the language of the user.

## 5. First tracker

Provisioning (key of the tracker, label with the QR code) is described in
[Firmware](../firmware/index.md#provisioning). The user then adds the tracker from **Devices →
Add** with the guided procedure.
