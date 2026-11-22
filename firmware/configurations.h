#ifndef CONFIGURATIONS_H
#define CONFIGURATIONS_H

// Credentials and device key, not versioned: copy secrets.example.h to secrets.h
#include "secrets.h"

// Print the configuration at startup (secrets excluded)
#define START_UP_PRINT_ENV 1

// Firmware version, sent to the server at every connection as <version>+<variant>.
// The variant tells which images of the updates over the air fit this build (board,
// connection mode): one name for every tracker built with the same configuration.
// Release builds (.github/workflows/release.yml) set both from the tag and the variant.
#ifndef FIRMWARE_VERSION
  #define FIRMWARE_VERSION "2.3.0"
#endif
#ifndef FIRMWARE_VARIANT
  #define FIRMWARE_VARIANT "default"
#endif
// Automatic updates from the official releases: keep 0 on a customized firmware, an
// update would replace it with the official image of the same variant
#define AUTO_UPDATE 0

// --- Board ---
// Pins, modem and GNSS of the board come from boards/<board>.h: changing board means
// changing this line (board.h lists the supported ones and how to add a new one)
#define BOARD BOARD_LILYGO_T_CALL_A7670_V1_0

// Bridge for compiling with the standard TinyGSM library (CLI tests): comment it out
// when compiling for the physical board with the LilyGO TinyGSM library
#define COMPILING_WITH_STANDARD_TINYGSM

// 4G only (LTE Cat-1): the 2G networks are being switched off. 0 = automatic (LTE/GSM).
#define MODEM_LTE_ONLY 1

// 1. WiFi / 2. Sim module / 3. WiFi priority, fallback to Sim module
#define CONNECTION_MODE 1
// WiFi connection attempts, and delay between them in milliseconds
#define WIFI_CONNECTION_RETRY 30
#define WIFI_CONNECTION_DELAY 1000

// Server (backend), reached with a WebSocket on the /tracker path
#define SERVER_HOST "car-tracking.local"
// TLS (wss): about 2 MB a month more (handshake ~5 KB per connection, ~29 B per frame).
// The certificate is verified with the root CAs of certificates.h (npm run ca-bundle):
// with the self-signed certificate of the debug stack set SERVER_TLS_VERIFY 0.
// Without TLS: SERVER_TLS 0 and SERVER_PORT 80.
#define SERVER_TLS 1
#define SERVER_TLS_VERIFY 1
#define SERVER_PORT 443
// Keep alive below 100s: Cloudflare closes the idle WebSockets after 100 seconds
#define KEEP_ALIVE_SEC 60
// Reconnection back-off, every attempt costs about 1 KB on the SIM
#define RECONNECT_MIN_DELAY_MS 5000
#define RECONNECT_MAX_DELAY_MS 120000

// --- Data usage ---
// GPS sampling interval while driving, in milliseconds
#define SAMPLE_INTERVAL_MS 5000
// Points sent in a single frame: the overhead of a frame (WebSocket + TLS + TCP/IP) is
// about 90 bytes, a point about 10 bytes
#define BATCH_SIZE 3
// A batch not full yet is sent anyway after this time (seconds), keeps the position fresh
// on the straight roads where the adaptive sampling records few points
#define BATCH_MAX_DELAY_SEC 30
// Below this distance (meters) from the last recorded point the car is standing still ...
#define THRESHOLD_DISTANCE 15
// ... and a point is recorded only every X seconds, e.g. at a traffic light or in a jam
#define STATIONARY_INTERVAL_SEC 300

// Adaptive sampling: 1 records only the samples where the route bends (straight roads
// cost a point every ADAPTIVE_MAX_INTERVAL_SEC), 0 records every sample
#define ADAPTIVE_SAMPLING 1
// Max distance (meters) between the real route and the one drawn with the recorded points
#define ADAPTIVE_TOLERANCE_METERS 10
#define ADAPTIVE_MAX_INTERVAL_SEC 30

// Pressure, temperature and vehicle voltage change slowly: sent at most every X seconds
#define ENVIRONMENT_INTERVAL_SEC 60

// --- Position source ---
// GNSS_SOURCE_MODEM: GNSS of the modem (BOARD_MODEM_HAS_GNSS: A7670E-FASE / A7670SA-FASE)
// GNSS_SOURCE_EXTERNAL: NMEA module on a UART, for the modems without GNSS (A7670G)
#define GNSS_SOURCE GNSS_SOURCE_MODEM
// External module only: baud rate, optional power switch (-1 = always powered; with the
// P-MOSFET of hardware/README.md: BOARD_GNSS_POWER_PIN, active LOW). The UART pins come
// from the board (BOARD_GNSS_RX_PIN / BOARD_GNSS_TX_PIN), GNSS_RX_PIN / GNSS_TX_PIN
// override them.
#define GNSS_BAUD 9600
#define GNSS_POWER_PIN -1
#define GNSS_POWER_ACTIVE_LEVEL LOW

