#include "uplink.h"
#include "configurations.h"
#include "clock.h"
#include "ota.h"
#include <Preferences.h>

using namespace proto;

// The counter is reserved in blocks: one NVS write every 256 frames instead of every frame.
// After a reboot the unused part of the block is skipped, a nonce is never repeated.
static const uint32_t COUNTER_BLOCK = 256;

static Preferences prefs;
static uint8_t key[KEY_SIZE];
static uint64_t imei = 0;
static String imeiText;
static ModemInfo modemInfo;

static uint32_t deviceId = 0;
static uint32_t counter = 0;
static uint32_t counterReserved = 0;
// ACK received on the current connection
static bool acknowledged = false;

// Last command frame applied (NVS): the server sends a command at every connection until
// it's answered, it's applied once and only answered again
static uint32_t lastCommandCounter = 0;
static CommandResult lastCommandResult = RESULT_OK;
static CommandHandler commandHandler = nullptr;

// Command frame received while reading, handled by uplinkLoop() (not sent from inside
// the read loop of the connection)
static uint8_t pendingCommand[MAX_FRAME_SIZE];
static size_t pendingCommandLength = 0;

static uint8_t frame[MAX_FRAME_SIZE];

// Extra data waiting for the connection
static const size_t EXTRA_QUEUE = 4;
struct ExtraReading {
  uint32_t timestamp;
  uint16_t length;
  char json[EXTRA_MAX_SIZE];
};
static ExtraReading extraQueue[EXTRA_QUEUE];
static size_t extraCount = 0;

// Automatic updates (AUTO_UPDATE 1): one request a day, after the ACK
static const uint32_t UPDATE_CHECK_SEC = 86400;
static bool updateCheckDue = false;

static uint32_t nextCounter() {
  if (counter >= counterReserved) {
    counterReserved = counter + COUNTER_BLOCK;
    prefs.putUInt("ctr", counterReserved);
  }
  return counter++;
}

bool uplinkInit(const ModemInfo &info) {
  modemInfo = info;
  imeiText = info.imei;
  imei = parseImei(info.imei.c_str());
  if (imei == 0) {
    Serial.printf("[UPLINK] Invalid IMEI '%s'\n", info.imei.c_str());
    return false;
  }
  if (!parseHexKey(DEVICE_KEY, key)) {
    Serial.println("[UPLINK] Invalid DEVICE_KEY, it must be 64 hex characters");
    return false;
  }
  prefs.begin("tracker", false);

  // The key stays in the NVS: the images of the updates over the air are built with a key
  // of zeros and keep the one of the first installation
  bool compiled = false;
  for (size_t i = 0; i < KEY_SIZE; i++) compiled |= key[i] != 0;
  if (compiled) {
    uint8_t stored[KEY_SIZE];
    if (prefs.getBytes("key", stored, KEY_SIZE) != KEY_SIZE || memcmp(stored, key, KEY_SIZE) != 0) {
      prefs.putBytes("key", key, KEY_SIZE);
    }
  } else if (prefs.getBytes("key", key, KEY_SIZE) != KEY_SIZE) {
    Serial.println("[UPLINK] No device key: flash once a firmware with the DEVICE_KEY of this tracker");
    return false;
  }
  lastCommandCounter = prefs.getUInt("cmd", 0);
  lastCommandResult = (CommandResult)prefs.getUChar("cmdres", RESULT_OK);

  counter = prefs.getUInt("ctr", 0);
  counterReserved = counter + COUNTER_BLOCK;
  prefs.putUInt("ctr", counterReserved);

  // A different modem (IMEI) means a different device: forget the old id
  if (prefs.getULong64("imei", 0) == imei) {
    deviceId = prefs.getUInt("id", 0);
  } else {
    prefs.putULong64("imei", imei);
    prefs.putUInt("id", 0);
    deviceId = 0;
  }

  Serial.printf("[UPLINK] IMEI %s, device id %u\n", imeiText.c_str(), (unsigned)deviceId);
  return true;
}

void uplinkOnConnected(uint32_t timestamp) {
  // At every connection: it authenticates the tracker and refreshes its information
  acknowledged = false;
  pendingCommandLength = 0;

  DeviceInfo info = {
    modemInfo.manufacturer.c_str(),
    modemInfo.model.c_str(),
    modemInfo.revision.c_str(),
    FIRMWARE_VERSION "+" FIRMWARE_VARIANT
  };
  size_t length = buildHello(frame, sizeof(frame), key, imei, nextCounter(), timestamp, info);
  if (length > 0 && serverSend(frame, length)) {
    Serial.printf("[UPLINK] HELLO sent (%u bytes)\n", (unsigned)length);
  }
}

bool uplinkWaitAck(unsigned long timeoutMs) {
  unsigned long start = millis();
  while (!acknowledged && millis() - start < timeoutMs && serverConnected()) {
    uplinkLoop();
    delay(20);
  }
  return uplinkReady();
}

bool uplinkReady() {
  return acknowledged && serverConnected();
}

void uplinkSetCommandHandler(CommandHandler handler) {
  commandHandler = handler;
}

static void sendCommandResult(uint32_t commandCounter, CommandResult result) {
  uint32_t now = utcNow();
  size_t length = buildCommandResult(frame, sizeof(frame), key, deviceId, nextCounter(), now,
                                     commandCounter, result);
  if (length > 0 && serverSend(frame, length)) {
    Serial.printf("[UPLINK] Command %u answered: %u\n", (unsigned)commandCounter, (unsigned)result);
  }
}

