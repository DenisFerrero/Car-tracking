#include "protocol.h"
#include "chacha_poly.h"
#include <string.h>

namespace proto {

namespace {

const uint32_t DIRECTION_UPLINK = 0;
const uint32_t DIRECTION_DOWNLINK = 1;

// Bounded writer, a failed write marks the whole buffer as overflowed
struct Writer {
  uint8_t *data;
  size_t capacity;
  size_t length;
  bool overflow;

  Writer(uint8_t *buffer, size_t size) : data(buffer), capacity(size), length(0), overflow(false) {}

  void u8(uint8_t value) {
    if (length >= capacity) {
      overflow = true;
      return;
    }
    data[length++] = value;
  }

  void u32(uint32_t value) {
    for (int i = 0; i < 4; i++) u8((uint8_t)(value >> (8 * i)));
  }

  void u64(uint64_t value) {
    for (int i = 0; i < 8; i++) u8((uint8_t)(value >> (8 * i)));
  }

  void varint(uint32_t value) {
    while (value >= 0x80) {
      u8((uint8_t)(value | 0x80));
      value >>= 7;
    }
    u8((uint8_t)value);
  }

  void zigzag(int32_t value) {
    varint(((uint32_t)value << 1) ^ (uint32_t)(value >> 31));
  }

  void string(const char *value) {
    size_t size = value ? strlen(value) : 0;
    if (size > 255) size = 255;
    u8((uint8_t)size);
    for (size_t i = 0; i < size; i++) u8((uint8_t)value[i]);
  }
};

void buildNonce(uint8_t nonce[12], uint32_t counter, uint32_t timestamp, uint32_t direction) {
  uint32_t values[3] = {counter, timestamp, direction};
  for (int v = 0; v < 3; v++) {
    for (int i = 0; i < 4; i++) nonce[v * 4 + i] = (uint8_t)(values[v] >> (8 * i));
  }
}

// Encrypts in place the plaintext placed right after the header, appends the truncated tag
size_t seal(uint8_t *out, size_t headerLength, size_t plainLength, const uint8_t key[KEY_SIZE],
            uint32_t counter, uint32_t timestamp) {
  uint8_t nonce[12];
  uint8_t tag[16];
  buildNonce(nonce, counter, timestamp, DIRECTION_UPLINK);

  uint8_t *body = out + headerLength;
  chacha20_poly1305_encrypt(body, tag, body, plainLength, out, headerLength, key, nonce);
  memcpy(body + plainLength, tag, TAG_SIZE);
  return headerLength + plainLength + TAG_SIZE;
}

void writeHeader(Writer &writer, FrameType type) {
  writer.u8((uint8_t)((VERSION << 4) | type));
}

// Delta encoding state, the first point is relative to the header timestamp and zeros
struct DeltaState {
  uint32_t timestamp;
  int32_t lat, lon, altitude, pressure, temperature, voltage;
};

void writePoint(Writer &writer, const Point &point, DeltaState &state) {
  uint8_t ext = point.ext & (EXT_SIGNAL | EXT_VOLTAGE | EXT_EVENTS | EXT_CELL | EXT_STALE);
  if (point.events == 0) ext &= (uint8_t)~EXT_EVENTS;
  uint8_t flags = (uint8_t)(point.flags & ~FLAG_EXTENDED);
  if (ext) flags |= FLAG_EXTENDED;

  writer.u8(flags);
  writer.varint(point.timestamp - state.timestamp);
  writer.zigzag(point.lat - state.lat);
  writer.zigzag(point.lon - state.lon);
  state.timestamp = point.timestamp;
  state.lat = point.lat;
  state.lon = point.lon;

  if (point.flags & FLAG_ALTITUDE) {
    writer.zigzag(point.altitude - state.altitude);
    state.altitude = point.altitude;
  }
  if (point.flags & FLAG_PRESSURE) {
    writer.zigzag((int32_t)point.pressure - state.pressure);
    state.pressure = point.pressure;
  }
  if (point.flags & FLAG_TEMPERATURE) {
    writer.zigzag(point.temperature - state.temperature);
    state.temperature = point.temperature;
  }
  if (point.flags & FLAG_SPEED) {
    writer.varint(point.speed);
  }
  if (point.flags & FLAG_SATELLITES) {
    writer.u8(point.satellites);
  }
  if (ext) {
    writer.u8(ext);
    if (ext & EXT_SIGNAL) writer.u8(point.signal);
    if (ext & EXT_VOLTAGE) {
      writer.zigzag((int32_t)point.voltage - state.voltage);
      state.voltage = point.voltage;
    }
    if (ext & EXT_EVENTS) writer.u8(point.events);
    if (ext & EXT_CELL) {
      writer.varint(point.mcc);
      writer.varint(point.mnc);
      writer.varint(point.cellArea);
      writer.varint(point.cellId);
    }
  }
}

// Authenticates and decrypts a downlink frame without device reference (ACK, COMMAND)
bool openDownlink(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], FrameType type,
                  uint8_t *plain, size_t capacity, size_t *plainLength, uint32_t *counter, uint32_t *timestamp) {
  const size_t headerLength = 1 + 4 + 4;
  if (length <= headerLength + TAG_SIZE || length > MAX_FRAME_SIZE) return false;
  if (frame[0] != (uint8_t)((VERSION << 4) | type)) return false;

  *counter = 0;
  *timestamp = 0;
  for (int i = 0; i < 4; i++) {
    *counter |= (uint32_t)frame[1 + i] << (8 * i);
    *timestamp |= (uint32_t)frame[5 + i] << (8 * i);
  }

  uint8_t nonce[12];
  buildNonce(nonce, *counter, *timestamp, DIRECTION_DOWNLINK);

  size_t cipherLength = length - headerLength - TAG_SIZE;
  if (cipherLength > capacity) return false;
  if (chacha20_poly1305_decrypt_truncated(plain, frame + headerLength, cipherLength, frame + length - TAG_SIZE,
                                          TAG_SIZE, frame, headerLength, key, nonce) != 0) {
    return false;
  }
  *plainLength = cipherLength;
  return true;
}

// Bounded reader of a decrypted payload
struct Reader {
  const uint8_t *data;
  size_t length;
  size_t offset;
  bool error;

