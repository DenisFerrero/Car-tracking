// Unit tests of the plain C++ modules of the firmware: adaptive sampling and NMEA parser.
//
// Build: g++ -o units_test firmware/test/units_test.cpp firmware/track_filter.cpp firmware/nmea.cpp
// (MSVC: cl /EHsc /TP with the same files). Exit code 0 when every check passes.

#include <stdio.h>
#include <string.h>
#include <math.h>
#include "../track_filter.h"
#include "../nmea.h"
#include "../cell.h"
#include "../owner_code.h"

using namespace proto;

static int failures = 0;

static void check(bool condition, const char *name) {
  printf("%s %s\n", condition ? "PASS" : "FAIL", name);
  if (!condition) failures++;
}

// A sample every 5 seconds, position in meters from the origin (45N, 9E)
static Point at(uint32_t second, double northMeters, double eastMeters) {
  Point point;
  memset(&point, 0, sizeof(point));
  point.timestamp = 1763625600 + second;
  point.lat = 4500000 + (int32_t)lround(northMeters / 1.1132);
  point.lon = 900000 + (int32_t)lround(eastMeters / (1.1132 * cos(45.0 * 3.14159265358979 / 180.0)));
  return point;
}

static TrackFilterConfig config() {
  TrackFilterConfig value = {10, 15, 30, 300};
  return value;
}

static void testStraightRoad() {
  TrackFilter filter(config());
  Point out;
  int recorded = 0;
  // 2 minutes at 72 km/h (100 m every 5 s) with 3 m of GPS noise
  for (uint32_t t = 0; t <= 120; t += 5) {
    if (filter.push(at(t, t * 20.0, (t % 10 == 0) ? 3 : -3), out)) recorded++;
  }
  // The first point, then one every 30 seconds
  check(recorded == 5, "straight road: a point every 30 seconds");
}

static void testTurn() {
  TrackFilter filter(config());
  Point out;
  uint32_t vertices[8];
  int recorded = 0;
  // North for 50 seconds, then east: the corner (t = 50) must be recorded
  for (uint32_t t = 0; t <= 100; t += 5) {
    Point point = t <= 50 ? at(t, t * 20.0, 0) : at(t, 1000, (t - 50) * 20.0);
    if (filter.push(point, out) && recorded < 8) vertices[recorded++] = out.timestamp - 1763625600;
  }
  bool corner = false;
  for (int i = 0; i < recorded; i++) corner = corner || vertices[i] == 50;
  check(corner, "turn: the corner is recorded");
}

static void testStandingStill() {
  TrackFilter filter(config());
  Point out;
  int recorded = 0;
  // 10 minutes stopped with 5 m of noise: the first point and one every 5 minutes
  for (uint32_t t = 0; t <= 600; t += 5) {
    if (filter.push(at(t, (t % 3) * 5.0, 0), out)) recorded++;
  }
  check(recorded == 3, "standing still: a point every 5 minutes");
}

static void testFlushAndOrder() {
  TrackFilter filter(config());
  Point out;
  filter.push(at(0, 0, 0), out);
  check(!filter.push(at(0, 100, 0), out), "a sample older than the anchor is ignored");
  filter.push(at(5, 100, 0), out);
  filter.push(at(10, 200, 0), out);
  check(filter.flush(out) && out.timestamp == 1763625610, "flush returns the last sample");
  check(!filter.flush(out), "nothing left after the flush");
}

static bool feed(NmeaParser &parser, const char *sentence) {
  bool fix = false;
  for (const char *c = sentence; *c; c++) fix = parser.feed(*c) || fix;
  return fix;
}

