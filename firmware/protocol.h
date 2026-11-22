#ifndef PROTOCOL_H
#define PROTOCOL_H

// Binary protocol v2, documented in server/helpers/protocol.js.
// Plain C++ without Arduino dependencies: it's compiled on the PC as well, by the
// cross test with the server implementation (firmware/test).

#include <stdint.h>
#include <stddef.h>

namespace proto {

const uint8_t VERSION = 2;

enum FrameType : uint8_t {
  HELLO = 1, TELEMETRY = 2, ACK = 3, COMMAND = 4, COMMAND_RESULT = 5,
  FW_OFFER = 6, FW_REQUEST = 7, FW_CHUNK = 8, FW_RESULT = 9, UPDATE_CHECK = 10, EXTRA = 11
};

// Firmware update: data of a FW_CHUNK and largest window of a FW_REQUEST
const size_t FW_CHUNK_SIZE = 1024;
const size_t FW_MAX_WINDOW = 32 * 1024;
enum FirmwareStatus : uint8_t { FW_INSTALLED = 0, FW_BAD_HASH = 1, FW_WRITE_FAILED = 2, FW_TOO_BIG = 3, FW_TIMEOUT = 4 };

// Commands of the server, parameters in seconds relative to the frame timestamp
enum CommandId : uint8_t { CMD_LIVE = 1, CMD_ANTITHEFT = 2, CMD_LOCATE = 3 };
enum CommandResult : uint8_t { RESULT_OK = 0, RESULT_UNKNOWN_COMMAND = 1, RESULT_EXPIRED = 2 };

enum Status : uint8_t { MOVING = 0, ENGINE_OFF = 1, HEARTBEAT = 2, ALARM = 3 };

const uint8_t FLAG_STATUS_MASK = 0x03;
const uint8_t FLAG_ALTITUDE = 0x04;
const uint8_t FLAG_PRESSURE = 0x08;
const uint8_t FLAG_TEMPERATURE = 0x10;
const uint8_t FLAG_SPEED = 0x20;
const uint8_t FLAG_SATELLITES = 0x40;
const uint8_t FLAG_EXTENDED = 0x80;

// Fields of the extension byte, Point::ext tells which ones are available
const uint8_t EXT_SIGNAL = 0x01;
const uint8_t EXT_VOLTAGE = 0x02;
const uint8_t EXT_EVENTS = 0x04;
const uint8_t EXT_CELL = 0x08;
const uint8_t EXT_STALE = 0x10;  // position of the last fix, no payload

// Why a point was recorded besides the regular tracking
const uint8_t EVENT_MOTION = 0x01;
const uint8_t EVENT_TILT = 0x02;
const uint8_t EVENT_POWER_LOST = 0x04;
const uint8_t EVENT_LOW_BATTERY = 0x08;

const size_t KEY_SIZE = 32;
const size_t TAG_SIZE = 8;
// Fits the WebSocket buffer of the firmware (connections.cpp)
const size_t MAX_FRAME_SIZE = 480;

// One sample, 40 bytes: it's the record format of the offline spool as well.
// FLAG_EXTENDED is set by the encoder, from the fields available in ext.
struct Point {
  uint32_t timestamp;   // unix seconds
  int32_t lat;          // 1e-5 degrees
  int32_t lon;          // 1e-5 degrees
  uint32_t cellArea;    // TAC / LAC
  uint32_t cellId;
  uint16_t mcc;
  uint16_t mnc;
  int16_t altitude;     // meters
  uint16_t pressure;    // hPa * 10
  int16_t temperature;  // °C * 10
  uint16_t voltage;     // vehicle battery, V * 100
  uint8_t speed;        // km/h
  uint8_t flags;        // status + FLAG_*
  uint8_t satellites;   // used in the fix
  uint8_t signal;       // -dBm
  uint8_t events;       // EVENT_*
  uint8_t ext;          // EXT_*
};

struct Command {
  CommandId id;
  uint32_t seconds;
};

const size_t MAX_COMMANDS = 8;

struct CommandFrame {
  uint32_t counter;
  uint32_t timestamp;   // server time, unix seconds
  Command commands[MAX_COMMANDS];
  size_t count;
  bool unknown;         // stopped at an unknown command: the ones before it are valid
};

struct DeviceInfo {
  const char *manufacturer;
  const char *model;
  const char *revision;
  const char *firmware;
};

// Returns the frame length, 0 when it doesn't fit
size_t buildHello(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint64_t imei,
                  uint32_t counter, uint32_t timestamp, const DeviceInfo &info);

// Encodes as many points as fit in the capacity, the number is stored in consumed.
// Returns the frame length, 0 when not even one point fits.
size_t buildTelemetry(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                      uint32_t counter, const Point *points, size_t count, size_t *consumed);

// Authenticates an ACK and extracts the device id and the server time
bool parseAck(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], uint32_t *deviceId,
              uint32_t *timestamp = nullptr);

// Authenticates a COMMAND frame and decodes its commands
bool parseCommand(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], CommandFrame &out);

// Result of a COMMAND frame, sent back to the server
size_t buildCommandResult(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                          uint32_t counter, uint32_t timestamp, uint32_t commandCounter, CommandResult result);

struct FirmwareOffer {
  uint32_t counter;
  uint32_t size;
  uint8_t sha256[32];
  char version[32];
};

// Authenticates a FW_OFFER of the server
bool parseFirmwareOffer(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], FirmwareOffer &out);

// Plain frames of the download: request of a window, result of the installation
size_t buildFirmwareRequest(uint8_t *out, uint32_t offset, uint16_t length);
size_t buildFirmwareResult(uint8_t *out, FirmwareStatus status);

// Daily request of an automatic update (builds with AUTO_UPDATE 1): no payload, the
// server offers the newest image of the variant if the owner allows it
size_t buildUpdateCheck(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                        uint32_t counter, uint32_t timestamp);

// Extra data of the vehicle as a JSON object (e.g. read from another board), stored by the
// server as it is: new fields need no change of the firmware. timestamp = time of reading.
// Returns 0 when it doesn't fit in the capacity.
size_t buildExtra(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                  uint32_t counter, uint32_t timestamp, const char *json, size_t jsonLength);

// 64 hex chars to 32 bytes
bool parseHexKey(const char *hex, uint8_t key[KEY_SIZE]);

// 15 digits IMEI to integer, 0 when invalid
uint64_t parseImei(const char *imei);

}

#endif
