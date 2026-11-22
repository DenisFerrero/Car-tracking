# New tracker

From the freshly assembled board to the tracker sending positions to the app. You need the
server already installed ([Installation](../server/install.md)), a board from the
[catalog](index.md) and a data SIM with the PIN disabled or known.

## 1. Hardware

1. Assemble the board following its page (for the LilyGO:
   [bill of materials and wiring](lilygo-t-call-a7670-v1-0.md)), with the
   [power board](carrier-board.md) if it goes on the car battery.
2. Insert the SIM and connect the GNSS and LTE antennas: without an antenna the modem doesn't
   register on the network and the GNSS doesn't find the satellites.
3. Note the IMEI printed on the module (the serial port at 115200 baud shows it at start too).

## 2. Key and pairing code

On the server, with the IMEI:

```sh
docker compose exec backend node scripts/provision.ts 863820040182648 --label /tmp/label.svg
docker compose cp backend:/tmp/label.svg .
```

It prints the key of the tracker (`DEVICE_KEY`), the pairing code and the SVG label with QR
code, IMEI and code. The server stores nothing: key and code derive from
`CRYPTO_MASTER_KEY` and the IMEI, so the command can be repeated whenever needed.

## 3. Firmware

1. Copy `firmware/secrets.example.h` to `firmware/secrets.h` and fill in `DEVICE_KEY`, the
   APN of the carrier and the PIN if any (and the WiFi network if `CONNECTION_MODE` uses WiFi).
2. In `firmware/configurations.h` set `BOARD`, `SERVER_HOST` (the `DOMAIN` of the server) and,
   if needed, sampling and sensors ([options](../firmware/index.md#configuration)).
3. Compile and flash over USB (board *ESP32 Dev Module*, partitions with two OTA slots):

    ```sh
    arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs firmware \
      --library <LilyGo-Modem-Series>/lib/TinyGSM
    arduino-cli upload --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs -p COM5 firmware
    ```

At the first start the firmware saves the key and the network settings in NVS: later remote
updates use the official images without credentials
([OTA](../firmware/index.md#remote-updates-ota)).

Put the label on the case of the tracker. The code proves physical possession: knowing just
the IMEI isn't enough to add it.

## 4. Pairing in the app

*Devices → Add → Tracker*:

1. **Label**: scan the QR code or type IMEI and code, then *Verify*.
2. **Vehicle**: choose where you install it.
    - *New vehicle*: name and color on the map.
    - A **vehicle you already have** without a tracker (for example one created for the
      [phone](../app/phone-vehicles.md)): history, km, deadlines, costs and shares stay and
      from now on the tracker feeds them.
3. **Power on**: power the tracker outdoors, under open sky. The app waits for the first
   connection in realtime; the first GNSS fix can take a few minutes.
4. **Done**: open the vehicle for the live position.

The tracker can also be powered before the pairing: it connects, but the positions sent
before are shown to nobody.

## 5. Installation in the car and check

- Connect the power and, if present, the ignition wire (`IGNITION_ACTIVE_LEVEL`): with the
  ignition off the tracker saves energy.
- In the *Live* tab check signal, satellites and voltage; try *Locate*.
- In *Settings* choose the alarms to receive (movement, lifting, power disconnected...).

| Problem | Check |
| :--- | :--- |
| The app stays on «Waiting for the first connection» | Serial: network registration, APN, PIN; the server reachable at `https://DOMAIN` |
| `invalid_pairing` | IMEI and code of the label, `CRYPTO_MASTER_KEY` unchanged since the provisioning |
| Connected but no position | GNSS antenna, open sky; without a fix the cell position arrives |
| «The tracker belongs to another account» | The tracker still belongs to someone: it must be removed from that account |

## Moving the tracker to another vehicle

The data belong to the **vehicle**, not to the tracker. From *Settings → Tracker* of the
vehicle:

- **Move to another vehicle**: choose one of your vehicles without a tracker or create a new
  one. The previous vehicle keeps its history, km, deadlines, costs and shares, without a
  tracker; with *Archive this vehicle* it disappears from the map and from the choice of the
  phone but stays in the device list (at the bottom). Pending commands are cancelled.
- **Remove the tracker from the vehicle** (car sold, tracker to reuse): the vehicle stays
  without a tracker and the tracker becomes free; anyone with the label can pair it again.
- **Delete the vehicle** (*Danger zone*): deletes the vehicle with all its history; the
  tracker becomes free.

An archived vehicle is restored with the *Archived* switch in its settings and becomes active
again automatically when it receives a tracker. The *Installed trackers* list shows which
tracker was in the vehicle and when.

The tracker doesn't need reflashing: the server closes its connection and at the next one the
ACK carries the id of the new vehicle ([protocol](../reference/protocol.md#flow)).
