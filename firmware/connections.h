#include <MQTT.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Arduino.h>
#include <configurations.h>
#include <TinyGsmClient.h>

void printVariables ();

extern WiFiClientSecure secureWifiNet;
extern WiFiClient wifiNet;
extern TinyGsmClient gsmNet;

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
bool startGPS ();
bool startMQTT(MQTTClientCallbackSimple dispatcher);
bool reconnectMQTT();

String getMacAddress ();
deviceInfo getDeviceInfo ();
String getDeviceProperty(String property);