#include "connections.h"
#include "configurations.h"
#include "modem.h"
#include "protocol.h"
#include "settings.h"
#include <WiFi.h>
#include <esp_random.h>
#if SERVER_TLS
  #include <WiFiClientSecure.h>
  #if SERVER_TLS_VERIFY
    #include "certificates.h"
  #endif
#endif

#if SERVER_TLS
static WiFiClientSecure wifiNet;
#else
static WiFiClient wifiNet;
#endif

// Minimal WebSocket client (RFC 6455): binary messages without fragmentation (the frames
// of the protocol are small), pings for the keepalive
class WebSocketLink {
private:
  Client *_client;
  const char *_path;
  bool _connected = false;
  // Frames of the server: ACK, COMMAND, FW_OFFER and the chunks of the firmware updates
  uint8_t _incoming[5 + proto::FW_CHUNK_SIZE + 16];
  // Header (max 8 bytes for a client frame up to 64KB) and payload sent in one write:
  // two writes may become two TCP segments, 40 bytes of overhead each on the SIM
  uint8_t _outgoing[8 + proto::MAX_FRAME_SIZE];
  unsigned long _lastReceived = 0;
  unsigned long _lastPing = 0;

  bool sendFrame(uint8_t opcode, const uint8_t *payload, size_t size) {
    if (size > sizeof(_outgoing) - 8) return false;

    size_t headerSize = 0;
    _outgoing[headerSize++] = 0x80 | opcode;  // FIN + opcode
    if (size <= 125) {
      _outgoing[headerSize++] = 0x80 | (uint8_t)size;  // Mask bit + length
    } else {
      _outgoing[headerSize++] = 0x80 | 126;
      _outgoing[headerSize++] = (uint8_t)(size >> 8);
      _outgoing[headerSize++] = (uint8_t)size;
    }

    uint32_t mask = esp_random();
    uint8_t *maskKey = _outgoing + headerSize;
    memcpy(maskKey, &mask, 4);
    headerSize += 4;

    for (size_t i = 0; i < size; i++) {
      _outgoing[headerSize + i] = payload[i] ^ maskKey[i % 4];
    }
    return _client->write(_outgoing, headerSize + size) == headerSize + size;
  }

  bool readExact(uint8_t *buffer, size_t size) {
    return _client->readBytes(buffer, size) == size;
  }

  void discard(size_t size) {
    uint8_t scratch[64];
    while (size > 0) {
      size_t chunk = size < sizeof(scratch) ? size : sizeof(scratch);
      if (!readExact(scratch, chunk)) return;
      size -= chunk;
    }
  }

  // Reads the next frame: binary messages go to the handler, control frames are handled here
  void readFrame(FrameHandler handler) {
    uint8_t header[2];
    if (!readExact(header, 2)) return;
    _lastReceived = millis();

    bool fin = header[0] & 0x80;
    uint8_t opcode = header[0] & 0x0F;
    bool masked = header[1] & 0x80;
    uint64_t length = header[1] & 0x7F;

    if (length == 126) {
      uint8_t ext[2];
      if (!readExact(ext, 2)) return;
      length = ((uint16_t)ext[0] << 8) | ext[1];
    } else if (length == 127) {
      uint8_t ext[8];
      if (!readExact(ext, 8)) return;
      length = 0;
      for (int i = 0; i < 8; i++) length = (length << 8) | ext[i];
    }

    uint8_t mask[4] = {0, 0, 0, 0};
    if (masked && !readExact(mask, 4)) return;

    if (length > sizeof(_incoming)) {
      // Never expected from the server
      discard((size_t)length);
      stop();
      return;
    }

    uint8_t payload[125];
    switch (opcode) {
      case 0x2:  // Binary: one frame of the protocol
        if (readExact(_incoming, (size_t)length)) {
          for (size_t i = 0; i < length; i++) _incoming[i] ^= mask[i % 4];
          if (fin && handler) handler(_incoming, (size_t)length);
        }
        break;
      case 0x8:  // Close
        discard((size_t)length);
        stop();
        break;
      case 0x9:  // Ping: answer with a pong carrying the same payload
        if (length <= sizeof(payload) && readExact(payload, (size_t)length)) {
          for (size_t i = 0; i < length; i++) payload[i] ^= mask[i % 4];
          sendFrame(0xA, payload, (size_t)length);
        }
        break;
      default:  // Pong, text, continuation and reserved opcodes
        discard((size_t)length);
        break;
    }
  }

public:
  WebSocketLink(Client *client, const char *path) : _client(client), _path(path) {}

