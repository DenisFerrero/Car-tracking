#include <configurations.h>

// 1. WiFi / 2. Sim module / 3. WiFi priority, fallback to Sim module
#ifndef CONNECTION_MODE
  #define CONNECTION_MODE 1 
#endif

// Not WIFI and not Sim module, fallback to WiFi
#if CONNECTION_MODE != 1 && CONNECTION_MODE != 2 && CONNECTION_MODE != 3
  #error "Invalid connection mode selected. Please select 1. WiFi or 2. Sim module"
#endif

#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  // Set WiFi SSID if not already
  #ifndef WIFI_SSID
    #error "Missing WiFi SSID"
  #endif
  // Set WiFi Password if not already
  #ifndef WIFI_PASSWORD
    #error "Missing WiFi Password"
  #endif
  // Set WiFi retry attempt if not already
  #ifndef WIFI_CONNECTION_RETRY
    #define WIFI_CONNECTION_RETRY 100
  #endif
  // Set Wifi delay between each reconnection attempt
  #ifndef WIFI_CONNECTION_DELAY
    #define WIFI_CONNECTION_DELAY 1000
  #endif
#endif

#ifndef MQTT_BROKER
  #error "MQTT broker not defined"
#endif

#ifndef MQTT_PORT
  #define MQTT_PORT 1883
#endif

#ifndef MQTT_USERNAME
  #error "MQTT username not defined"
#endif

#ifndef MQTT_PASSWORD
  #error "MQTT password not defined"
#endif

#ifndef MQTT_CONNECTION_RETRY
  #define MQTT_CONNECTION_RETRY 100
#endif

#ifndef MQTT_CONNECTION_DELAY
  #define MQTT_CONNECTION_DELAY 1000
#endif

// Interval for position sharing
#ifndef PUBLISH_RATE
  #define PUBLISH_RATE 20*1000
#endif
// Distance, in meters, threshold between the last coordinate and the current one, if greater allow to share the position
#ifndef THRESHOLD_DISTANCE
  #define THRESHOLD_DISTANCE 3
#endif