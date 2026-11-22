// Copy this file to secrets.h (ignored by git) and fill in the values

// WiFi (CONNECTION_MODE 1 or 3)
#define WIFI_SSID "MyWiFi"
#define WIFI_PASSWORD "MyWiFiPassword"

// SIM (CONNECTION_MODE 2 or 3)
#define SIM_APN "iot.1nce.net"
#define SIM_USER ""
#define SIM_PASSWORD ""
#define SIM_PIN ""

// Key of this tracker, derived from its IMEI: it authenticates every frame, the HELLO
// included (no other credential). From the backend folder: npm run provision -- <IMEI>
// Saved in NVS at the first boot: images for the updates over the air are built with all
// zeros here and use the saved key.
#define DEVICE_KEY "0000000000000000000000000000000000000000000000000000000000000000"

// Owner keychain (OWNER_TAG in configurations.h)
// 1: address of the BLE tag, as shown by a BLE scanner app (nRF Connect)
// #define OWNER_TAG_ADDRESS "c3:12:ab:45:67:89"
// 2: key shared with hardware/owner-beacon, e.g. openssl rand -hex 32
// #define OWNER_TAG_KEY "0000000000000000000000000000000000000000000000000000000000000000"
