#ifndef CONFIG_DEFAULTS_H
#define CONFIG_DEFAULTS_H

// Validation and default values of configurations.h / secrets.h

#define GNSS_SOURCE_MODEM 1
#define GNSS_SOURCE_EXTERNAL 2

#if CONNECTION_MODE != 1 && CONNECTION_MODE != 2 && CONNECTION_MODE != 3
  #error "Invalid CONNECTION_MODE: 1. WiFi, 2. Sim module, 3. WiFi with Sim fallback"
#endif

#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  #ifndef WIFI_SSID
    #error "Missing WIFI_SSID in secrets.h"
  #endif
  #ifndef WIFI_PASSWORD
    #error "Missing WIFI_PASSWORD in secrets.h"
  #endif
  #ifndef WIFI_CONNECTION_RETRY
    #define WIFI_CONNECTION_RETRY 30
  #endif
  #ifndef WIFI_CONNECTION_DELAY
    #define WIFI_CONNECTION_DELAY 1000
  #endif
#endif

#if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  #ifndef SIM_APN
    #error "Missing SIM_APN in secrets.h"
  #endif
  #ifndef SIM_USER
    #define SIM_USER ""
  #endif
  #ifndef SIM_PASSWORD
    #define SIM_PASSWORD ""
  #endif
  #ifndef SIM_PIN
    #define SIM_PIN ""
  #endif
#endif

#ifndef MODEM_LTE_ONLY
  #define MODEM_LTE_ONLY 1
#endif

#if defined(MQTT_BROKER) && !defined(SERVER_HOST)
  #error "MQTT_BROKER is now SERVER_HOST (and MQTT_TLS / MQTT_PORT / MQTT_KEEP_ALIVE_SEC: SERVER_TLS / SERVER_PORT / KEEP_ALIVE_SEC)"
#endif
#ifndef SERVER_HOST
  #error "SERVER_HOST not defined"
#endif
#ifndef SERVER_TLS
  #define SERVER_TLS 1
#endif
#ifndef SERVER_TLS_VERIFY
  #define SERVER_TLS_VERIFY 1
#endif
#ifndef SERVER_PORT
  #if SERVER_TLS
    #define SERVER_PORT 443
  #else
    #define SERVER_PORT 80
  #endif
#endif
// The HELLO authenticated with DEVICE_KEY is the only credential (MQTT_USERNAME and
// MQTT_PASSWORD of the old firmware are ignored)
#ifndef DEVICE_KEY
  #error "Missing DEVICE_KEY in secrets.h, generate it with: npm run provision <IMEI> (server folder)"
#endif
// Images for the updates over the air: DEVICE_KEY of zeros, the tracker keeps its own key
#ifndef FIRMWARE_VARIANT
  #define FIRMWARE_VARIANT "default"
#endif
// Automatic updates: once a day the tracker asks the server for a newer image of its
// variant (the owner can still turn them off in the app). 0 for customized builds: they
// would be replaced by the official images of the same variant.
#ifndef AUTO_UPDATE
  #define AUTO_UPDATE 0
#endif
// Longest download of a firmware update, before the deep sleep (about 1.2 MB)
#ifndef OTA_MAX_SEC
  #define OTA_MAX_SEC 900
#endif
#ifndef KEEP_ALIVE_SEC
  #define KEEP_ALIVE_SEC 60
#endif
#if KEEP_ALIVE_SEC < 10 || KEEP_ALIVE_SEC > 90
  #error "KEEP_ALIVE_SEC must be 10-90: the server closes the connections silent for 3 minutes, Cloudflare after 100 seconds"
#endif
#ifndef RECONNECT_MIN_DELAY_MS
  #define RECONNECT_MIN_DELAY_MS 5000
#endif
#ifndef RECONNECT_MAX_DELAY_MS
  #define RECONNECT_MAX_DELAY_MS 120000
#endif

#ifndef SAMPLE_INTERVAL_MS
  #define SAMPLE_INTERVAL_MS 5000
#endif
#ifndef BATCH_SIZE
  #define BATCH_SIZE 3
#endif
#if BATCH_SIZE < 1 || BATCH_SIZE > 20
  #error "BATCH_SIZE must be between 1 and 20"
#endif
#ifndef BATCH_MAX_DELAY_SEC
  #define BATCH_MAX_DELAY_SEC 30
#endif
#ifndef ADAPTIVE_SAMPLING
  #define ADAPTIVE_SAMPLING 1
#endif
#ifndef ADAPTIVE_TOLERANCE_METERS
  #define ADAPTIVE_TOLERANCE_METERS 10
#endif
#ifndef ADAPTIVE_MAX_INTERVAL_SEC
  #define ADAPTIVE_MAX_INTERVAL_SEC 30
#endif
#ifndef ENVIRONMENT_INTERVAL_SEC
  #define ENVIRONMENT_INTERVAL_SEC 60
#endif

#ifndef GNSS_SOURCE
  #define GNSS_SOURCE GNSS_SOURCE_MODEM
#endif
#if GNSS_SOURCE != GNSS_SOURCE_MODEM && GNSS_SOURCE != GNSS_SOURCE_EXTERNAL
  #error "Invalid GNSS_SOURCE: GNSS_SOURCE_MODEM or GNSS_SOURCE_EXTERNAL"
#endif
#if GNSS_SOURCE == GNSS_SOURCE_MODEM && !BOARD_MODEM_HAS_GNSS
  #error "The modem of this board has no GNSS: use GNSS_SOURCE_EXTERNAL"
#endif
#ifndef GNSS_RX_PIN
  #define GNSS_RX_PIN BOARD_GNSS_RX_PIN
