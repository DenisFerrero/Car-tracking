# Firmware

Arduino firmware for the ESP32 (`firmware/`): GNSS with adaptive sampling, batched upload over
an encrypted WebSocket, offline queue in flash, anti-theft, deep sleep, remote updates. The
board is chosen with `BOARD` in `firmware/configurations.h` (see the
[catalog](../devices/index.md)).

## Configuration

| File | Content |
| :--- | :--- |
| `firmware/configurations.h` | Board, server, sampling, sensors, options (versioned) |
| `firmware/config_defaults.h` | Default value of every option |
| `firmware/secrets.h` | Tracker key, WiFi, APN, PIN (from `secrets.example.h`, excluded from git) |
| `firmware/release/` | Configuration of the official images (no credentials) |

Main options: `SERVER_HOST` (= `DOMAIN`), `CONNECTION_MODE` (SIM, WiFi, WiFi + SIM),
`BATCH_SIZE`, `THRESHOLD_DISTANCE`, `IGNITION_ACTIVE_LEVEL`, `VEHICLE_VOLTAGE_SENSE`,
`POWER_GOOD_SENSE`, `GNSS_SOURCE`, `OWNER_TAG`, `AUTO_UPDATE`.

## Provisioning

Every tracker has its own key, derived from `CRYPTO_MASTER_KEY` and its IMEI (printed on the
module or shown on the serial port at startup):

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

1. Copy `firmware/secrets.example.h` to `firmware/secrets.h` and fill in `DEVICE_KEY` and the
   APN. Nothing needs registering on the server: the backend derives the key from the IMEI
   again.
2. Adjust `firmware/configurations.h` (board, `SERVER_HOST`, port 443, sampling) and flash the
   board.
3. Print the label (`--label`, SVG with QR code, IMEI and code) and stick it on the tracker.
4. The user opens **Devices → Add**: the guided procedure reads the QR (or IMEI and code by
   hand), asks for name and color and waits for the first connection. The code proves
   physical possession: knowing just the IMEI isn't enough.

At the first start the firmware saves the key and the network settings (server, WiFi, APN,
PIN) in NVS: images without credentials take them from there.

## Remote updates (OTA)

### From the GitHub releases

With `GITHUB_REPO=<owner>/<repository>` the backend reads the latest release every 6 hours.
The `firmware-<variant>.bin` images attached by the pipeline join the available updates
(checked against the SHA-256 computed by GitHub) and the owners of the trackers of that
variant get the *New firmware* notification. Immediate check:
`POST /api/admin/releases/check` (administrator).

The official images are built with `SERVER_HOST ""` and without key, WiFi or APN
(`firmware/release/`): they use the settings saved in NVS by the first installation. The first
installation is therefore over USB with a personal build of the same variant
(`FIRMWARE_VARIANT "lilygo-sim"` or `"lilygo-wifi-sim"`).

### Automatic updates

Builds with `AUTO_UPDATE 1` (the official images) send once a day, after the ACK, an
`UPDATE_CHECK` frame (~100 B, ~3 KB a month). Unless the owner turned them off (*Settings →
Automatic updates*) the server offers the latest version of the variant and the tracker
installs it on its own (~1.3 MB of SIM per update). An image that already failed on that
tracker isn't offered again.

**Custom firmware**: keeps `AUTO_UPDATE 0` and never asks for updates, so a modified version
isn't replaced by the official one; manual installation stays possible.

### By hand, without GitHub

1. Build with an all-zero `DEVICE_KEY`, the new `FIRMWARE_VERSION` and the `FIRMWARE_VARIANT`
   of the trackers, with a partition scheme with two OTA slots.
2. Upload it to the server:
   ```sh
   docker compose cp build/firmware.ino.bin backend:/tmp/fw.bin
   docker compose exec backend node scripts/firmware.ts /tmp/fw.bin 2.4.0 default "Notes"
   ```
3. The owner opens the tracker *Settings* → *Install*.

### How it works

On connection the tracker gets the offer (signed with its key), downloads the image in 1 KB
blocks, checks the SHA-256, writes it to the free slot and restarts. The new firmware becomes
final only at the first ACK of the server: if it can't connect the bootloader goes back to the
previous version (state *not applied*). The download lasts at most `OTA_MAX_SEC` (15 minutes)
per cycle and resumes from where it got to.

## Power management and anti-theft

| Event | Behavior |
| :--- | :--- |
| Ignition on | Sampling every 5 s, batched upload, offline queue without network |
| Ignition off (after 5 s) | Parking position and queue, then deep sleep |
| Every 4 hours | Wake-up, standby position (heartbeat), back to deep sleep |
| Movement (LIS3DH) | Alarm: tracking for 60 s, extended while the car moves (max 15 min) |
| Car lifted | Tilt beyond 4° from the parked one (tow truck, jack) |
| Power cut | With the [power board](../devices/carrier-board.md): alarm and tracking on battery |
| Key fob nearby | With `OWNER_TAG` the movement is ignored ([details](../devices/owner-beacon.md)) |
| Anti-theft paused | `ANTITHEFT` command: no alarm until it expires |

- Movement detection arms 3 minutes after the ignition goes off and pauses for 10 minutes
  after an alarm, to limit data on false alarms.
- Without a GPS fix heartbeats and alarms use the last known position, marked *stale*, with
  the serving cell.

## Extra data

`uplinkQueueExtra("{\"rpm\":820}")` queues a JSON object (at most 400 bytes) read from another
board of the vehicle; it's sent as soon as the connection is ready (`EXTRA` frame, see the
[protocol](../reference/protocol.md#extra-data-extra)). Reading from the external board (e.g.
serial) is still to be written: protocol, backend and app don't change when fields are added.

## TLS

The tracker connects over `wss://` on port 443 and verifies the certificate with the root CAs
of `firmware/certificates.h` (Let's Encrypt, Google Trust Services, SSL.com). The file is
regenerated with `npm run ca-bundle` (`backend` folder).
