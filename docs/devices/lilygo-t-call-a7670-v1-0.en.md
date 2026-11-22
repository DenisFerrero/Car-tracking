# LilyGO T-Call A7670 V1.0

<span class="status supported">SUPPORTED</span> · board file
`firmware/boards/lilygo_t_call_a7670_v1_0.h` · driver `firmware/modem_a76xx.cpp` · variants
`lilygo-sim`, `lilygo-wifi-sim`

ESP32 with a SIMCom A7670 modem (LTE Cat-1). The firmware uses 4G only (`MODEM_LTE_ONLY`).

!!! warning "GNSS"
    Only the **A7670E-FASE** and **A7670SA-FASE** versions of the modem have a built-in GNSS
    (check with `AT+SIMCOMATI`). The global **A7670G** version doesn't: it needs an external
    GNSS module (`GNSS_SOURCE_EXTERNAL`, see the
    [power board](carrier-board.md#7-external-gnss-optional-not-fitted)).

## Bill of materials

### Main parts

| # | Part | Role | Qty | Indicative price |
| :---: | :--- | :--- | :---: | :---: |
| 1 | **LilyGO T-Call A7670 V1.0** | ESP32 with LTE modem and built-in GNSS (*-FASE* versions) | 1 | ~€ 25–35 |
| 2 | **BMP390** | Pressure and temperature (I2C) | 1 | ~€ 5–10 |
| 3 | **LIS3DH** | Low-power accelerometer (I2C), wake-up on movement on INT1 | 1 | ~€ 3–8 |

### Power and protection (basic build)

| # | Part | Role | Qty | Indicative price |
| :---: | :--- | :--- | :---: | :---: |
| 4 | **12V → 5V buck converter, ≥ 1A** | Powers the T-Call from the car | 1 | ~€ 2–5 |
| 5 | **Inline fuse holder + 1A fuse** | Protection on the +12V | 1 | ~€ 1–3 |
| 6 | **PC817 optocoupler** *(recommended)* | Isolates the ignition from GPIO 32 | 1 | ~€ 0.50–1 |
| 7 | **1 kΩ resistor** | Limits the current in the LED of the optocoupler | 1 | ~€ 0.10 |
| — | *Alternative: 12 kΩ + 3.3 kΩ resistors* | Divider for the ignition without optocoupler | 1+1 | ~€ 0.20 |

For a permanent installation, with a backup battery and *load dump* protection, use the
[power board](carrier-board.md).

### Connectivity and accessories

| # | Part | Role | Qty | Indicative price |
| :---: | :--- | :--- | :---: | :---: |
| 8 | **IoT/M2M data SIM** | 100-200 MB per month are enough (see [data usage](../reference/data-usage.md)) | 1 | ~€ 5–15/year |
| 9 | External GNSS antenna *(optional)* | Better reception under the dashboard | 1 | ~€ 3–8 |
| 10 | External LTE antenna *(optional)* | Weak coverage | 1 | ~€ 3–8 |
| 11 | Wires, perfboard, enclosure | Assembly | — | ~€ 7–20 |

**Estimated cost**: ~€ 40–55 for the minimal build, ~€ 55–80 with optocoupler, antennas and
enclosure (under € 40 from Asian marketplaces). IoT operators such as Onomondo, 1NCE or Tele2
IoT offer plans for a few euros a year.

## Wiring

| Line | Sensor pin | T-Call pin | Notes |
| :--- | :--- | :--- | :--- |
| Sensor power | VCC / VIN | **3V3** | 3.3V |
| Ground | GND | **GND** | Common |
| I2C data | SDA | **GPIO 21** | BMP390 + LIS3DH |
| I2C clock | SCL | **GPIO 22** | BMP390 + LIS3DH |
| LIS3DH alarm | INT1 | **GPIO 33** | Wake-up on movement |
| Ignition | signal | **GPIO 32** | Through the optocoupler or the divider |
| PGOOD *(power board)* | — | GPIO 34 | Power cut |
| Battery voltage *(power board)* | — | GPIO 35 | ADC1 |

Don't use GPIO 4, 12, 13, 14, 25, 26 and 27 (modem and LED) nor 16/17 (PSRAM).

```text
+------------------+          +------------------+
|   LIS3DH (Acc.)  |          |   BMP390 (Baro.) |
+--+---+---+---+---+          +--+---+---+---+---+
   |   |   |   |                 |   |   |   |
  3V3 GND SDA SCL               3V3 GND SDA SCL
   |   |   |   +--------+--------|---|---|---+--> GPIO22
   |   |   +------------|--------|---|---+------> GPIO21
   +---|----------------|--------+---|----------> 3V3
       +----------------|------------+----------> GND
  INT1 -----------------+-----------------------> GPIO33 (anti-theft wake-up)

  Ignition (+12V) --[ optocoupler ]-------------> GPIO32 (ignition)
```

## Ignition input (+12V → 3.3V)

The ESP32 accepts at most 3.3V on its GPIOs: the car voltage (12-14.4V) burns it.

**Option A, optocoupler (recommended)**: +12V ignition → **1 kΩ** resistor → anode of the LED
of the PC817, cathode to ground. ESP32 side: collector to GPIO 32, emitter to GND, with the
internal pull-up. The signal is active low: `IGNITION_ACTIVE_LEVEL LOW` (the firmware keeps the
pull-up on during deep sleep too). The [power board](carrier-board.md) uses an emitter follower
instead, active high.

**Option B, divider (cheap)**: R1 **12 kΩ** to the +12V, R2 **3.3 kΩ** to ground, middle point
to GPIO 32 with `IGNITION_ACTIVE_LEVEL HIGH`: about 2.6V at 12V and 3.1V at 14.4V. With 10 kΩ
instead of 12 kΩ it would reach 3.57V, at the absolute limit of the ESP32.

## Firmware

```c
// firmware/configurations.h
#define BOARD BOARD_LILYGO_T_CALL_A7670_V1_0
```

- Build with the TinyGSM library of LilyGO (repository
  [Xinyuan-LilyGO/LilyGo-Modem-Series](https://github.com/Xinyuan-LilyGO/LilyGo-Modem-Series),
  folder `lib/TinyGSM`), commenting out `COMPILING_WITH_STANDARD_TINYGSM`. Board *ESP32 Dev
  Module*, partition scheme with two OTA slots (default or *Minimal SPIFFS*).
- Configuration, provisioning and updates: see [Firmware](../firmware/index.md).

## V1.1 version

The V1.1 of the T-Call uses different pins and GPIO 32/33 are taken by the modem: it needs its
own board file. The firmware fails to compile when the configuration isn't compatible.
