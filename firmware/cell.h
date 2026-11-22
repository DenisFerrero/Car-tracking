#ifndef CELL_H
#define CELL_H

// Serving cell of the modem, the server turns it into an approximate position when the
// GNSS has no fix (garage, container). Plain C++, tested on the PC (firmware/test).

#include <stdint.h>

struct CellInfo {
  uint16_t mcc;     // mobile country code, e.g. 222 Italy
  uint16_t mnc;     // mobile network code
  uint32_t area;    // TAC (LTE) or LAC (GSM)
  uint32_t id;      // cell id (LTE: 28 bits)
};

// Parses the answer of AT+CPSI? (SIMCom), e.g.
//   +CPSI: LTE,Online,222-01,0x5A1B,26834437,123,EUTRAN-BAND3,1300,5,5,-94,-1105,-750,13
// False when the modem has no service.
bool parseCpsi(const char *response, CellInfo &cell);

#endif
