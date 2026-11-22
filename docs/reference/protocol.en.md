# Binary protocol (v2)

Every message is a binary frame encrypted with **ChaCha20-Poly1305** (RFC 8439). The full
specification is in `backend/src/protocol/protocol.ts`, the firmware implementation in
`firmware/protocol.cpp`.

| Field | Size | Notes |
| :--- | :--- | :--- |
| Header | 1 B | version (4 bits) + kind: HELLO, TELEMETRY, ACK, COMMAND, COMMAND_RESULT, FW_*, UPDATE_CHECK, EXTRA |
| Device | 8 B / 1-2 B / 0 | HELLO: IMEI; TELEMETRY, COMMAND_RESULT, UPDATE_CHECK and EXTRA: id (varint); ACK and COMMAND: none (the connection identifies it) |
| Counter | 4 B | never repeated with the same key (reserved in blocks in NVS) |
| Timestamp | 4 B | UNIX seconds of the first point |
| Payload | variable | encrypted, header used as AAD (authenticated) |
| Tag | 8 B | truncated Poly1305 (forgery probability 2⁻⁶⁴) |

In the TELEMETRY payload points are encoded as **differences from the previous point**
(zigzag varints): coordinates at 1e-5 degrees (~1 m), altitude in meters, pressure in tenths
of hPa, temperature in tenths of °C, speed in km/h. Then, when present, satellites, signal
power (dBm), car battery voltage, events (movement, car lifted, power cut, low battery),
serving cell and the *stale* flag. A full point costs ~22 bytes, the following ones ~8-10
bytes.

## Channel

One WebSocket per tracker on `/tracker`, one frame per binary message. Every connection starts
with the HELLO (within 10 s), the server answers with the ACK and then sends the pending
commands; then come telemetry, command results, the daily update request (`UPDATE_CHECK`, no
payload) and extra data (`EXTRA`). Keepalive with WebSocket pings (`KEEP_ALIVE_SEC`, 60 s when
the server is silent); the server closes connections silent for 3 minutes.

## Extra data (EXTRA)

The payload is a UTF-8 JSON object (at most 400 bytes on the firmware, 50 fields, any values,
nested too); the timestamp is the time of the reading (without a valid time the server uses
the time of reception). Cost: ~95 bytes on the wire plus the JSON.

## Commands to the tracker

Commands wait in the database. As soon as the tracker is connected and got the ACK, the
backend sends a COMMAND frame with all the pending commands; the tracker applies them only
once (growing counter saved in NVS) and answers with COMMAND_RESULT. A new command replaces the
pending ones of the same kind; durations are relative to the time of the frame.

| Command | Parameter | Effect |
| :--- | :--- | :--- |
| `LIVE` | seconds (0 = stop) | Every sample is recorded and sent at once |
| `ANTITHEFT` | seconds (0 = re-arm) | Alarms suspended (e.g. car at the mechanic) |
| `LOCATE` | - | One position as soon as possible (expires after an hour) |

With the car parked the tracker sleeps: a command arrives at the next wake-up.

**Clock**: UTC time comes from the GNSS or, without a fix, from the authenticated timestamp of
ACKs and commands (forward only).

## Flow

1. **Registration**: at every start the tracker sends a HELLO encrypted with its key; the
   server derives the key from the IMEI, checks the tag and answers with an ACK with the id.
2. **Telemetry**: GPS read every 5 seconds with **adaptive sampling** (10 m tolerance): every
   sample in bends, one every 30 seconds on straight roads; batched upload (`BATCH_SIZE` 3, or
   after 30 seconds).
3. **Offline queue**: without network points go to flash (LittleFS, 192 KB ≈ 4900 points) and
   when the network is back they leave in a few large frames.
4. **Without a fix**: points carry the last known position marked *stale* and the serving
   cell (`AT+CPSI?`), from which the server can estimate the position. While driving one
   every `CELL_FALLBACK_INTERVAL_SEC` (60 s) without a fix.

## Phones

Phones don't use this protocol: they send positions as JSON over HTTPS
(`POST /api/phones/positions`) with the upload token of the phone; every point can name the
vehicle of the user it's shared from (`vehicleId`).