static void testNmea() {
  NmeaParser parser;
  check(!feed(parser, "$GNGGA,092750.00,4528.12345,N,00911.40018,E,1,08,1.01,123.4,M,47.9,M,,*43\r\n"),
        "GGA alone is not a fix");
  check(feed(parser, "$GNRMC,092751.00,A,4528.12345,N,00911.40018,E,26.998,77.52,201126,,,A*7B\r\n"),
        "RMC with status A is a fix");

  const NmeaFix &fix = parser.fix();
  check(fix.timestamp == 1795166871UL, "RMC date and time in unix seconds");
  check(fix.lat == 4546872 && fix.lon == 919000, "coordinates in 1e-5 degrees");
  check(fabs(fix.speedKmh - 50.0) < 0.1, "speed from knots to km/h");
  check(fix.hasAltitude && fix.altitude == 123 && fix.satellites == 8, "altitude and satellites from GGA");

  check(!feed(parser, "$GNRMC,092752.00,V,,,,,,,201126,,,N*6E\r\n"), "status V is not a fix");
  check(!feed(parser, "$GNRMC,092753.00,A,4528.12345,N,00911.40018,E,26.998,77.52,201126,,,A*00\r\n"),
        "wrong checksum is ignored");
  check(feed(parser, "$GPRMC,000000.00,A,3352.12800,S,15112.60000,W,0.0,,010125,,,A*74\r\n") &&
            parser.fix().lat == -3386880 && parser.fix().lon == -15121000,
        "southern and western hemispheres");
  check(parser.fixes() == 2, "fix counter");
}

static void testCell() {
  CellInfo cell;
  check(parseCpsi("\r\n+CPSI: LTE,Online,222-01,0x5A1B,26834437,123,EUTRAN-BAND3,1300,5,5,-94,-1105,-750,13\r\n\r\nOK\r\n", cell),
        "cpsi lte");
  check(cell.mcc == 222 && cell.mnc == 1 && cell.area == 0x5A1B && cell.id == 26834437, "cpsi lte values");
  check(parseCpsi("+CPSI: GSM,Online,222-88,0x1f40,12345,-70,0,0,0,0,0,0", cell), "cpsi gsm");
  check(cell.mnc == 88 && cell.area == 0x1F40 && cell.id == 12345, "cpsi gsm values");
  check(!parseCpsi("+CPSI: NO SERVICE,Online", cell), "cpsi no service");
  check(!parseCpsi("+CPSI: LTE,Online,000-00,0x0000,0,0", cell), "cpsi empty cell");
  check(!parseCpsi("ERROR", cell), "cpsi error");
}

static bool equalsHex(const uint8_t *data, const char *hex) {
  for (size_t i = 0; hex[2 * i]; i++) {
    unsigned int value;
    if (sscanf(hex + 2 * i, "%2x", &value) != 1 || data[i] != value) return false;
  }
  return true;
}

static void testOwnerCode() {
  // FIPS 180-2 and RFC 4231 test case 2
  uint8_t digest[32];
  owner::sha256((const uint8_t *)"abc", 3, digest);
  check(equalsHex(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), "sha256 abc");
  const char *long_message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
  owner::sha256((const uint8_t *)long_message, strlen(long_message), digest);
  check(equalsHex(digest, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"), "sha256 two blocks");
  const char *data = "what do ya want for nothing?";
  owner::hmacSha256((const uint8_t *)"Jefe", 4, (const uint8_t *)data, strlen(data), digest);
  check(equalsHex(digest, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), "hmac rfc4231");

  uint8_t key[owner::KEY_SIZE];
  for (size_t i = 0; i < sizeof(key); i++) key[i] = (uint8_t)i;
  uint8_t advertising[owner::ADVERTISING_SIZE];
  owner::buildAdvertising(advertising, key, 3, 123456);
  uint8_t tagId = 0;
  uint32_t counter = 0;
  check(owner::parseAdvertising(advertising, sizeof(advertising), key, &tagId, &counter) && tagId == 3 &&
            counter == 123456, "beacon round trip");
  advertising[6] ^= 1;  // a different counter with the old code
  check(!owner::parseAdvertising(advertising, sizeof(advertising), key, &tagId, &counter), "beacon forged counter");
  advertising[6] ^= 1;
  key[0] ^= 1;
  check(!owner::parseAdvertising(advertising, sizeof(advertising), key, &tagId, &counter), "beacon other key");
}

int main() {
  testStraightRoad();
  testTurn();
  testStandingStill();
  testFlushAndOrder();
  testNmea();
  testCell();
  testOwnerCode();
  printf(failures == 0 ? "ALL PASSED\n" : "%d FAILED\n", failures);
  return failures == 0 ? 0 : 1;
}
