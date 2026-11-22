#ifndef MODEM_H
#define MODEM_H

// Modem interface used by the common code. Every modem family of board.h implements it
// in its own modem_<family>.cpp, the only place that knows the AT commands and TinyGSM.

#include <Arduino.h>
#include <Client.h>
#include "cell.h"
#include "gnss.h"

struct ModemInfo {
  String imei;
  String manufacturer;
  String model;
  String revision;
};

// Powers the modem and configures it (network mode, TLS certificates). Required in every
// connection mode: the modem hosts the GNSS and gives the IMEI.
bool modemPowerOn();
void modemPowerOff();
ModemInfo modemReadInfo();

// Cellular data connection
bool modemAttach();
bool modemAttached();
void modemDetach();

// TCP client of the cellular connection, with TLS when SERVER_TLS is enabled
Client &modemClient();

// Signal strength in dBm, 0 when unknown
int modemSignalDbm();
// Serving cell, false without service
bool modemCellInfo(CellInfo &cell);

// Integrated GNSS (BOARD_MODEM_HAS_GNSS)
bool modemGnssEnable();
bool modemGnssRead(GnssReading &reading);

#endif
