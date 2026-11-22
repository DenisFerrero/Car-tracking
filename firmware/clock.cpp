#include "clock.h"
#include <esp_attr.h>

// utc = clockNow() + offset
RTC_DATA_ATTR static int64_t rtcUtcOffset = 0;
RTC_DATA_ATTR static bool rtcUtcKnown = false;

// Tolerated difference before correcting: the RTC drifts a few seconds a day
#define CLOCK_TOLERANCE_SEC 2

time_t clockNow() {
  return time(nullptr);
}

uint32_t utcNow() {
  return rtcUtcKnown ? (uint32_t)(clockNow() + rtcUtcOffset) : 0;
}

bool utcKnown() {
  return rtcUtcKnown;
}

void utcFromGnss(uint32_t utc) {
  int64_t offset = (int64_t)utc - (int64_t)clockNow();
  if (!rtcUtcKnown || offset - rtcUtcOffset > CLOCK_TOLERANCE_SEC || rtcUtcOffset - offset > CLOCK_TOLERANCE_SEC) {
    rtcUtcOffset = offset;
    rtcUtcKnown = true;
  }
}

void utcFromServer(uint32_t utc) {
  int64_t offset = (int64_t)utc - (int64_t)clockNow();
  if (!rtcUtcKnown || offset - rtcUtcOffset > CLOCK_TOLERANCE_SEC) {
    rtcUtcOffset = offset;
    rtcUtcKnown = true;
  }
}

void clockReset() {
  rtcUtcOffset = 0;
  rtcUtcKnown = false;
}