#endif
#ifndef GNSS_TX_PIN
  #define GNSS_TX_PIN BOARD_GNSS_TX_PIN
#endif
#ifndef GNSS_BAUD
  #define GNSS_BAUD 9600
#endif
#ifndef GNSS_POWER_PIN
  #define GNSS_POWER_PIN -1
#endif
#ifndef GNSS_POWER_ACTIVE_LEVEL
  #define GNSS_POWER_ACTIVE_LEVEL HIGH
#endif

#ifndef THRESHOLD_DISTANCE
  #define THRESHOLD_DISTANCE 15
#endif
#ifndef STATIONARY_INTERVAL_SEC
  #define STATIONARY_INTERVAL_SEC 300
#endif

#ifndef CELL_LOCATION
  #define CELL_LOCATION 1
#endif
#ifndef CELL_FALLBACK_INTERVAL_SEC
  #define CELL_FALLBACK_INTERVAL_SEC 60
#endif

#ifndef PIN_IGNITION_SENSE
  #define PIN_IGNITION_SENSE BOARD_PIN_IGNITION
#endif
#ifndef IGNITION_ACTIVE_LEVEL
  #define IGNITION_ACTIVE_LEVEL HIGH
#endif
#ifndef IGNITION_DEBOUNCE_MS
  #define IGNITION_DEBOUNCE_MS 5000
#endif
#ifndef HEARTBEAT_PERIOD_SEC
  #define HEARTBEAT_PERIOD_SEC 14400
#endif
#ifndef GPS_FIX_TIMEOUT_SEC
  #define GPS_FIX_TIMEOUT_SEC 90
#endif

#ifndef PIN_ACCEL_INT
  #define PIN_ACCEL_INT BOARD_PIN_ACCEL_INT
#endif
#ifndef ALARM_ARM_DELAY_SEC
  #define ALARM_ARM_DELAY_SEC 180
#endif
#ifndef ALARM_TRACK_SEC
  #define ALARM_TRACK_SEC 60
#endif
#ifndef ALARM_MAX_TRACK_SEC
  #define ALARM_MAX_TRACK_SEC 900
#endif
#ifndef ALARM_MOVE_METERS
  #define ALARM_MOVE_METERS 50
#endif
#ifndef ALARM_SAMPLE_INTERVAL_MS
  #define ALARM_SAMPLE_INTERVAL_MS 10000
#endif
#ifndef ALARM_COOLDOWN_SEC
  #define ALARM_COOLDOWN_SEC 600
#endif
#ifndef TILT_THRESHOLD_DEG
  #define TILT_THRESHOLD_DEG 4
#endif
#ifndef TILT_CHECK_INTERVAL_SEC
  #define TILT_CHECK_INTERVAL_SEC 900
#endif

#ifndef OWNER_TAG
  #define OWNER_TAG 0
#endif
#if OWNER_TAG != 0 && OWNER_TAG != 1 && OWNER_TAG != 2
  #error "Invalid OWNER_TAG: 0 off, 1 fixed address, 2 rolling code beacon"
#endif
#ifndef OWNER_TAG_SCAN_MS
  #define OWNER_TAG_SCAN_MS 4000
#endif
#if OWNER_TAG == 1 && !defined(OWNER_TAG_ADDRESS)
  #error "Missing OWNER_TAG_ADDRESS in secrets.h, e.g. \"c3:12:ab:45:67:89\""
#endif
#if OWNER_TAG == 2 && !defined(OWNER_TAG_KEY)
  #error "Missing OWNER_TAG_KEY in secrets.h: 64 hex characters, the same of the beacon"
#endif

#ifndef VEHICLE_VOLTAGE_SENSE
  #define VEHICLE_VOLTAGE_SENSE 0
#endif
#if VEHICLE_VOLTAGE_SENSE
  #ifndef PIN_VEHICLE_VOLTAGE
    #define PIN_VEHICLE_VOLTAGE BOARD_PIN_VEHICLE_VOLTAGE
  #endif
  #if PIN_VEHICLE_VOLTAGE < 32 || PIN_VEHICLE_VOLTAGE > 39
    #error "PIN_VEHICLE_VOLTAGE must be an ADC1 pin (32-39): ADC2 doesn't work with the WiFi"
  #endif
  #ifndef VEHICLE_VOLTAGE_DIVIDER
    #define VEHICLE_VOLTAGE_DIVIDER 5.7f
  #endif
  #ifndef VEHICLE_VOLTAGE_CALIBRATION
    #define VEHICLE_VOLTAGE_CALIBRATION 1.0f
  #endif
  #ifndef LOW_BATTERY_MV
    #define LOW_BATTERY_MV 11900
  #endif
  #ifndef CRITICAL_BATTERY_MV
    #define CRITICAL_BATTERY_MV 11500
  #endif
#endif

#ifndef POWER_GOOD_SENSE
  #define POWER_GOOD_SENSE 0
#endif
#if POWER_GOOD_SENSE
  #ifndef PIN_POWER_GOOD
    #define PIN_POWER_GOOD BOARD_PIN_POWER_GOOD
  #endif
  #ifndef POWER_GOOD_ACTIVE_LEVEL
    #define POWER_GOOD_ACTIVE_LEVEL LOW
  #endif
  // The deep sleep wakes up on ANY_HIGH (ext1, shared with the accelerometer)
  #if POWER_GOOD_ACTIVE_LEVEL != LOW
    #error "POWER_GOOD_SENSE needs an active low PGOOD: the power loss must be a high level"
  #endif
#endif

#endif
