#include <Arduino.h>

struct coordinate {
  double x;
  double y;
  double altitude;
  float pressure;
  float temperature;
  int device_id = 0;

  String toStringJSON () {
    return "{\"x\": " + String(this->x, 8) + ", \"y\": " + String(this->y, 8) + ", \"altitude\": " + String(this->altitude, 8) + ", \"pressure\": " + String(this->pressure, 3) + ", \"temperature\": " + String(this->temperature, 3) + ", \"device_id\": " + String(this->device_id) + "}";
  }
};

coordinate getCoordinate ();
double calculateDistance(const coordinate &coord1, const coordinate &coord2);
bool shareCoordinate (const coordinate &coord1, const coordinate &coord2);
void smartDelay(unsigned long ms);