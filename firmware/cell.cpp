#include "cell.h"
#include <stdlib.h>
#include <string.h>

bool parseCpsi(const char *response, CellInfo &cell) {
  const char *start = strstr(response, "+CPSI:");
  if (!start) return false;
  start += 6;
  while (*start == ' ') start++;

  // System mode, operation mode, MCC-MNC, area (hex), cell id
  char line[128];
  size_t length = 0;
  while (start[length] && start[length] != '\r' && start[length] != '\n' && length < sizeof(line) - 1) {
    line[length] = start[length];
    length++;
  }
  line[length] = '\0';

  char *fields[6];
  size_t count = 0;
  char *field = line;
  while (count < 6) {
    fields[count++] = field;
    char *comma = strchr(field, ',');
    if (!comma) break;
    *comma = '\0';
    field = comma + 1;
  }
  if (count < 5) return false;
  if (strcmp(fields[0], "LTE") != 0 && strcmp(fields[0], "GSM") != 0 && strcmp(fields[0], "WCDMA") != 0) return false;

  char *dash = strchr(fields[2], '-');
  if (!dash) return false;
  *dash = '\0';
  char *end;
  unsigned long mcc = strtoul(fields[2], &end, 10);
  if (*end || mcc == 0 || mcc > 999) return false;
  unsigned long mnc = strtoul(dash + 1, &end, 10);
  if (*end || mnc > 999) return false;

  unsigned long area = strtoul(fields[3], &end, 16);  // "0x5A1B", strtoul skips the 0x prefix
  if (*end) return false;
  unsigned long id = strtoul(fields[4], &end, 10);
  if (*end || id == 0) return false;

  cell.mcc = (uint16_t)mcc;
  cell.mnc = (uint16_t)mnc;
  cell.area = (uint32_t)area;
  cell.id = (uint32_t)id;
  return true;
}
