#include <MQTT.h>
#include <WiFi.h>
#include <Arduino.h>

void printVariables ();

extern WiFiClient wifiNet;
extern MQTTClient client;

struct deviceInfo {
  int id = 0;
  String part_number;
  String serial_number;
  String manufacturer;
  String model;
  String revision;
  String imei;

  String toStringJSON () {
    return "{\"id\": " + String(this->id) + ", \"part_number\": \"" + this->part_number + "\", \"serial_number\": \"" + this->serial_number + "\", \"manufacturer\": \"" + this->manufacturer + "\", \"model\": \"" + this->model + "\", \"revision\": \"" + this->revision + "\", \"imei\": \"" + this->imei + "\"}";
  }
};

bool startConnection ();
bool startMQTT(MQTTClientCallbackSimple dispatcher);
bool reconnectMQTT();

String getMacAddress ();
deviceInfo getDeviceInfo ();