#ifndef GNSS_H
#define GNSS_H

// Position source, chosen with GNSS_SOURCE in configurations.h:
//  - GNSS_SOURCE_MODEM: GNSS integrated in the modem (BOARD_MODEM_HAS_GNSS), modem.h
//  - GNSS_SOURCE_EXTERNAL: NMEA module on a UART (u-blox, Quectel...), required by the
//    modems without GNSS like the global A7670G

#include <Arduino.h>

struct GnssReading {
  uint32_t timestamp;   // unix seconds, UTC
  int32_t lat;          // 1e-5 degrees
  int32_t lon;          // 1e-5 degrees
  float speedKmh;
  int16_t altitude;     // meters, valid with hasAltitude
  bool hasAltitude;
  uint8_t satellites;   // used in the fix, 0 when unknown
};

// Powers and configures the receiver, the modem must be on for GNSS_SOURCE_MODEM
bool gnssBegin();

// Reads the bytes received by the external module: call it often (UART buffer)
void gnssPoll();

// The current fix, false without a valid fix
bool gnssRead(GnssReading &reading);

// Powers down the external module before the deep sleep (the modem GNSS goes down with it)
void gnssSleep();

#endif
