// Print those variables at startup
#define START_UP_PRINT_ENV 1
// 1. WiFi / 2. Sim module / 3. WiFi priority, fallback to Sim module. Default 1
#define CONNECTION_MODE 1
// WiFI credentials
#define WIFI_SSID "MyWifi"
#define WIFI_PASSWORD "12345"
// Connection retry attempt. Default 100
#define WIFI_CONNECTION_RETRY 100
// Delay between each reconnection attempt. Default 1000
#define WIFI_CONNECTION_DELAY 1000

// MQTT Broker address and credentials 
#define MQTT_BROKER "192.168.1.254"
// Default 1883
#define MQTT_PORT 1883
#define MQTT_USERNAME "admin"
#define MQTT_PASSWORD "admin"
// Connection retry attempt. Default 100
#define MQTT_CONNECTION_RETRY 100
// Delay between each reconnection attempt. Default 1000
#define MQTT_CONNECTION_DELAY 100
// TLS certificate if the connection is protected. Download certificate from here: https://letsencrypt.org/certs/isrgrootx1.pem
// #define MQTT_CERTIFICATE

// Publish coordinates each X milliseconds. Default 20*1000
#define PUBLISH_RATE 20*1000
// Distance, in meters, threshold between the last coordinate and the current one, if greater allow to share the position
// Method use to prevent to share the current position if the car is steady and not moving, allows to save the amount of MB used by the Sim module
// If you want to share the distance any way just set the value to 0
#define THRESHOLD_DISTANCE 3