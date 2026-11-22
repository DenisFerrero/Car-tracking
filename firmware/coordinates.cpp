#include "coordinates.h"
#include "configurations.h"
#include "clock.h"
#include "connections.h"
#include "gnss.h"
#include "power.h"
#include <math.h>
#include <string.h>
#include <Wire.h>
#include <Adafruit_BMP3XX.h>
#include <Adafruit_LIS3DH.h>

using namespace proto;

static Adafruit_BMP3XX bmp;
static Adafruit_LIS3DH lis = Adafruit_LIS3DH();
static uint8_t lisAddress = 0x18;
static bool bmpReady = false;
static bool lisReady = false;

// Earth radius in meters to calculate the distance between two points
#define EARTH_RADIUS 6371000.0

static void writeRegisterI2C(uint8_t address, uint8_t reg, uint8_t value) {
  Wire.beginTransmission(address);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

static uint8_t readRegisterI2C(uint8_t address, uint8_t reg) {
  Wire.beginTransmission(address);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(address, (uint8_t)1);
  return Wire.available() ? Wire.read() : 0;
}

bool initSensors() {
  Wire.begin(BOARD_I2C_SDA, BOARD_I2C_SCL);

  bmpReady = bmp.begin_I2C();
  if (bmpReady) {
    bmp.setTemperatureOversampling(BMP3_OVERSAMPLING_8X);
    bmp.setPressureOversampling(BMP3_OVERSAMPLING_4X);
    bmp.setIIRFilterCoeff(BMP3_IIR_FILTER_COEFF_3);
    bmp.setOutputDataRate(BMP3_ODR_50_HZ);
    Serial.println("BMP390 initialized");
  } else {
    Serial.println("BMP390 not found, check wiring!");
  }

  // Try both typical I2C addresses for LIS3DH (0x18 and 0x19)
  if (lis.begin(0x18)) {
    lisAddress = 0x18;
    lisReady = true;
  } else if (lis.begin(0x19)) {
    lisAddress = 0x19;
    lisReady = true;
  }

  if (lisReady) {
    // Wake-on-motion on INT1, direct register writes (not exposed by the Adafruit library)
    writeRegisterI2C(lisAddress, 0x20, 0x57);  // CTRL_REG1: 100Hz ODR, X/Y/Z enabled
    // High-pass filter only on INT1: the output registers keep the gravity for the tilt
    writeRegisterI2C(lisAddress, 0x21, 0x01);  // CTRL_REG2: High-pass filter enabled for INT1
    writeRegisterI2C(lisAddress, 0x22, 0x40);  // CTRL_REG3: Route IA1 (Interrupt Activity 1) to INT1
    writeRegisterI2C(lisAddress, 0x23, 0x00);  // CTRL_REG4: 2g full scale
    writeRegisterI2C(lisAddress, 0x24, 0x08);  // CTRL_REG5: Latch interrupt on INT1 pin
    writeRegisterI2C(lisAddress, 0x32, 0x10);  // INT1_THS: Movement threshold (~250mg)
    writeRegisterI2C(lisAddress, 0x33, 0x00);  // INT1_DURATION: Trigger immediately
    writeRegisterI2C(lisAddress, 0x30, 0x2A);  // INT1_CFG: Enable X-High, Y-High, Z-High interrupts
    Serial.println("LIS3DH initialized for wake-on-motion");
  } else {
    Serial.println("LIS3DH not found, check wiring!");
  }

  return bmpReady && lisReady;
}

void clearAccelInterrupt() {
  // Reading INT1_SRC (0x31) clears the latch
  if (lisReady) readRegisterI2C(lisAddress, 0x31);
}

bool samplePoint(Point &point, Status status) {
  GnssReading fix;
  if (!gnssRead(fix)) return false;

  utcFromGnss(fix.timestamp);

  memset(&point, 0, sizeof(point));
  point.timestamp = fix.timestamp;
  point.lat = fix.lat;
  point.lon = fix.lon;
  point.flags = status & FLAG_STATUS_MASK;

  float kmh = fix.speedKmh;
  point.speed = (uint8_t)(kmh > 255 ? 255 : (kmh < 0 ? 0 : lroundf(kmh)));
  point.flags |= FLAG_SPEED;

  if (fix.hasAltitude) {
    point.altitude = fix.altitude;
    point.flags |= FLAG_ALTITUDE;
  }
  if (fix.satellites > 0) {
    point.satellites = fix.satellites;
    point.flags |= FLAG_SATELLITES;
  }

  addReadings(point);
  return true;
}

void addReadings(Point &point) {
  int dbm = signalDbm();
  if (dbm < 0) {
    point.signal = (uint8_t)(dbm < -255 ? 255 : -dbm);
    point.ext |= EXT_SIGNAL;
  }

  if (bmpReady && bmp.performReading()) {
    point.pressure = (uint16_t)lroundf(bmp.pressure / 10.0f);  // Pa to hPa * 10
    point.temperature = (int16_t)lroundf(bmp.temperature * 10.0f);
    point.flags |= FLAG_PRESSURE | FLAG_TEMPERATURE;
  }

  uint32_t millivolts = vehicleMillivolts();
  if (millivolts > 0) {
    point.voltage = (uint16_t)(millivolts / 10);
    point.ext |= EXT_VOLTAGE;
  }
}

bool waitForFix(Point &point, Status status, unsigned long timeoutMs) {
  unsigned long start = millis();
  do {
    if (samplePoint(point, status)) return true;
    // Keeps reading the external receiver while waiting
    for (int i = 0; i < 100; i++) {
      gnssPoll();
      delay(20);
    }
  } while (millis() - start < timeoutMs);
  return false;
}

bool readGravity(int16_t gravity[3]) {
  if (!lisReady) return false;

  // Average of 32 samples at 100Hz, filters the vibrations
  float sum[3] = {0, 0, 0};
  for (int i = 0; i < 32; i++) {
    sensors_event_t event;
    lis.getEvent(&event);
    sum[0] += event.acceleration.x;
    sum[1] += event.acceleration.y;
    sum[2] += event.acceleration.z;
    delay(10);
  }
  // m/s^2 to mg
  for (int axis = 0; axis < 3; axis++) gravity[axis] = (int16_t)lroundf(sum[axis] / 32.0f / 9.80665f * 1000.0f);
  return true;
}

float tiltDegrees(const int16_t a[3], const int16_t b[3]) {
  float dot = 0, normA = 0, normB = 0;
  for (int axis = 0; axis < 3; axis++) {
    dot += (float)a[axis] * b[axis];
    normA += (float)a[axis] * a[axis];
    normB += (float)b[axis] * b[axis];
  }
  if (normA <= 0 || normB <= 0) return 0;
  float cosine = dot / sqrtf(normA * normB);
  if (cosine > 1) cosine = 1;
  if (cosine < -1) cosine = -1;
  return acosf(cosine) * 180.0f / (float)M_PI;
}

static double toRadians(double degrees) {
  return degrees * M_PI / 180.0;
}

double distanceMeters(const Point &a, const Point &b) {
  double lat1 = toRadians(a.lat / 1e5);
  double lat2 = toRadians(b.lat / 1e5);
  double dLat = lat2 - lat1;
  double dLon = toRadians((b.lon - a.lon) / 1e5);

  double h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return EARTH_RADIUS * 2 * atan2(sqrt(h), sqrt(1 - h));
}
