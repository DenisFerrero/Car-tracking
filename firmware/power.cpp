#include "power.h"
#include "configurations.h"

void powerInit() {
#if VEHICLE_VOLTAGE_SENSE
  // 11 dB attenuation: about 0.15-3.1 V on the pin, calibrated by analogReadMilliVolts
  analogSetPinAttenuation(PIN_VEHICLE_VOLTAGE, ADC_11db);
#endif
#if POWER_GOOD_SENSE
  // Open drain output of the charger, external pull-up (GPIO 34-39 have no pull-ups)
  pinMode(PIN_POWER_GOOD, INPUT);
#endif
}

uint32_t vehicleMillivolts() {
#if VEHICLE_VOLTAGE_SENSE
  // Average of several readings, the ESP32 ADC is noisy
  uint32_t total = 0;
  for (int i = 0; i < 16; i++) total += analogReadMilliVolts(PIN_VEHICLE_VOLTAGE);
  return (uint32_t)((total / 16.0f) * VEHICLE_VOLTAGE_DIVIDER * VEHICLE_VOLTAGE_CALIBRATION);
#else
  return 0;
#endif
}

bool externalPowerPresent() {
#if POWER_GOOD_SENSE
  return digitalRead(PIN_POWER_GOOD) == POWER_GOOD_ACTIVE_LEVEL;
#else
  return true;
#endif
}