  bool connect() {
    _connected = false;
    const String &host = networkSettings().serverHost;
    if (host.length() == 0 || !_client->connect(host.c_str(), SERVER_PORT)) return false;

    // Handshake kept short: it's sent at every connection
    _client->print(String("GET ") + _path + " HTTP/1.1\r\n"
                   "Host: " + host + "\r\n"
                   "Upgrade: websocket\r\n"
                   "Connection: Upgrade\r\n"
                   "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                   "Sec-WebSocket-Version: 13\r\n\r\n");

    bool statusOk = false;
    unsigned long start = millis();
    while (_client->connected() && millis() - start < 10000) {
      String line = _client->readStringUntil('\n');
      if (line.startsWith("HTTP/1.1 101")) statusOk = true;
      if (line == "\r" || line.length() == 0) break;  // End of the headers
    }

    _connected = statusOk;
    if (!_connected) _client->stop();
    _lastReceived = _lastPing = millis();
    return _connected;
  }

  bool send(const uint8_t *frame, size_t length) {
    return connected() && sendFrame(0x2, frame, length);
  }

  void loop(FrameHandler handler) {
    while (connected() && _client->available() >= 2) readFrame(handler);
    if (!connected()) return;

    // Keepalive: a ping when the server has been silent for KEEP_ALIVE_SEC (the server
    // closes the connections silent for 3 minutes, Cloudflare after 100 seconds). Nothing
    // received for two keepalives: the connection is dead.
    unsigned long now = millis();
    if (now - _lastReceived >= 2 * KEEP_ALIVE_SEC * 1000UL + 10000UL) {
      Serial.println("[NET] Server silent, connection closed");
      stop();
    } else if (now - _lastReceived >= KEEP_ALIVE_SEC * 1000UL && now - _lastPing >= KEEP_ALIVE_SEC * 1000UL) {
      _lastPing = now;
      sendFrame(0x9, nullptr, 0);
    }
  }

  void close() {
    if (connected()) {
      const uint8_t normal[2] = {0x03, 0xE8};  // 1000
      sendFrame(0x8, normal, sizeof(normal));
    }
    stop();
  }

  void stop() {
    _client->stop();
    _connected = false;
  }

  bool connected() { return _connected && _client->connected(); }
};

static WebSocketLink wsWifi(&wifiNet, "/tracker");
static WebSocketLink wsGsm(&modemClient(), "/tracker");
static WebSocketLink *activeLink = nullptr;
static FrameHandler frameHandler = nullptr;

void printVariables() {
#if START_UP_PRINT_ENV == 1
  Serial.println("--- Configuration ---");
  Serial.printf("Firmware: %s+%s, automatic updates %s\n", FIRMWARE_VERSION, FIRMWARE_VARIANT, AUTO_UPDATE ? "on" : "off");
#if CONNECTION_MODE == 1
  Serial.println("Connection: WiFi");
#elif CONNECTION_MODE == 2
  Serial.println("Connection: SIM");
#else
  Serial.println("Connection: WiFi with SIM fallback");
#endif
#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  Serial.printf("WiFi SSID: %s\n", networkSettings().wifiSsid.c_str());
#endif
#if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  Serial.printf("SIM APN: %s\n", networkSettings().simApn.c_str());
#endif
  Serial.printf("Board: %s\n", BOARD_NAME);
  Serial.printf("Server: %s://%s:%d/tracker (keep alive %ds)\n", SERVER_TLS ? "wss" : "ws", networkSettings().serverHost.c_str(), SERVER_PORT,
                KEEP_ALIVE_SEC);
  Serial.printf("Sampling %dms, batch %d points, threshold %dm, stationary %ds\n",
                SAMPLE_INTERVAL_MS, BATCH_SIZE, THRESHOLD_DISTANCE, STATIONARY_INTERVAL_SEC);
  Serial.printf("Ignition pin %d (active %s), heartbeat %ds\n", PIN_IGNITION_SENSE,
                IGNITION_ACTIVE_LEVEL == HIGH ? "HIGH" : "LOW", HEARTBEAT_PERIOD_SEC);
  Serial.printf("Accelerometer pin %d, arm delay %ds, cooldown %ds, tilt %d degrees\n", PIN_ACCEL_INT,
                ALARM_ARM_DELAY_SEC, ALARM_COOLDOWN_SEC, TILT_THRESHOLD_DEG);
  Serial.printf("Adaptive sampling %s (%dm, max %ds), environment every %ds\n", ADAPTIVE_SAMPLING ? "on" : "off",
                ADAPTIVE_TOLERANCE_METERS, ADAPTIVE_MAX_INTERVAL_SEC, ENVIRONMENT_INTERVAL_SEC);
  Serial.printf("GNSS: %s, vehicle voltage %s, power good %s, cell location %s, owner tag %d\n",
                GNSS_SOURCE == GNSS_SOURCE_MODEM ? "modem" : "external",
                VEHICLE_VOLTAGE_SENSE ? "on" : "off", POWER_GOOD_SENSE ? "on" : "off",
                CELL_LOCATION ? "on" : "off", OWNER_TAG);
  Serial.println();
#endif
}

bool startNetwork() {
#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  if (WiFi.status() != WL_CONNECTED) {
    const NetworkSettings &net = networkSettings();
    Serial.printf("Connecting to WiFi %s", net.wifiSsid.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(net.wifiSsid.c_str(), net.wifiPassword.c_str());
    for (int attempt = 0; attempt < WIFI_CONNECTION_RETRY && WiFi.status() != WL_CONNECTED; attempt++) {
      delay(WIFI_CONNECTION_DELAY);
      Serial.print(".");
    }
    Serial.println(WiFi.status() == WL_CONNECTED ? " OK" : " FAILED");
  }
  if (WiFi.status() == WL_CONNECTED) return true;
#endif

#if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  return modemAttach();
#else
  return false;
#endif
}

bool networkConnected() {
#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  if (WiFi.status() == WL_CONNECTED) return true;
#endif
#if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  return modemAttached();
#else
  return false;
#endif
}

void serverBegin(FrameHandler onFrame) {
  frameHandler = onFrame;
#if SERVER_TLS
#if SERVER_TLS_VERIFY
  wifiNet.setCACert(SERVER_CA_BUNDLE);
#else
  wifiNet.setInsecure();
#endif
#endif
}

bool serverConnect() {
  if (serverConnected()) return true;
  if (!networkConnected() && !startNetwork()) return false;

#if CONNECTION_MODE == 1
  activeLink = &wsWifi;
#elif CONNECTION_MODE == 2
  activeLink = &wsGsm;
#else
  activeLink = WiFi.status() == WL_CONNECTED ? &wsWifi : &wsGsm;
#endif

  Serial.printf("Connecting to %s...", networkSettings().serverHost.c_str());
  bool connected = activeLink->connect();
  Serial.println(connected ? " OK" : " FAILED");
  return connected;
}

bool serverConnected() {
  return activeLink != nullptr && activeLink->connected();
}

void serverLoop() {
  if (activeLink != nullptr) activeLink->loop(frameHandler);
}

bool serverSend(const uint8_t *frame, size_t length) {
  return activeLink != nullptr && activeLink->send(frame, length);
}

void serverDisconnect() {
  if (activeLink != nullptr) activeLink->close();
}

int signalDbm() {
#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  if (WiFi.status() == WL_CONNECTED) return WiFi.RSSI();
#endif
  return modemSignalDbm();
}

void prepareForSleep() {
  Serial.println("[POWER] Preparing for deep sleep...");

  if (serverConnected()) {
    activeLink->close();
    delay(100);
  }

#if CONNECTION_MODE == 1 || CONNECTION_MODE == 3
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
#endif

  // The modem hosts the GNSS: it's powered in every connection mode
  modemPowerOff();
}
