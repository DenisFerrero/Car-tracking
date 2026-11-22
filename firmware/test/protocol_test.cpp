// Host program for the cross test with the server: builds frames with the firmware
// encoder and verifies the ACK and COMMAND frames built by the server, plus the rolling
// code of the owner beacon. Driven by cross-check.ts.
//
// Usage: protocol_test <device key hex> <ack hex> <command hex>

#include <stdio.h>
#include <string.h>
#include "../owner_code.h"
#include "../protocol.h"

using namespace proto;

static void printHex(const char *label, const uint8_t *data, size_t length) {
  printf("%s ", label);
  for (size_t i = 0; i < length; i++) printf("%02x", data[i]);
  printf("\n");
}

static size_t fromHex(const char *hex, uint8_t *out, size_t capacity) {
  size_t length = strlen(hex) / 2;
  if (length > capacity) return 0;
  for (size_t i = 0; i < length; i++) {
    unsigned int value;
    sscanf(hex + i * 2, "%2x", &value);
    out[i] = (uint8_t)value;
  }
  return length;
}

int main(int argc, char **argv) {
  if (argc < 4) return 2;

  uint8_t key[KEY_SIZE];
  if (!parseHexKey(argv[1], key)) return 3;

  uint8_t frame[MAX_FRAME_SIZE];

  DeviceInfo info = {"SIMCOM INCORPORATED", "A7670E-LASE", "A7670M7_V1.11.1", "2.0.0"};
  size_t length = buildHello(frame, sizeof(frame), key, parseImei("863820040182648"), 1000, 1763625600, info);
  printHex("hello", frame, length);

  // A drive with negative coordinates, missing fields and every status
  Point points[40];
  memset(points, 0, sizeof(points));
  for (int i = 0; i < 40; i++) {
    Point &p = points[i];
    p.timestamp = 1763625600 + i * 5 + (i > 20 ? 60 : 0);
    p.lat = 4546421 + i * 41 - (i % 7) * 13;
    p.lon = -7318003 - i * 52 + (i % 5) * 9;
    p.altitude = (int16_t)(-12 + i);
    p.pressure = (uint16_t)(10132 - i * 3);
    p.temperature = (int16_t)(-55 + i * 4);
    p.speed = (uint8_t)(i * 6);
    p.flags = (uint8_t)(i % 4) | FLAG_ALTITUDE | FLAG_PRESSURE | FLAG_TEMPERATURE | FLAG_SPEED;
    if (i % 9 == 4) p.flags &= (uint8_t)~(FLAG_PRESSURE | FLAG_TEMPERATURE);
    if (i % 11 == 6) p.flags &= (uint8_t)~(FLAG_ALTITUDE | FLAG_SPEED);
    // Optional fields of the extension byte
    if (i % 3 == 0) {
      p.satellites = (uint8_t)(4 + i % 9);
      p.flags |= FLAG_SATELLITES;
    }
    if (i % 4 == 1) {
      p.signal = (uint8_t)(60 + i);
      p.ext |= EXT_SIGNAL;
    }
    if (i % 5 == 2) {
      p.voltage = (uint16_t)(1180 + i * 7);
      p.ext |= EXT_VOLTAGE;
    }
    // Events available only on some points, an empty mask must not be encoded
    p.ext |= EXT_EVENTS;
    p.events = (uint8_t)(i % 13 == 0 ? (EVENT_MOTION | EVENT_TILT) : 0);
    // Points without fix: stale position and serving cell
    if (i % 8 == 7) {
      p.ext |= EXT_STALE | EXT_CELL;
      p.mcc = 222;
      p.mnc = (uint16_t)(i % 3 == 0 ? 1 : 88);
      p.cellArea = 0x5A1Bu + (uint32_t)i;
      p.cellId = 26834437u + (uint32_t)i * 1000u;
    }
  }

  // Small capacity to force the split in several frames
  size_t offset = 0;
  uint32_t counter = 2000;
  while (offset < 40) {
    size_t consumed = 0;
    length = buildTelemetry(frame, 120, key, 300, counter++, points + offset, 40 - offset, &consumed);
    if (length == 0 || consumed == 0) return 4;
    printHex("telemetry", frame, length);
    offset += consumed;
  }

  uint8_t ack[64];
  size_t ackLength = fromHex(argv[2], ack, sizeof(ack));
  uint32_t deviceId = 0;
  // Separate statement: the evaluation order of printf arguments is unspecified
  bool ackOk = parseAck(ack, ackLength, key, &deviceId);
  printf("ack %s %u\n", ackOk ? "ok" : "fail", (unsigned)deviceId);

  // A tampered ACK must be rejected
  ack[ackLength - 1] ^= 1;
  printf("tampered %s\n", parseAck(ack, ackLength, key, &deviceId) ? "ok" : "fail");

  // COMMAND of the server: commands, then the result for the server
  uint8_t command[MAX_FRAME_SIZE];
  size_t commandLength = fromHex(argv[3], command, sizeof(command));
  CommandFrame parsed;
  if (parseCommand(command, commandLength, key, parsed)) {
    printf("command %u %u %d", parsed.counter, parsed.timestamp, parsed.unknown ? 1 : 0);
    for (size_t i = 0; i < parsed.count; i++) printf(" %u:%u", parsed.commands[i].id, parsed.commands[i].seconds);
    printf("\n");
    length = buildCommandResult(frame, sizeof(frame), key, 300, 3000, 1763625800, parsed.counter, RESULT_EXPIRED);
    printHex("result", frame, length);
  } else {
    printf("command fail\n");
  }
  // A COMMAND is not an ACK, even with the right key
  printf("command-as-ack %s\n", parseAck(command, commandLength, key, &deviceId) ? "ok" : "fail");

  // FW_OFFER: size, SHA-256 and version; the plain request and result frames
  uint8_t offerFrame[MAX_FRAME_SIZE];
  size_t offerLength = fromHex(argv[4], offerFrame, sizeof(offerFrame));
  FirmwareOffer offer;
  if (parseFirmwareOffer(offerFrame, offerLength, key, offer)) {
    printf("offer %u %u %s ", offer.counter, offer.size, offer.version);
    for (int i = 0; i < 32; i++) printf("%02x", offer.sha256[i]);
    printf("\n");
  } else {
    printf("offer fail\n");
  }
  CommandFrame offerAsCommand;
  printf("offer-as-command %s\n", parseCommand(offerFrame, offerLength, key, offerAsCommand) ? "ok" : "fail");
  length = buildFirmwareRequest(frame, 70000, 32768);
  printHex("fw-request", frame, length);
  length = buildFirmwareResult(frame, FW_BAD_HASH);
  printHex("fw-result", frame, length);

  // Daily update check and extra data of the vehicle (JSON as it is)
  length = buildUpdateCheck(frame, sizeof(frame), key, 300, 2000, 1763625700);
  printHex("update-check", frame, length);
  const char *json = "{\"rpm\":820,\"coolant\":88.5,\"dtc\":[\"P0420\"]}";
  length = buildExtra(frame, sizeof(frame), key, 300, 2001, 1763625710, json, strlen(json));
  printHex("extra", frame, length);
  char big[MAX_FRAME_SIZE];
  memset(big, 'x', sizeof(big));
  printf("extra-limits %u %u\n", (unsigned)buildExtra(frame, sizeof(frame), key, 300, 2002, 1763625710, big, sizeof(big)),
         (unsigned)buildExtra(frame, sizeof(frame), key, 300, 2002, 1763625710, json, 0));

  // Owner beacon, key = the device key
  uint8_t advertising[owner::ADVERTISING_SIZE];
  owner::buildAdvertising(advertising, key, 7, 58787520);
  printHex("beacon", advertising, sizeof(advertising));
  uint8_t tagId = 0;
  uint32_t beaconCounter = 0;
  bool beaconValid = owner::parseAdvertising(advertising, sizeof(advertising), key, &tagId, &beaconCounter);
  advertising[17] ^= 0x80;
  bool beaconTampered = owner::parseAdvertising(advertising, sizeof(advertising), key, &tagId, &beaconCounter);
  printf("beacon-check %s %s\n", beaconValid ? "ok" : "fail", beaconTampered ? "ok" : "fail");

  return 0;
}
