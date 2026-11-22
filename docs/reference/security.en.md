# Security

- **Key per device**: `HMAC-SHA256(CRYPTO_MASTER_KEY, IMEI)`. The key extracted from a tracker
  doesn't allow forging the data of the others.
- **TLS** up to the proxy (`wss://`, verified certificate), on top of the end-to-end
  encryption of the frames.
- **Unique nonces**: persistent counter + timestamp + direction (uplink/downlink). The
  downlink counter is shared by ACKs and commands; the tracker drops commands with a counter
  that doesn't grow.
- **No plaintext fallback**: unauthenticated frames are dropped.
- **Replay**: a repeated frame produces the same points, ignored by the `(device_id, time)`
  primary key.
- **Tracker gateway**: no password, the key is the credential: the first frame must be a HELLO
  authenticated with the key of its IMEI, otherwise the connection is closed and the attempt
  counted. Then only TELEMETRY, COMMAND_RESULT, UPDATE_CHECK and EXTRA with the id of the
  authenticated device are accepted (any other frame closes the connection); frames of at most
  1 KB, bounded queue, a single connection per tracker (the new one replaces the old one).
- **Web and app**: argon2id passwords, mandatory TOTP (anti-replay, AES-GCM encrypted secret),
  WebAuthn passkeys, temporary lockout after failed attempts and rate limits. Opaque sessions
  (only the hash in the database): `HttpOnly`/`Secure`/`SameSite=Strict` cookies with an Origin
  check in the browser, bearer token in the app. Strict CSP, HSTS. Every API checks access to
  the single device (404 for other people's) and realtime reaches only the users of the
  device.
- **Phones**: positions are uploaded with an upload token valid only for that phone, renewed
  at every start of the sharing; a fix can name only a vehicle owned by the owner of the
  phone, others are skipped.
- **Transport**: REST over HTTPS (HTTP/2 via Traefik, compression) for requests and a single
  WebSocket (`/api/live`) for realtime: positions, state, commands, notifications, shares
  granted or revoked. Less latency and overhead than polling, and no extra protocols to
  protect.
- **Validation**: every call (body, query, parameters and WebSocket messages) is validated
  with *strict* zod schemas: unknown fields, wrong types and out-of-range values are rejected
  with 400 before reaching the logic.
- **Rate limits and DoS**: global per-IP limit (`RATE_LIMIT`, 300/min) applied **before**
  authentication, so anonymous requests and fake tokens consume it too; tight limits on
  sign-in, TOTP, recovery, invitations and friend codes (`AUTH_RATE_LIMIT`; codes have 50
  random bits). Body of at most 64 KB, request and connection timeouts, a limit of realtime
  connections per user, `__proto__`/`constructor` rejected in JSON. In front, Traefik limits
  requests per second and concurrent requests per IP, and separately connections to
  `/tracker` (10/min per IP); the gateway accepts 30 connections a minute per IP and bans for
  30 minutes whoever sends 10 invalid HELLOs.
- **Database**: TimescaleDB hypertables compressed after 7 days, retention `RETENTION_DAYS`
  (`PHONE_RETENTION_DAYS` for the personal positions of phones). The hypertables
  (`positions`, `traffic`) have no foreign key to `devices`: creating a new chunk would add the
  key trigger, locking `devices` and deadlocking with command delivery. The backend cleans the
  data up when a device is removed.
- **Dependencies**: exact versions published at least 14 days earlier, transitive ones too
  (`overrides` in `backend/package.json`, `dependency_overrides` in `app/pubspec.yaml`), with
  no known vulnerabilities (`npm audit`, OSV). The `.dockerignore` keeps secrets, `.env` and
  database data out of the build context.
