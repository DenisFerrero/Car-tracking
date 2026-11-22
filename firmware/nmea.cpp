#include "nmea.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

namespace {

const float KNOTS_TO_KMH = 1.852f;

int hexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

int twoDigits(const char *text) {
  if (text[0] < '0' || text[0] > '9' || text[1] < '0' || text[1] > '9') return -1;
  return (text[0] - '0') * 10 + (text[1] - '0');
}

// Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm)
int32_t daysFromCivil(int year, unsigned month, unsigned day) {
  year -= month <= 2;
  const int32_t era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yoe = (unsigned)(year - era * 400);
  const unsigned doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (int32_t)doe - 719468;
}

// ddmm.mmmm (latitude) or dddmm.mmmm (longitude) to 1e-5 degrees
bool parseCoordinate(const char *value, const char *hemisphere, int32_t *out) {
  if (!value[0] || !hemisphere[0]) return false;
  double raw = atof(value);
  double degrees = floor(raw / 100.0);
  double result = degrees + (raw - degrees * 100.0) / 60.0;
  if (hemisphere[0] == 'S' || hemisphere[0] == 'W') result = -result;
  else if (hemisphere[0] != 'N' && hemisphere[0] != 'E') return false;
  *out = (int32_t)lround(result * 1e5);
  return true;
}

}  // namespace

uint32_t nmeaUnixTime(int year, int month, int day, int hour, int minute, int second) {
  return (uint32_t)daysFromCivil(year, (unsigned)month, (unsigned)day) * 86400UL +
         (uint32_t)hour * 3600UL + (uint32_t)minute * 60UL + (uint32_t)second;
}

NmeaParser::NmeaParser()
    : length(0), receiving(false), fixCount(0), ggaAltitude(0), ggaHasAltitude(false), ggaSatellites(0) {
  memset(&current, 0, sizeof(current));
}

bool NmeaParser::feed(char c) {
  if (c == '$') {
    receiving = true;
    length = 0;
    return false;
  }
  if (!receiving) return false;

  if (c == '\r' || c == '\n') {
    receiving = false;
    buffer[length] = '\0';
    return parseSentence();
  }
  if (length >= MAX_SENTENCE) {
    receiving = false;  // Too long, not NMEA
    return false;
  }
  buffer[length++] = c;
  return false;
}

bool NmeaParser::parseSentence() {
  // Checksum: XOR of the characters between '$' and '*'
  char *star = strchr(buffer, '*');
  if (!star || star[1] == '\0' || star[2] == '\0') return false;
  int high = hexValue(star[1]);
  int low = hexValue(star[2]);
  if (high < 0 || low < 0) return false;

  uint8_t checksum = 0;
  for (char *p = buffer; p < star; p++) checksum ^= (uint8_t)*p;
  if (checksum != (uint8_t)((high << 4) | low)) return false;
  *star = '\0';

  // Splits the fields in place, empty fields stay empty strings
  char *fields[MAX_FIELDS];
  size_t count = 0;
  char *field = buffer;
  while (count < MAX_FIELDS) {
    fields[count++] = field;
    char *comma = strchr(field, ',');
    if (!comma) break;
    *comma = '\0';
    field = comma + 1;
  }

  // Talker (2 chars) + sentence type, e.g. GNRMC
  if (strlen(fields[0]) != 5) return false;
  const char *type = fields[0] + 2;
  if (strcmp(type, "RMC") == 0) return parseRmc(fields, count);
  if (strcmp(type, "GGA") == 0) parseGga(fields, count);
  return false;
}

// $xxRMC,hhmmss.ss,A,ddmm.mm,N,dddmm.mm,E,knots,course,ddmmyy,...
bool NmeaParser::parseRmc(char **fields, size_t count) {
  if (count < 10 || fields[2][0] != 'A') return false;

  const char *time = fields[1];
  const char *date = fields[9];
  if (strlen(time) < 6 || strlen(date) != 6) return false;
  int hour = twoDigits(time), minute = twoDigits(time + 2), second = twoDigits(time + 4);
  int day = twoDigits(date), month = twoDigits(date + 2), year = twoDigits(date + 4);
  if (hour < 0 || minute < 0 || second < 0 || day < 1 || month < 1 || month > 12 || year < 0) return false;

  int32_t lat, lon;
  if (!parseCoordinate(fields[3], fields[4], &lat) || !parseCoordinate(fields[5], fields[6], &lon)) return false;

  current.timestamp = nmeaUnixTime(2000 + year, month, day, hour, minute, second);
  current.lat = lat;
  current.lon = lon;
  current.speedKmh = fields[7][0] ? (float)atof(fields[7]) * KNOTS_TO_KMH : 0;
  current.altitude = ggaAltitude;
  current.hasAltitude = ggaHasAltitude;
  current.satellites = ggaSatellites;
  fixCount++;
  return true;
}

// $xxGGA,hhmmss.ss,lat,N,lon,E,quality,satellites,hdop,altitude,M,...
void NmeaParser::parseGga(char **fields, size_t count) {
  if (count < 10) return;
  bool fix = fields[6][0] && fields[6][0] != '0';
  ggaSatellites = fix && fields[7][0] ? (uint8_t)atoi(fields[7]) : 0;
  ggaHasAltitude = fix && fields[9][0];
  ggaAltitude = ggaHasAltitude ? (int16_t)lround(atof(fields[9])) : 0;
}
