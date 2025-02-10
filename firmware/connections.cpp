#include <connections.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <MQTT.h>
#include <configurations.h>

WiFiClientSecure secureWifiNet;
WiFiClient wifiNet;

MQTTClient client;

void printVariables () {
  #if START_UP_PRINT_ENV == 1

  Serial.println("--- Environmental variables ---");
  
  #pragma region Connection
  Serial.println("[CONNECTION]");
  Serial.print("Connection mode: ");
  #if CONNECTION_MODE == 1
  Serial.println("1. Wifi only");
  #endif
  #if CONNECTION_MODE == 2
  Serial.println("2. Sim module only");
  #endif
  #if CONNECTION_MODE == 3
  Serial.println("3. Wifi priority, fallback to Sim module");
  #endif

  #if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  Serial.print("WiFi SSID: ");
  Serial.println(WIFI_SSID);

  Serial.print("WiFi Password: ");
  Serial.println(WIFI_PASSWORD);

  Serial.print("WiFi connection retry attempt: ");
  Serial.println(WIFI_CONNECTION_RETRY);

  Serial.print("WiFi connection retry delay between each attempt: ");
  Serial.println(WIFI_CONNECTION_DELAY);
  #endif
  #pragma endregion Connection

  #pragma region MQTT
  Serial.println("[MQTT]");
  Serial.print("MQTT broker: ");
  Serial.println(MQTT_BROKER);
  
  Serial.print("MQTT port: ");
  Serial.println(MQTT_PORT);
  
  Serial.print("MQTT username: ");
  Serial.println(MQTT_USERNAME);
  
  Serial.print("MQTT password: ");
  Serial.println(MQTT_PASSWORD);
  
  Serial.print("MQTT connection retry attempt: ");
  Serial.println(MQTT_CONNECTION_RETRY);

  Serial.print("MQTT connection retry delay between each attempt: ");
  Serial.println(MQTT_CONNECTION_DELAY);

  #ifdef MQTT_CERTIFICATE
  Serial.print("MQTT certification: ");
  Serial.println(MQTT_CERTIFICATE);
  #endif
  #pragma endregion MQTT

  #pragma region Application

  Serial.println("[APPLICATION]");
  
  Serial.print("Publish coordinates each: ");
  Serial.print(PUBLISH_RATE);
  Serial.println("ms");

  Serial.print("Threshold distance: ");
  Serial.print(THRESHOLD_DISTANCE);
  Serial.println("m");
  #endif
  #pragma endregion Application

  Serial.println();
}

bool startConnection () {
  bool connected = false;

  #if CONNECTION_MODE == 1 || CONNECTION_MODE == 3

  Serial.print("Connecting to ");
  Serial.print(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempt = 0;  
  // Try to connect to the WIFI for X time
  while(WiFi.status() != WL_CONNECTED && attempt < WIFI_CONNECTION_RETRY){
    delay(WIFI_CONNECTION_DELAY);
    attempt += 1;
    Serial.print(".");
  }

  Serial.println();

  connected = WiFi.status() == WL_CONNECTED;

  #endif

  #if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  
  if (!connected) {
    connected = true;
  }

  #endif

  return connected;
}

bool startMQTT (MQTTClientCallbackSimple dispatcher) {

  Serial.print("Connecting to MQTT Broker: ");
  Serial.print(MQTT_BROKER);

  #if CONNECTION_MODE == 1
    #ifdef MQTT_CERTIFICATE
      client.begin(MQTT_BROKER, MQTT_PORT, secureWifiNet);
      secureWifiNet.setCACert(MQTT_CERTIFICATE);
    #else
      client.begin(MQTT_BROKER, MQTT_PORT, wifiNet);
    #endif

  #endif

  #if CONNECTION_MODE == 2
  #endif
  
  #if CONNECTION_MODE == 3
  // Use WiFi if connected
  if (WiFi.status() == WL_CONNECTED) {
    client.begin(MQTT_BROKER, MQTT_PORT, wifiNet);
  }
  #endif

  client.onMessage(dispatcher);

  int attempt = 0; 

  while (!client.connect(getMacAddress().c_str(), MQTT_USERNAME, MQTT_PASSWORD) && attempt < MQTT_CONNECTION_RETRY) {
    delay(MQTT_CONNECTION_DELAY);
    attempt += 1;
    Serial.print(".");
  }

  Serial.println();

  return client.connected(); 
}

bool reconnectMQTT () {
  Serial.print("Reconnecting to MQTT Broker: ");
  Serial.print(MQTT_BROKER);

  int attempt = 0; 

  while (!client.connect(getMacAddress().c_str(), MQTT_USERNAME, MQTT_PASSWORD) && attempt < MQTT_CONNECTION_RETRY) {
    delay(MQTT_CONNECTION_DELAY);
    attempt += 1;
    Serial.print(".");
  }
}

String getMacAddress () {
  String result = "";

  #if CONNECTION_MODE == 1
  result = "12345"; // WiFi.macAddress();
  #endif
  
  #if CONNECTION_MODE == 2
  result = "12345";
  #endif

  #if CONNECTION_MODE == 3
  // Pick the WiFi mac address if connected
  if (WiFi.status() == WL_CONNECTED) {
    result = "12345"; // WiFi.macAddress();
  }
  // Pick the Sim module mac address
  else {
    result = "12345";
  }
  #endif

  return result;
}

deviceInfo getDeviceInfo () {
  deviceInfo result;

  result.part_number = "part_number";
  result.serial_number = "serial_number";
  result.manufacturer = "manufacturer";
  result.model = "model";
  result.revision = "revision";
  result.imei = "imei";

  return result;
}
