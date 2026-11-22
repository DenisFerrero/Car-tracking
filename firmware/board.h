#ifndef BOARD_H
#define BOARD_H

// Board registry. The common code uses only the BOARD_* macros of the selected board
// (configurations.h: BOARD) and the modem driver of its family (modem.h).
//
// Adding a board:
//  1. write boards/<board>.h with every macro listed in boards/lilygo_t_call_a7670_v1_0.h
//  2. register it below
//  3. if its modem belongs to a new family, add a modem_<family>.cpp implementing modem.h

#define BOARD_LILYGO_T_CALL_A7670_V1_0 1

// Modem families, each one implemented by a modem_<family>.cpp
#define MODEM_FAMILY_SIMCOM_A76XX 1

#if BOARD == BOARD_LILYGO_T_CALL_A7670_V1_0
  #include "boards/lilygo_t_call_a7670_v1_0.h"
#else
  #error "Unknown BOARD, see board.h"
#endif

#if !defined(BOARD_NAME) || !defined(BOARD_MODEM_FAMILY) || !defined(BOARD_MODEM_HAS_GNSS) || \
    !defined(BOARD_I2C_SDA) || !defined(BOARD_I2C_SCL) || !defined(BOARD_PIN_IGNITION) || \
    !defined(BOARD_PIN_ACCEL_INT) || !defined(BOARD_PIN_POWER_GOOD) || !defined(BOARD_PIN_VEHICLE_VOLTAGE) || \
    !defined(BOARD_GNSS_RX_PIN) || !defined(BOARD_GNSS_TX_PIN) || !defined(BOARD_GNSS_POWER_PIN)
  #error "Incomplete board definition, see boards/lilygo_t_call_a7670_v1_0.h"
#endif

#endif