  Reader(const uint8_t *buffer, size_t size) : data(buffer), length(size), offset(0), error(false) {}

  bool done() const { return offset >= length; }

  uint8_t u8() {
    if (offset >= length) {
      error = true;
      return 0;
    }
    return data[offset++];
  }

  uint32_t varint() {
    uint32_t value = 0;
    for (uint32_t shift = 0; shift < 35; shift += 7) {
      uint8_t byte = u8();
      if (error) return 0;
      value |= (uint32_t)(byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return value;
    }
    error = true;
    return 0;
  }
};

int hexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

}  // namespace

size_t buildHello(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint64_t imei,
                  uint32_t counter, uint32_t timestamp, const DeviceInfo &info) {
  if (capacity < TAG_SIZE) return 0;

  Writer writer(out, capacity - TAG_SIZE);
  writeHeader(writer, HELLO);
  writer.u64(imei);
  writer.u32(counter);
  writer.u32(timestamp);
  size_t headerLength = writer.length;

  writer.string(info.manufacturer);
  writer.string(info.model);
  writer.string(info.revision);
  writer.string(info.firmware);
  if (writer.overflow) return 0;

  return seal(out, headerLength, writer.length - headerLength, key, counter, timestamp);
}

size_t buildTelemetry(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                      uint32_t counter, const Point *points, size_t count, size_t *consumed) {
  *consumed = 0;
  if (count == 0 || capacity < TAG_SIZE) return 0;

  Writer writer(out, capacity - TAG_SIZE);
  writeHeader(writer, TELEMETRY);
  writer.varint(deviceId);
  writer.u32(counter);
  writer.u32(points[0].timestamp);
  size_t headerLength = writer.length;
  if (writer.overflow) return 0;

  DeltaState state = {points[0].timestamp, 0, 0, 0, 0, 0, 0};
  for (size_t i = 0; i < count; i++) {
    // Points must be in chronological order, a varint can't encode a negative dt
    if (i > 0 && points[i].timestamp < state.timestamp) break;

    size_t before = writer.length;
    DeltaState backup = state;
    writePoint(writer, points[i], state);
    if (writer.overflow) {
      writer.length = before;
      writer.overflow = false;
      state = backup;
      break;
    }
    (*consumed)++;
  }
  if (*consumed == 0) return 0;

  return seal(out, headerLength, writer.length - headerLength, key, counter, points[0].timestamp);
}

bool parseAck(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], uint32_t *deviceId,
              uint32_t *timestamp) {
  uint8_t plain[16];
  size_t plainLength = 0;
  uint32_t counter = 0, time = 0;
  if (!openDownlink(frame, length, key, ACK, plain, sizeof(plain), &plainLength, &counter, &time)) return false;

  Reader reader(plain, plainLength);
  uint32_t value = reader.varint();
  if (reader.error || value == 0) return false;

  *deviceId = value;
  if (timestamp) *timestamp = time;
  return true;
}

