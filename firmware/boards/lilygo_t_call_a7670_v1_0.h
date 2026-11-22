#ifndef BOARD_LILYGO_T_CALL_A7670_V1_0_H
#define BOARD_LILYGO_T_CALL_A7670_V1_0_H

// LilyGO T-Call A7670 V1.0 (ESP32-WROVER-E, SIMCom A7670). The version is printed on the
// front of the board: the V1.1 has a different pin map and needs its own file.
// Schematic: github.com/Xinyuan-LilyGO/LilyGO-T-A76XX, schematic/esp32/T-Call-A7670-V1.0.pdf

#define BOARD_NAME "LilyGO T-Call A7670 V1.0"

// --- Modem ---
#define BOARD_MODEM_FAMILY MODEM_FAMILY_SIMCOM_A76XX
#define BOARD_MODEM_UART 1
#define BOARD_MODEM_BAUD 115200
#define BOARD_MODEM_TX_PIN 26
#define BOARD_MODEM_RX_PIN 25
#define BOARD_MODEM_PWRKEY_PIN 4
#define BOARD_MODEM_RESET_PIN 27
#define BOARD_MODEM_RESET_LEVEL LOW
#define BOARD_MODEM_DTR_PIN 14
#define BOARD_MODEM_RING_PIN 13
// No modem power switch on this board: the LED is only a power indicator
#define BOARD_LED_PIN 12
// GNSS integrated only in the A7670E-FASE / A7670SA-FASE (AT+SIMCOMATI shows the model):
// set it to 0 for the LASE and the A7670G, and use an external module
#define BOARD_MODEM_HAS_GNSS 1
#define BOARD_MODEM_GNSS_ENABLE_PIN -1
#define BOARD_MODEM_GNSS_ENABLE_LEVEL -1

// --- Buses ---
#define BOARD_I2C_SDA 21
#define BOARD_I2C_SCL 22

// --- Default pins of the application, configurations.h can override them ---
// Free on this board: 0, 2, 5, 15, 18, 19, 23 (in/out), 34, 35, 36, 39 (input only).
// Never use 4, 12, 13, 14, 25, 26, 27 (modem, LED) and 16, 17 (PSRAM).
#define BOARD_PIN_IGNITION 32
#define BOARD_PIN_ACCEL_INT 33
#define BOARD_PIN_POWER_GOOD 34
#define BOARD_PIN_VEHICLE_VOLTAGE 35
#define BOARD_GNSS_RX_PIN 18
#define BOARD_GNSS_TX_PIN 19
#define BOARD_GNSS_POWER_PIN 23

#endif
