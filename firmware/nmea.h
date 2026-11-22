#ifndef NMEA_H
#define NMEA_H

// Minimal NMEA 0183 parser for an external GNSS module (u-blox, Quectel...): RMC for
// date, time, position and speed, GGA for altitude and satellites. Any talker (GP, GN,
// GL, GA, GB). Sentences with a wrong checksum are ignored.
//
// Plain C++ without Arduino dependencies, tested on the PC (firmware/test).

#include <stdint.h>
#include <stddef.h>

struct NmeaFix {
  uint32_t timestamp;   // unix seconds, UTC
  int32_t lat;          // 1e-5 degrees
  int32_t lon;          // 1e-5 degrees
  float speedKmh;
  int16_t altitude;     // meters, valid with hasAltitude
  bool hasAltitude;
  uint8_t satellites;   // used in the fix
};

// Unix seconds of a UTC date and time
uint32_t nmeaUnixTime(int year, int month, int day, int hour, int minute, int second);

class NmeaParser {
 public:
  NmeaParser();

  // Feeds one byte, returns true when it completed an RMC sentence with a valid fix
  bool feed(char c);

  // The last valid fix, altitude and satellites from the last GGA
  const NmeaFix &fix() const { return current; }
  // Number of RMC sentences with a valid fix parsed so far
  uint32_t fixes() const { return fixCount; }

 private:
  static const size_t MAX_SENTENCE = 100;
  static const size_t MAX_FIELDS = 20;

  char buffer[MAX_SENTENCE + 1];
  size_t length;
  bool receiving;
  NmeaFix current;
  uint32_t fixCount;
  int16_t ggaAltitude;
  bool ggaHasAltitude;
  uint8_t ggaSatellites;

  bool parseSentence();
  bool parseRmc(char **fields, size_t count);
  void parseGga(char **fields, size_t count);
};

#endif