bool parseCommand(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], CommandFrame &out) {
  uint8_t plain[64];
  size_t plainLength = 0;
  if (!openDownlink(frame, length, key, COMMAND, plain, sizeof(plain), &plainLength, &out.counter, &out.timestamp)) {
    return false;
  }

  out.count = 0;
  out.unknown = false;
  Reader reader(plain, plainLength);
  while (!reader.done() && out.count < MAX_COMMANDS) {
    uint8_t id = reader.u8();
    Command &command = out.commands[out.count];
    command.id = (CommandId)id;
    command.seconds = 0;

    if (id == CMD_LIVE || id == CMD_ANTITHEFT) {
      command.seconds = reader.varint();
    } else if (id != CMD_LOCATE) {
      // Unknown size: the rest of the frame can't be decoded
      out.unknown = true;
      break;
    }
    if (reader.error) {
      out.unknown = true;
      break;
    }
    out.count++;
  }
  return true;
}

size_t buildCommandResult(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                          uint32_t counter, uint32_t timestamp, uint32_t commandCounter, CommandResult result) {
  if (capacity < TAG_SIZE) return 0;

  Writer writer(out, capacity - TAG_SIZE);
  writeHeader(writer, COMMAND_RESULT);
  writer.varint(deviceId);
  writer.u32(counter);
  writer.u32(timestamp);
  size_t headerLength = writer.length;

  writer.u32(commandCounter);
  writer.u8((uint8_t)result);
  if (writer.overflow) return 0;

  return seal(out, headerLength, writer.length - headerLength, key, counter, timestamp);
}

// Frame of the tracker with the device id and an opaque payload
static size_t buildBytes(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], FrameType type, uint32_t deviceId,
                         uint32_t counter, uint32_t timestamp, const uint8_t *data, size_t dataLength) {
  if (capacity < TAG_SIZE) return 0;

  Writer writer(out, capacity - TAG_SIZE);
  writeHeader(writer, type);
  writer.varint(deviceId);
  writer.u32(counter);
  writer.u32(timestamp);
  size_t headerLength = writer.length;

  for (size_t i = 0; i < dataLength; i++) writer.u8(data[i]);
  if (writer.overflow) return 0;

  return seal(out, headerLength, writer.length - headerLength, key, counter, timestamp);
}

size_t buildUpdateCheck(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                        uint32_t counter, uint32_t timestamp) {
  return buildBytes(out, capacity, key, UPDATE_CHECK, deviceId, counter, timestamp, nullptr, 0);
}

size_t buildExtra(uint8_t *out, size_t capacity, const uint8_t key[KEY_SIZE], uint32_t deviceId,
                  uint32_t counter, uint32_t timestamp, const char *json, size_t jsonLength) {
  if (jsonLength == 0) return 0;
  return buildBytes(out, capacity, key, EXTRA, deviceId, counter, timestamp, (const uint8_t *)json, jsonLength);
}

bool parseFirmwareOffer(const uint8_t *frame, size_t length, const uint8_t key[KEY_SIZE], FirmwareOffer &out) {
  uint8_t plain[4 + 32 + 1 + 255];
  size_t plainLength = 0;
  uint32_t timestamp = 0;
  if (!openDownlink(frame, length, key, FW_OFFER, plain, sizeof(plain), &plainLength, &out.counter, &timestamp)) {
    return false;
  }
  if (plainLength < 4 + 32 + 1) return false;
  out.size = 0;
  for (int i = 0; i < 4; i++) out.size |= (uint32_t)plain[i] << (8 * i);
  memcpy(out.sha256, plain + 4, 32);
  size_t versionLength = plain[36];
  if (37 + versionLength != plainLength || versionLength >= sizeof(out.version)) return false;
  memcpy(out.version, plain + 37, versionLength);
  out.version[versionLength] = 0;
  return true;
}

size_t buildFirmwareRequest(uint8_t *out, uint32_t offset, uint16_t length) {
  out[0] = (uint8_t)((VERSION << 4) | FW_REQUEST);
  for (int i = 0; i < 4; i++) out[1 + i] = (uint8_t)(offset >> (8 * i));
  out[5] = (uint8_t)length;
  out[6] = (uint8_t)(length >> 8);
  return 7;
}

size_t buildFirmwareResult(uint8_t *out, FirmwareStatus status) {
  out[0] = (uint8_t)((VERSION << 4) | FW_RESULT);
  out[1] = (uint8_t)status;
  return 2;
}

bool parseHexKey(const char *hex, uint8_t key[KEY_SIZE]) {
  if (!hex || strlen(hex) != KEY_SIZE * 2) return false;
  for (size_t i = 0; i < KEY_SIZE; i++) {
    int high = hexValue(hex[i * 2]);
    int low = hexValue(hex[i * 2 + 1]);
    if (high < 0 || low < 0) return false;
    key[i] = (uint8_t)((high << 4) | low);
  }
  return true;
}

uint64_t parseImei(const char *imei) {
  if (!imei || strlen(imei) != 15) return 0;
  uint64_t value = 0;
  for (int i = 0; i < 15; i++) {
    if (imei[i] < '0' || imei[i] > '9') return 0;
    value = value * 10 + (uint64_t)(imei[i] - '0');
  }
  return value;
}

}  // namespace proto
