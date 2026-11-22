#ifndef POWER_H
#define POWER_H

// Vehicle battery voltage (VEHICLE_VOLTAGE_SENSE) and external power detection of the
// backup battery charger (POWER_GOOD_SENSE). Both disabled by default: they need the
// hardware described in hardware/README.md.

#include <Arduino.h>

void powerInit();

// Vehicle battery in millivolts, 0 when the measure is disabled
uint32_t vehicleMillivolts();

// True while the tracker is supplied by the car (always true without POWER_GOOD_SENSE)
bool externalPowerPresent();

#endif
