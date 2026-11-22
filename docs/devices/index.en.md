# Device catalog

The boards the firmware supports and how to build a tracker with each of them. The catalog
grows with the firmware: every new board gets its row here and its page.

## Boards

| Board | Status | Modem / network | GNSS | Release variants | Page |
| :--- | :--- | :--- | :--- | :--- | :--- |
| LilyGO T-Call A7670 V1.0 | <span class="status supported">SUPPORTED</span> | SIMCom A7670E/SA/G, LTE Cat-1 (4G only) | Built in on the *-FASE* versions, external with the A7670G | `lilygo-sim`, `lilygo-wifi-sim` | [Details](lilygo-t-call-a7670-v1-0.md) |
| LilyGO T-Call A7670 V1.1 | <span class="status planned">PLANNED</span> | Like the V1.0, different pins | Like the V1.0 | — | Needs its own board file |

**Status**: *supported* = in the firmware, built by the CI, official images in the releases;
*experimental* = in the firmware, no official images; *planned* = not in the firmware yet.

## Accessories

| Accessory | Purpose | Page |
| :--- | :--- | :--- |
| Power board | 12V of the car, protections, backup battery, voltage sensing, isolated ignition | [Details](carrier-board.md) |
| Owner key fob | Ignores movement alarms when the owner is nearby | [Details](owner-beacon.md) |
| LIS3DH and BMP390 sensors | Movement and lift (anti-theft), pressure and temperature | On the board page |

## Without hardware

The Android phone can act as a tracker for the person or for a vehicle, with trips, costs and
deadlines but no anti-theft: see [Phone and vehicles](../app/phone-vehicles.md).

## Variants of the official images

The releases hold a `firmware-<variant>.bin` image per variant. The tracker accepts updates
only of its own variant (`FIRMWARE_VARIANT`), so the first installation over USB must be a
personal build of the same variant.

| Variant | Board | Connection |
| :--- | :--- | :--- |
| `lilygo-sim` | LilyGO T-Call A7670 V1.0 | SIM only (LTE) |
| `lilygo-wifi-sim` | LilyGO T-Call A7670 V1.0 | WiFi when available, SIM otherwise |

## Adding a board to the firmware

1. Write `firmware/boards/<board>.h` with all the `BOARD_*` macros listed in
   `firmware/boards/lilygo_t_call_a7670_v1_0.h` (name, modem family, GNSS, pins).
2. Register it in `firmware/board.h`.
3. If the modem belongs to a new family, add `firmware/modem_<family>.cpp` implementing
   `firmware/modem.h`.
4. For the releases: `firmware/release/<variant>.h` and the variant in the matrix of
   `.github/workflows/release.yml`.
5. Document it here: row in the table, page with bill of materials, wiring and notes (see
   `CLAUDE.md`).