// Serving cell in the points without a fix (garage, tunnel): the server estimates the
// position from it. While driving a point every CELL_FALLBACK_INTERVAL_SEC without fix.
#define CELL_LOCATION 1
#define CELL_FALLBACK_INTERVAL_SEC 60

// --- Power management ---
// Ignition sense (+12V under key, through an optocoupler or a voltage divider), pin
// BOARD_PIN_IGNITION, PIN_IGNITION_SENSE overrides it
// HIGH with the voltage divider, LOW with the optocoupler (internal pull-up enabled)
#define IGNITION_ACTIVE_LEVEL HIGH
// Ignition must stay off for this time before going to sleep (milliseconds)
#define IGNITION_DEBOUNCE_MS 5000
// Position sent while parked, every X seconds (4 hours)
#define HEARTBEAT_PERIOD_SEC 14400
// Max time waiting for a GPS fix after waking up (seconds)
#define GPS_FIX_TIMEOUT_SEC 90

// --- Anti-theft (LIS3DH accelerometer, INT1 on BOARD_PIN_ACCEL_INT / PIN_ACCEL_INT) ---
// Motion detection is armed only after this delay from the engine off (door slams, seats)
#define ALARM_ARM_DELAY_SEC 180
// Tracking time after a motion alarm, and its extension while the car keeps moving
#define ALARM_TRACK_SEC 60
#define ALARM_MAX_TRACK_SEC 900
#define ALARM_MOVE_METERS 50
#define ALARM_SAMPLE_INTERVAL_MS 10000
// After an alarm session the motion detection is paused, limits the data in windy places
#define ALARM_COOLDOWN_SEC 600
// Tilt detection (car lifted by a tow truck or a jack): angle in degrees from the position
// at the arming, checked at every motion wake up and every TILT_CHECK_INTERVAL_SEC
// (a wake up of about 0.5 seconds without the modem). 0 disables it.
#define TILT_THRESHOLD_DEG 4
#define TILT_CHECK_INTERVAL_SEC 900

// Owner keychain, a BLE scan at the motion alarm (tilt and power loss always alarm):
// 0 off, 1 any BLE tag with a fixed address (OWNER_TAG_ADDRESS in secrets.h, clonable),
// 2 beacon with rolling code of hardware/owner-beacon (OWNER_TAG_KEY in secrets.h).
// Samsung SmartTag / AirTag rotate address and identifiers: not usable.
// The BLE stack takes ~740 KB of flash: select the partition scheme "Minimal SPIFFS
// (1.9MB APP with OTA/190KB SPIFFS)" (arduino-cli: --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs)
#define OWNER_TAG 0
#define OWNER_TAG_SCAN_MS 4000

// --- Optional hardware, see hardware/README.md (disabled: 0) ---
// Vehicle battery voltage through a divider on an ADC1 pin (GPIO 32-39),
// BOARD_PIN_VEHICLE_VOLTAGE or PIN_VEHICLE_VOLTAGE
#define VEHICLE_VOLTAGE_SENSE 0
// (R1 + R2) / R2 of the divider: 470k / 100k
#define VEHICLE_VOLTAGE_DIVIDER 5.7f
// Correction measured with a multimeter: real voltage / reported voltage
#define VEHICLE_VOLTAGE_CALIBRATION 1.0f
// Below LOW the points carry the low battery event, below CRITICAL the tracker reduces
// the heartbeats to one a day to preserve the battery for the engine start
#define LOW_BATTERY_MV 11900
#define CRITICAL_BATTERY_MV 11500

// Backup battery: PGOOD output of the charger, active when the car supplies the tracker.
// The tracker wakes up and raises an alarm when the power is cut.
// Pin BOARD_PIN_POWER_GOOD or PIN_POWER_GOOD
#define POWER_GOOD_SENSE 0
#define POWER_GOOD_ACTIVE_LEVEL LOW

// Test builds (firmware/test/config_*.h) override the settings above without editing
// this file: arduino-cli compile --build-property "compiler.cpp.extra_flags=-DCT_CONFIG_OVERRIDE=..."
#ifdef CT_CONFIG_OVERRIDE
  #include CT_CONFIG_OVERRIDE
#endif

#include "board.h"
#include "config_defaults.h"

#endif
