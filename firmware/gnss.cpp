#include "gnss.h"
#include "configurations.h"

#if GNSS_SOURCE == GNSS_SOURCE_MODEM

#include "modem.h"

bool gnssBegin() {
  return modemGnssEnable();
}

void gnssPoll() {}

bool gnssRead(GnssReading &reading) {
  return modemGnssRead(reading);
}

void gnssSleep() {}

#elif GNSS_SOURCE == GNSS_SOURCE_EXTERNAL

#include <driver/gpio.h>
#include "nmea.h"

// A fix older than this is stale: the module lost the satellites or stopped talking
#define GNSS_FIX_MAX_AGE_MS 3000

static HardwareSerial gnssSerial(2);
static NmeaParser parser;
static unsigned long lastFixAt = 0;
static bool started = false;

static void setPower(bool on) {
#if GNSS_POWER_PIN >= 0
  gpio_hold_dis((gpio_num_t)GNSS_POWER_PIN);
  pinMode(GNSS_POWER_PIN, OUTPUT);
  digitalWrite(GNSS_POWER_PIN, on ? GNSS_POWER_ACTIVE_LEVEL : !GNSS_POWER_ACTIVE_LEVEL);
#else
  (void)on;
#endif
}

bool gnssBegin() {
  if (started) return true;
  started = true;

  setPower(true);
  // At 9600 baud a second of NMEA output is about 500 bytes
  gnssSerial.setRxBufferSize(2048);
  gnssSerial.begin(GNSS_BAUD, SERIAL_8N1, GNSS_RX_PIN, GNSS_TX_PIN);
  Serial.printf("External GNSS on RX %d / TX %d at %d baud\n", GNSS_RX_PIN, GNSS_TX_PIN, GNSS_BAUD);
  return true;
}

void gnssPoll() {
  if (!started) return;
  while (gnssSerial.available()) {
    if (parser.feed((char)gnssSerial.read())) lastFixAt = millis();
  }
}

bool gnssRead(GnssReading &reading) {
  gnssPoll();
  if (parser.fixes() == 0 || millis() - lastFixAt > GNSS_FIX_MAX_AGE_MS) return false;

  const NmeaFix &fix = parser.fix();
  reading.timestamp = fix.timestamp;
  reading.lat = fix.lat;
  reading.lon = fix.lon;
  reading.speedKmh = fix.speedKmh;
  reading.altitude = fix.altitude;
  reading.hasAltitude = fix.hasAltitude;
  reading.satellites = fix.satellites;
  return reading.timestamp > 1704067200UL;  // 2024-01-01, sanity check of the module clock
}

void gnssSleep() {
  if (started) gnssSerial.end();
  started = false;
#if GNSS_POWER_PIN >= 0
  setPower(false);
  // Keeps the module off during the deep sleep
  gpio_hold_en((gpio_num_t)GNSS_POWER_PIN);
  gpio_deep_sleep_hold_en();
#endif
}

#endif
