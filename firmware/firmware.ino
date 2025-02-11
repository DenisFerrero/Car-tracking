#include <MQTT.h>
#include <configurations.h>
#include <connections.h>
#include <coordinates.h>

// Manage the interval between each coordinate sharing using millis and not the delay
unsigned long lastMillis = 0;
// Device information regarding the Sim module
deviceInfo device;
// Last coordinate saved
coordinate lastCoordinate;

// When arrive a new message from MQTT broker decide what to do
void dispatcher (String &topic, String &message) {
  if (topic == ("discover." + device.imei + ".ack")) {
    try {
      device.id = atoi(message.c_str());
      Serial.print("Device ID received from main server: ");
      Serial.println(message);
    } catch (const std::exception& e) {
      Serial.println("[ERROR] Device acknowledge received: " + String(e.what()) + ". Message received: " + message);
    }
    // Unsubscribe from the discover ack even if an error has been triggered 
    client.unsubscribe("discover." + device.imei + ".ack");
  }
}

void setup() {
  Serial.begin(115200);
  // Print environment variables
  printVariables();

  // Start Wifi/Sim module connection
  if (!startConnection()) {
    Serial.println("Connection failed!!");
    while (1);
  } else {
    Serial.println("Connection started correctly");
  }
  // Start GPS
  startGPS();

  // Start MQTT connection to broker
  if (!startMQTT(dispatcher)) {
    Serial.println("Connection to MQTT failed");
    while(1);
  } else {
    Serial.println("Connection to MQTT started correctly");
  }

  // Get device informations after connection
  device = getDeviceInfo();
  // Subscribe to discover acknowledge message
  client.subscribe("discover." + device.imei + ".ack");
  // Send message for discover of the device
  client.publish("discover", device.toStringJSON().c_str());
}

void loop() {
  // In case the client is not connected try to reconnect
  if (!client.connected()) {
    reconnectMQTT();
  } else {
    // Check availability for any message
    client.loop();
    // Publish the coordinates
    if ((millis() - lastMillis) > PUBLISH_RATE && device.id > 0) {
      lastMillis = millis();
      
      coordinate currentCoordinate = getCoordinate();
      if (shareCoordinate(lastCoordinate, currentCoordinate)) {
        currentCoordinate.device_id = device.id;
        client.publish("coordinates", currentCoordinate.toStringJSON().c_str());
      }
      // Save the currentCoordinate into shareCoordinate for next iteraction
      lastCoordinate = currentCoordinate;
    }
  }
  // Continue reading data from GPS
  smartDelay(1);
}