static void handleCommand(const uint8_t *data, size_t length) {
  CommandFrame command;
  if (!parseCommand(data, length, key, command)) {
    Serial.println("[UPLINK] Invalid command, authentication failed");
    return;
  }
  utcFromServer(command.timestamp);

  if (command.counter < lastCommandCounter) return;  // replayed
  if (command.counter == lastCommandCounter) {
    // Already applied: the server didn't receive the result yet
    sendCommandResult(command.counter, lastCommandResult);
    return;
  }

  CommandResult result = command.unknown ? RESULT_UNKNOWN_COMMAND : RESULT_OK;
  for (size_t i = 0; i < command.count; i++) {
    CommandResult single = commandHandler ? commandHandler(command.commands[i], command.timestamp)
                                          : RESULT_UNKNOWN_COMMAND;
    if (single != RESULT_OK && result == RESULT_OK) result = single;
  }

  lastCommandCounter = command.counter;
  lastCommandResult = result;
  prefs.putUInt("cmd", lastCommandCounter);
  prefs.putUChar("cmdres", (uint8_t)result);
  sendCommandResult(command.counter, result);
}

bool uplinkQueueExtra(const char *json) {
  size_t length = json ? strlen(json) : 0;
  if (length == 0 || length > EXTRA_MAX_SIZE) return false;
  if (extraCount == EXTRA_QUEUE) {
    memmove(extraQueue, extraQueue + 1, sizeof(ExtraReading) * (EXTRA_QUEUE - 1));
    extraCount--;
  }
  ExtraReading &reading = extraQueue[extraCount++];
  reading.timestamp = utcNow();
  reading.length = (uint16_t)length;
  memcpy(reading.json, json, length);
  return true;
}

static void sendExtra() {
  while (extraCount > 0) {
    const ExtraReading &reading = extraQueue[0];
    size_t length = buildExtra(frame, sizeof(frame), key, deviceId, nextCounter(), reading.timestamp,
                               reading.json, reading.length);
    if (length > 0 && !serverSend(frame, length)) return;  // Retried at the next loop
    Serial.printf("[UPLINK] Extra data sent (%u bytes)\n", (unsigned)length);
    memmove(extraQueue, extraQueue + 1, sizeof(ExtraReading) * (EXTRA_QUEUE - 1));
    extraCount--;
  }
}

static void sendUpdateCheck() {
  updateCheckDue = false;
  uint32_t now = utcNow();
  size_t length = buildUpdateCheck(frame, sizeof(frame), key, deviceId, nextCounter(), now);
  if (length > 0 && serverSend(frame, length)) {
    prefs.putUInt("updchk", now);
    Serial.println("[UPLINK] Update check sent");
  }
}

void uplinkLoop() {
  serverLoop();
  if (!uplinkReady()) return;

  if (pendingCommandLength > 0) {
    size_t length = pendingCommandLength;
    pendingCommandLength = 0;
    handleCommand(pendingCommand, length);
  }
  if (extraCount > 0) sendExtra();
  if (updateCheckDue) sendUpdateCheck();
}

void uplinkPoll(unsigned long timeoutMs) {
  unsigned long start = millis();
  while (millis() - start < timeoutMs && serverConnected()) {
    uplinkLoop();
    delay(50);
  }
}

void uplinkOnFrame(const uint8_t *data, size_t length) {
  if (length == 0) return;
  uint8_t type = data[0] & 0x0F;

  if (type == FW_CHUNK) {
    otaOnChunk(data, length);
    return;
  }
  if (type == FW_OFFER) {
    FirmwareOffer offer;
    if (acknowledged && parseFirmwareOffer(data, length, key, offer)) otaOffer(offer);
    return;
  }
  if (type == COMMAND) {
    // Commands only after the ACK: they need the server time and the device id
    if (acknowledged && length <= sizeof(pendingCommand)) {
      memcpy(pendingCommand, data, length);
      pendingCommandLength = length;
    }
    return;
  }
  if (type != ACK) return;

  uint32_t id = 0, timestamp = 0;
  if (!parseAck(data, length, key, &id, &timestamp)) {
    Serial.println("[UPLINK] Invalid ACK, authentication failed");
    return;
  }
  utcFromServer(timestamp);

  acknowledged = true;
  otaConfirm();
#if AUTO_UPDATE
  updateCheckDue = timestamp - prefs.getUInt("updchk", 0) >= UPDATE_CHECK_SEC;
#endif
  if (id != deviceId) {
    deviceId = id;
    prefs.putUInt("id", id);
  }
  Serial.printf("[UPLINK] Registered, device id %u\n", (unsigned)id);
}

size_t uplinkSend(const Point *points, size_t count) {
  if (!uplinkReady()) return 0;

  size_t sent = 0;
  while (sent < count) {
    size_t consumed = 0;
    size_t length = buildTelemetry(frame, sizeof(frame), key, deviceId, nextCounter(),
                                   points + sent, count - sent, &consumed);
    if (length == 0 || !serverSend(frame, length)) break;

    Serial.printf("[UPLINK] %u points sent (%u bytes)\n", (unsigned)consumed, (unsigned)length);
    sent += consumed;
  }
  return sent;
}
