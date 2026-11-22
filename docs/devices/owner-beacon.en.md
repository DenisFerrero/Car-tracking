# Owner key fob

<span class="status experimental">DESIGN</span> · optional · sketch in `hardware/owner-beacon/`

With `OWNER_TAG` the tracker, when it wakes up for a movement, looks for the key fob of the
owner over Bluetooth for 4 seconds and, if it finds it, ignores the alarm (tilt and power cut
always raise the alarm).

**Samsung SmartTag, AirTag and similar can't be used**: for privacy they change Bluetooth
address and identifiers about every 15 minutes, with keys known only to the ecosystem of the
maker. Two options are left:

| `OWNER_TAG` | Key fob | Security |
| :---: | :--- | :--- |
| 1 | Any BLE tag with a fixed address (cheap iBeacon/Eddystone beacons, ~€5). The address, read with the *nRF Connect* app, goes in `OWNER_TAG_ADDRESS` | Low: the address can be read from afar and cloned with a phone |
| 2 | Beacon of this project, `hardware/owner-beacon` | HMAC-SHA256 rolling code with a shared key (`OWNER_TAG_KEY` / `TAG_KEY`), a recorded code isn't valid a second time |

Beacon (`OWNER_TAG 2`):

- **Seeed XIAO nRF52840** (~€10), *Seeed nRF52 Boards* core (not the mbed one), sketch
  `hardware/owner-beacon/owner-beacon.ino`; copy `secrets.example.h` to `secrets.h` with the
  same key as the tracker (`openssl rand -hex 32`)
- 3.7V LiPo battery 100-150 mAh on the `BAT+`/`BAT-` pads, charged from the USB-C of the XIAO
- 3D-printed key fob shell or a 30×25×10 mm box
- advertising every second, new code every 30 seconds. The counter is saved in flash in
  one-day blocks: after a reset it jumps forward and never repeats

> The consumption of the beacon and the real range in the car still have to be measured: they
> haven't been verified. `TX_POWER` reduces the range (e.g. -8 dBm, only near the door). The
> Bluetooth stack takes ~740 KB of flash on the tracker: with `OWNER_TAG` on choose the
> *Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)* partition scheme; the offline queue
> shrinks on its own to about 1200 points.
