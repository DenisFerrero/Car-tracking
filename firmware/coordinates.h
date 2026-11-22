#ifndef COORDINATES_H
#define COORDINATES_H

#include <Arduino.h>
#include "protocol.h"

bool initSensors();
// Clears the latched motion interrupt of the LIS3DH, required before sleeping
void clearAccelInterrupt();

// Reads GNSS, signal strength, BMP390 and vehicle voltage. Returns false without a valid
// fix (and its UTC time).
bool samplePoint(proto::Point &point, proto::Status status);
// Signal, pressure, temperature and vehicle voltage, without the position
void addReadings(proto::Point &point);

// Waits for a fix up to timeoutMs, returns false on timeout
bool waitForFix(proto::Point &point, proto::Status status, unsigned long timeoutMs);

// Gravity vector in mg, averaged over about 0.3 seconds. False without the LIS3DH.
bool readGravity(int16_t gravity[3]);
// Angle between two gravity vectors: the car was lifted (tow truck, jack) when it changes
float tiltDegrees(const int16_t a[3], const int16_t b[3]);

// Distance in meters (haversine)
double distanceMeters(const proto::Point &a, const proto::Point &b);

#endif
