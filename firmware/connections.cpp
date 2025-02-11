#include <connections.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <MQTT.h>
#include <configurations.h>
#include <TinyGsmClient.h>

WiFiClient wifiNet;
TinyGsm modem(Serial1);
TinyGsmClient gsmNet(modem);

// Code used to request information over the serial of the sim module
#define SIM_IMEI "CGSN"
#define SIM_MANUFACTURER "CGMI"
#define SIM_MODEL "CGMM"
#define SIM_REVISION "CGMR"

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

  #if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  Serial.print("SIM APN: ");
  Serial.println(SIM_APN);

  Serial.print("SIM User: ");
  Serial.println(SIM_USER);

  Serial.print("SIM Password: ");
  Serial.println(SIM_PASSWORD);
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
  Serial1.begin(115200, SERIAL_8N1, 26, 27);

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
    Serial.println("Initializing modem...");
    if (!modem.restart()) {
      Serial.println("Modem restart failed!");
      return false;
    }

    Serial.println("Connecting to cellular network...");
    if (!modem.gprsConnect(SIM_APN, SIM_USER, SIM_PASSWORD)) {
      Serial.println("GPRS connection failed!");
      return false;
    }

    Serial.println("Connected to cellular network!");
  }

  #endif

  // Enable GPS
  Serial1.println("AT+CGPS=1,1");
  delay(2000);

  return connected;
}

bool startMQTT (MQTTClientCallbackSimple dispatcher) {

  Serial.print("Connecting to MQTT Broker: ");
  Serial.print(MQTT_BROKER);

  #if CONNECTION_MODE == 1
  client.begin(MQTT_BROKER, MQTT_PORT, wifiNet);
  #endif

  #if CONNECTION_MODE == 2
  client.begin(MQTT_BROKER, MQTT_PORT, gsmNet);
  #endif
  
  #if CONNECTION_MODE == 3
  // Use WiFi if connected
  if (WiFi.status() == WL_CONNECTED) {
    client.begin(MQTT_BROKER, MQTT_PORT, wifiNet);
  } else {
    client.begin(MQTT_BROKER, MQTT_PORT, gsmNet);
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
  return WiFi.macAddress();
}

deviceInfo getDeviceInfo () {
  deviceInfo result;

  result.imei = getDeviceProperty(SIM_IMEI);
  result.manufacturer = getDeviceProperty(SIM_MANUFACTURER);
  result.model = getDeviceProperty(SIM_MODEL);
  result.revision = getDeviceProperty(SIM_REVISION);
  // Cannot gather from Sim module serial, remove them in future
  result.serial_number = "N/A";
  result.part_number = "N/A";

  return result;
}

String getDeviceProperty (String property) {
  String tempBuffer;
  String result = "";
  
  // TODO Apply "\r\n" if you not receive any response!
  Serial1.println("AT+" + property);
  delay(2000);

  while (Serial1.available()) { tempBuffer += Serial1.readString(); }

  // Parse response: +<property>: <result>
  if (tempBuffer.indexOf("+" + property + ":") != -1) {
    int indexMessage = tempBuffer.indexOf("+" + property + ":");
    result = tempBuffer.substring(indexMessage + (property.length()) + 2, tempBuffer.length());
  }

  return result;
}
