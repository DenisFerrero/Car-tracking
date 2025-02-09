#include <coordinates.h>
#include <configurations.h>
#include <math.h>
#define _USE_MATH_DEFINES // Ensures math constants are available for M_PI (π)

// Earth radius in meters to calculate the distance between two points
#define EARTH_RADIUS 6371000.0

// Get GPS current position
coordinate getCoordinate () {
  coordinate result;

  result.x = 45.45833;
  result.y = 7.8527995;
  result.altitude = 130;
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