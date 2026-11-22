# Power and I/O board

<span class="status experimental">DESIGN</span> · for the [LilyGO T-Call A7670 V1.0](lilygo-t-call-a7670-v1-0.md) · bill of materials in `hardware/bom.csv`

Perfboard to place next to the LilyGO T-Call A7670 V1.0. It connects the tracker to the 12V
system of the car and adds:

- protection from overvoltage (load dump), reverse polarity and short circuits
- backup battery: the tracker keeps working if the thief cuts the power, and reports it
  (`POWER_LOST` event)
- measurement of the car battery voltage (`LOW_BATTERY` events)
- ignition input isolated with an optocoupler
- connectors for the LIS3DH accelerometer and the BMP390 barometer
- provision for an external GNSS module (optional, not fitted)

The features are already in the firmware, disabled in `firmware/configurations.h` (see
[Enabling in the firmware](#enabling-in-the-firmware)).

> Design not built nor tested yet: check every connection with a multimeter before connecting
> the board, and power it the first time from a current-limited bench supply (12V, 0.5A)
> instead of the car battery.

## Why this architecture

The T-Call A7670 V1.0 **has no battery input**: it's powered only at 5V from USB-C (brought out
on the `VBUS` pin of the header). The 5V feeds an SY8089 buck (4.2V for the modem) and an
ME6217 LDO (3.3V for the ESP32). Both also work with an input from 3.5V to 5V, so `VBUS` can be
fed directly from the output of a charger with *power path* (load sharing):

- ignition on or off, with the car connected: the charger output is 4.4V and meanwhile the
  battery charges
- power cut: the output moves seamlessly to the battery (3.5-4.2V)

```text
 +30 (battery) ──F1 2A──┬──────────────┬──D1──┬── C1/C2 ──[ BUCK 5V ]──[ bq24074 ]──OUT 4.4V──┬── VBUS T-Call
                        │              │      │            U1            U2  │            C5   │
                      TVS1          R1/R2                                 LIPO │                 ├── 3V3 (from the T-Call) → sensors
                    5KP24A        470k/100k                             18650 + NTC              │
                        │              │                                  PGOOD ─────────────────┼── GPIO 34
 GND (ground) ──────────┴──────────────┴──────────────────────────────────┴──────────────────────┴── GND
                                       └──────────────────────────────────────────────────────────── GPIO 35 (ADC)

 +15 (ignition) ──F2 1A──D2──R3 4.7k──[ PC817 LED ]── GND
                                       [ PC817 transistor ]: collector 3V3, emitter → GPIO 32 (+ R4 10k to GND)
```

## Blocks

### 1. Input and protections

```text
+30 ──[F1 2A, inline fuse holder on the harness]──┬──────────── VPROT node ──[D1 SB3100 →]── VIN_BUCK
                                                  │                                              │
                                           TVS1 5KP24A                               C1 100µF 63V (105°C)
                                           (cathode on VPROT)                        C2 1µF 100V ceramic
                                                  │                                              │
GND ──────────────────────────────────────────────┴──────────────────────────────────────────────┘
```

| Part | Choice | Reason |
| :--- | :--- | :--- |
| **F1** | 2A blade fuse in an inline holder, taken with an *add-a-fuse* from an always-on circuit | Protects the car harness from short circuits. It's also the "sacrificial fuse" of the TVS |
| **TVS1** | **5KP24A** (5000 W, 24V standoff, ~39V clamping) | On an old car the alternator may lack *load dump* suppression: disconnecting the battery with the engine running can give 80-100V for hundreds of ms. The 24V standoff tolerates a jump start with a 24V booster. With reverse polarity it conducts forward and blows F1 |
| **D1** | **SB3100** (3A 100V Schottky) | Reverse polarity protection with no quiescent draw, about 0.4V drop |
| **C1/C2** | 100µF 63V low-ESR **105°C** electrolytic, 1µF 100V ceramic | Reserve for noise and short dips. Cars need high-temperature parts |

The highest voltage after the TVS (about 39V during a surge) stays below the 50V maximum of
the regulator.

### 2. 5V regulator

**U1: Pololu D36V28F5** (input 5.3-50V, output 5V up to 3.2A, built-in reverse protection).
Output to the `VBUS` input of the charger.

- While cranking the voltage can fall to 6-8V (even lower with old batteries): the regulator
  turns off but the backup battery powers the tracker without interruption.
- Quiescent current: at most 3 mA according to the maker. With the rest of the board, an
  estimated 3-5 mA idle, about 2-4 Ah a month: fine for a car used regularly (a 45 Ah battery
  loses less than 10% in a month). **Measure it** on the finished board.

### 3. Backup battery and charger

**U2: Adafruit bq24074** (Universal USB / DC / Solar Lithium charger, product 4755).

| Setting | Value | How |
| :--- | :--- | :--- |
| Charge current | **500 mA** | Cut the trace of the 1.0A jumper and close the 0.5A one: less heat and less load on the regulator |
| Thermistor | 10k NTC glued to the cell | Cut the `THERM` jumper and connect the NTC between `THERM` and GND. The charger stops charging outside the safe temperature range (about 0-50°C) |
| Output | `OUT` → `VBUS` of the T-Call | At most 4.4V with the car connected, the battery voltage without |
| State | `PGOOD` → GPIO 34 | Open drain, low while powered. Pull-up R5 470k to 3V3 (GPIO 34 has no internal pull-ups) |

**Battery: protected 18650 Li-ion cell** (with a built-in protection circuit), e.g. Samsung
35E, LG MJ1 or Panasonic NCR18650B in the protected version, in a holder with wires.

- **Temperature**: in summer the cabin goes beyond 70°C. A steel cylindrical cell is sturdier
  than a pouch LiPo, the thermistor stops charging when hot, and discharging is allowed up to
  about 60°C. **Mount the board low, under the dashboard or under a seat, never in the sun**. A
  LiFePO4 would be safer with heat but needs another charger (3.6V instead of 4.2V).
- **Autonomy** without the car (estimates, to be verified): 10-15 hours of continuous
  tracking, or several weeks in deep sleep with heartbeats.
- **Modem peaks**: the firmware uses 4G only (`MODEM_LTE_ONLY`), where peaks stay around 1A.
  In 2G (fallback with `MODEM_LTE_ONLY 0`) the modem draws pulses up to 2A, beyond the 1.5A of
  the charger. **C5, 2200µF 6.3V low-ESR, must be soldered close to the `VBUS` pin of the
  T-Call** anyway: it's cheap and also covers the turn-on transients of the modem.

> Don't connect the USB-C of the T-Call to the PC while the board is powered: the two sources
> would be in parallel. To flash the firmware disconnect the `VBUS` connector of the carrier
> (or the whole carrier).

### 4. Battery voltage sensing

```text
VPROT (before D1) ──R1 470k 1%──┬── GPIO 35
                                │
                            R2 100k 1%  C3 100nF
                                │        │
GND ────────────────────────────┴────────┘
```

- Ratio (470k + 100k) / 100k = 5.7: 14.4V becomes 2.53V, measurable up to about 17V.
- Continuous draw 25 µA. C3 filters noise and provides the charge for the ADC sampling,
  despite the high impedance of the divider.
- During a surge clamped by the TVS (39V) the pin gets about 75 µA through R1, absorbed by the
  protection diodes of the ESP32.
- **GPIO 35 belongs to ADC1**: ADC2 doesn't work with WiFi on.
- Calibration: measure the battery with a multimeter and set
  `VEHICLE_VOLTAGE_CALIBRATION = real voltage / read voltage`.

### 5. Ignition input (optocoupler)

```text
+15 ──F2 1A──D2 1N4007 →──R3 4.7k 1W──[A  PC817  K]── GND

3V3 ──[C  PC817  E]──┬── GPIO 32
                     │
                 R4 10k  C4 100nF
                     │    │
GND ─────────────────┴────┘
```

- **Active high output** (emitter follower): with the ignition on GPIO 32 reads about 3.1V, so
  `IGNITION_ACTIVE_LEVEL HIGH` stays and deep sleep needs no internal pull-up.
- LED current: 2.7 mA at 14.4V, 1.5 mA at 9V (cranking). With a minimum CTR of 50% the
  transistor gives more than the 0.33 mA needed.
- D2 protects from reverse polarity. The 1W R3 withstands load dump surges (up to 1.6W for
  400 ms).
- Galvanic isolation keeps the noise of the car away from the ESP32.

### 6. Sensors

| Module | Wiring |
| :--- | :--- |
| LIS3DH (e.g. Adafruit 2809) | 3V3, GND, SDA → GPIO 21, SCL → GPIO 22, **INT1 → GPIO 33** |
| BMP390 (e.g. Adafruit 4816) | 3V3, GND, SDA → GPIO 21, SCL → GPIO 22 |

Mount the accelerometer **rigidly** on the board and the board rigidly to the car: lift
detection compares the tilt with the parked one (4° threshold), so a loose board causes false
alarms.

### 7. External GNSS (optional, not fitted)

Needed with a modem without GNSS, e.g. the **A7670G** (worldwide LTE bands, no built-in GNSS),
or for a faster and more precise fix.

```text
3V3 ──[S  Q1 AO3401A  D]──── VCC of the GNSS module
           G
           ├── R6 100k ── 3V3      (off by default)
           └── GPIO 23             (LOW = on)

GPIO 18 (ESP32 RX) ←── module TX
GPIO 19 (ESP32 TX) ──→ module RX
3V3 always on ──────── V_BCKP of the module (if present): keeps ephemerides and clock,
                       fix in 1-2 seconds at wake-up instead of 30 or more
```

- Recommended module: **u-blox M10** (MAX-M10S or similar), with GPS, Galileo, GLONASS and
  BeiDou at the same time and about 25 mW. Active antenna facing the sky (under the dashboard,
  not under a metallized athermal windscreen).
- Alternatively the Quectel L76K, used by LilyGO in the "with GPS" versions.

## Connections to the T-Call V1.0 header

Always check the names printed on the board. Don't use GPIO 4, 12, 13, 14, 25, 26 and 27
(modem and LED) nor 16/17 (PSRAM).

| Carrier | T-Call | Notes |
| :--- | :--- | :--- |
| `OUT` of the bq24074 (via C5) | `VBUS` | Short wire, at least 0.5 mm² |
| GND | `GND` | Two wires, near VBUS |
| 3V3 (sensors, PC817 collector, R5, R6) | `3V3` | Small loads only (< 100 mA) |
| Ignition | GPIO 32 | `PIN_IGNITION_SENSE` |
| LIS3DH INT1 | GPIO 33 | `PIN_ACCEL_INT` |
| PGOOD | GPIO 34 | `PIN_POWER_GOOD` |
| Voltage divider | GPIO 35 | `PIN_VEHICLE_VOLTAGE` |
| I2C | GPIO 21 (SDA), 22 (SCL) | LIS3DH and BMP390 |
| GNSS (opt.) | GPIO 18, 19, 23 | `GNSS_RX_PIN`, `GNSS_TX_PIN`, `GNSS_POWER_PIN` |

**T-Call V1.1**: uses different pins and GPIO 32/33 are taken by the modem. The firmware fails
to compile when the configuration isn't compatible.

## Wiring in the car

| Wire | Where | Section |
| :--- | :--- | :--- |
| Permanent +30 | *Add-a-fuse* on an always-on fuse (e.g. interior lights), F1 2A | 0.75 mm² |
| Ignition +15 | *Add-a-fuse* on a fuse powered only with the ignition on (e.g. radio), F2 1A | 0.5 mm² |
| Ground | Body bolt, with a ring terminal | 0.75 mm² |

- Screw terminal block or plug-in connector (e.g. Molex Micro-Fit) with cable retention, so the
  board can be removed.
- ABS enclosure, fixed in a hidden place away from heat. LTE antenna away from metal surfaces,
  GNSS antenna facing the sky.

## Assembly and testing

Assembly on 2.54 mm perfboard, about 7 × 9 cm:

1. Input block (F1 excluded), TVS, D1 and C1/C2. With the bench supply at 12V, 0.5A: check the
   polarity on VIN_BUCK and that, swapping the wires, the current goes into limiting (the TVS
   conducts).
2. Regulator U1: 5.0V out, no load.
3. Charger U2 without battery: settings, then 4.4V on `OUT`. Connect the battery: the CHG LED
   lights up. Removing the 12V, `OUT` must follow the battery without interruption and `PGOOD`
   go from 0V to 3.3V (with the T-Call connected).
4. Divider: 12.0V in → about 2.1V on GPIO 35.
5. Optocoupler: 12V on the +15 → about 3.1V on GPIO 32, 0V without.
6. T-Call connected, firmware with the options enabled: check voltage, events and wake-ups on
   the serial port. Measure the deep sleep draw on the +30.

## Enabling in the firmware

In `firmware/configurations.h`:

```c
#define VEHICLE_VOLTAGE_SENSE 1     // divider on GPIO 35
#define VEHICLE_VOLTAGE_CALIBRATION 1.0f  // after calibrating with the multimeter
#define POWER_GOOD_SENSE 1          // PGOOD of the bq24074 on GPIO 34

// Only with the external GNSS module
#define GNSS_SOURCE GNSS_SOURCE_EXTERNAL
#define GNSS_POWER_PIN BOARD_GNSS_POWER_PIN  // 23
```

The default pins of this design are in the board file,
`firmware/boards/lilygo_t_call_a7670_v1_0.h` (`BOARD_PIN_*`). To move one, define the matching
`PIN_*` in `configurations.h` (e.g. `PIN_VEHICLE_VOLTAGE`). `IGNITION_ACTIVE_LEVEL` stays
`HIGH` with the optocoupler of this design.

## Bill of materials

The `hardware/bom.csv` file of the repository holds the full list. Indicative cost of the
carrier, excluding T-Call, sensors and the optional GNSS: **€ 40-50**, of which about € 20 for
regulator and charger and € 10 for the battery.
