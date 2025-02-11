#include "GPS_config.h"
#include <connections.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <MQTT.h>
#include <configurations.h>
#include <TinyGsmClient.h>

WiFiClient wifiNet;
TinyGsm modem(Serial1);
TinyGsmClient gsmNet(modem);

#define TINY_GSM_RX_BUFFER 2048 // Set RX buffer to 1Kb

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

  return connected;
}

bool startGPS () {
  // Turn on DC boost to power on the modem
  #ifdef BOARD_POWERON_PIN
  pinMode(BOARD_POWERON_PIN, OUTPUT);
  digitalWrite(BOARD_POWERON_PIN, HIGH);
  #endif

  // Set modem reset pin ,reset modem
  pinMode(MODEM_RESET_PIN, OUTPUT);
  digitalWrite(MODEM_RESET_PIN, !MODEM_RESET_LEVEL);
  delay(100);
  digitalWrite(MODEM_RESET_PIN, MODEM_RESET_LEVEL);
  delay(2600);
  digitalWrite(MODEM_RESET_PIN, !MODEM_RESET_LEVEL);

  // Turn on modem
  pinMode(BOARD_PWRKEY_PIN, OUTPUT);
  digitalWrite(BOARD_PWRKEY_PIN, LOW);
  delay(100);
  digitalWrite(BOARD_PWRKEY_PIN, HIGH);
  delay(1000);
  digitalWrite(BOARD_PWRKEY_PIN, LOW);

  // Set modem baud
  Serial1.begin(115200, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);

  Serial.println("Start modem...");
  delay(3000);

  /*
   * [Comment from example]
   * During testing, it was found that there may be a power outage.
   * Add a loop detection here. When the GPS timeout does not start,
   * resend the AT to check if the modem is online
   */
  Serial.print("Modem starting");
  int retry = 0;
  while (!modem.testAT(1000)) {
    Serial.print(".");
    if (retry++ > 10) {
      digitalWrite(BOARD_PWRKEY_PIN, LOW);
      delay(100);
      digitalWrite(BOARD_PWRKEY_PIN, HIGH);
      delay(1000);    //Ton = 1000ms ,Min = 500ms, Max 2000ms
      digitalWrite(BOARD_PWRKEY_PIN, LOW);
      retry = 0;
    }
  }
  Serial.println();

  String modemName = "UNKOWN";
  while (1) {
    modemName = modem.getModemName();
    if (modemName == "UNKOWN") {
      Serial.println("Unable to obtain module information normally, try again");
      delay(1000);
    } else if (modemName.startsWith("A7670G")) {
      while (1) {
        Serial.println("A7670G does not support built-in GPS function, please run examples/GPSShield");
        delay(1000);
      }
    } else {
      Serial.print("Model Name:");
      Serial.println(modemName);
      break;
    }
    delay(5000);
  }

  delay(200);

  Serial.println("Enabling GPS/GNSS/GLONASS");
  while (!modem.enableGPS(MODEM_GPS_ENABLE_GPIO, MODEM_GPS_ENABLE_LEVEL)) {
      Serial.print(".");
  }

  Serial.println();
  Serial.println("GPS Enabled");

  modem.setGPSBaud(115200);

  modem.setGPSMode(3);    //GPS + BD

  modem.configNMEASentence(1, 1, 1, 1, 1, 1);

  modem.setGPSOutputRate(1);

  modem.enableNMEA();

  return true;
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

  return client.connected();
}

String getMacAddress () {
  return WiFi.macAddress();
}

deviceInfo getDeviceInfo () {
  deviceInfo result;

  result.imei = "12345";
  result.manufacturer = "manufacturer";
  result.model = "model";
  result.revision = "revision";

  // TODO Test
  // result.imei = getDeviceProperty(SIM_IMEI);
  // result.manufacturer = getDeviceProperty(SIM_MANUFACTURER);
  // result.model = getDeviceProperty(SIM_MODEL);
  // result.revision = getDeviceProperty(SIM_REVISION);

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
