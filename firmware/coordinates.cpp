#include <coordinates.h>
#include <configurations.h>
#include <math.h>
#include <connections.h>
#include <TinyGPSPlus.h>
#define _USE_MATH_DEFINES // Ensures math constants are available for M_PI (π)

// Earth radius in meters to calculate the distance between two points
#define EARTH_RADIUS 6371000.0

// The TinyGPSPlus object
TinyGPSPlus gps;

// Get GPS current position
coordinate getCoordinate () {
  coordinate result;
  String response;

  Serial.print(F("Location: "));
  if (gps.location.isValid()) {
    Serial.print(gps.location.lat(), 8);
    result.x = gps.location.lat();
    Serial.print(F(","));
    Serial.print(gps.location.lng(), 8);
    result.y = gps.location.lng();
    Serial.println();
  } else {
    Serial.println(F("INVALID"));
  }

  Serial.print(F("Altitude: "));
  if (gps.altitude.isValid()) {
    Serial.print(gps.altitude.meters(), 6);
    result.altitude = gps.altitude.meters();
    Serial.println();
  } else {
    Serial.println(F("INVALID"));
  }

  // TODO
  result.pressure = 170;
  result.temperature = 35;

  return result;
}

// Convert degrees to radians
double toRadians(double degrees) {
  return degrees * M_PI / 180.0;
}

// Haversine formula to calculate distance (in meters) between two geographic coordinates [from ChatGPT]
double calculateDistance(const coordinate &coord1, const coordinate &coord2) {
  double lat1 = toRadians(coord1.y);
  double lon1 = toRadians(coord1.x);
  double lat2 = toRadians(coord2.y);
  double lon2 = toRadians(coord2.x);

  double dLat = lat2 - lat1;
  double dLon = lon2 - lon1;

  double a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return EARTH_RADIUS * c; // Distance in meters
}

// Conditional coordinate sharing
bool shareCoordinate (const coordinate &coord1, const coordinate &coord2) {
  #if THRESHOLD_DISTANCE <= 0
  return true;
  #endif
  #if THRESHOLD_DISTANCE > 0
  return calculateDistance(coord1, coord2) > THRESHOLD_DISTANCE;
  #endif
}

// This custom version of delay() ensures that the gps object is being "fed".
void smartDelay(unsigned long ms)
{
  int ch = 0;
  unsigned long start = millis();
  do {
    while (Serial1.available()) {
      ch = Serial1.read();
      // Serial.write(ch);
      gps.encode(ch);
    }
  } while (millis() - start < ms);
}