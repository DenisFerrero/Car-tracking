#include <Arduino.h>

struct coordinate {
  float x;
  float y;
  float altitude;
  float pressure;
  float temperature;
  int device_id = 0;

  String toStringJSON () {
    return "{\"x\": " + String(this->x) + ", \"y\": " + String(this->y) + ", \"altitude\": " + String(this->altitude) + ", \"pressure\": " + String(this->pressure) + ", \"temperature\": " + String(this->temperature) + ", \"device_id\": " + String(this->device_id) + "}";
  }
};

coordinate getCoordinate ();
double calculateDistance(const coordinate &coord1, const coordinate &coord2);
bool shareCoordinate (const coordinate &coord1, const coordinate &coord2);