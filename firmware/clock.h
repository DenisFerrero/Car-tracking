#ifndef CLOCK_H
#define CLOCK_H

// Two clocks:
//  - clockNow(): RTC seconds, monotonic and counting in deep sleep, used for the schedules
//  - utcNow(): unix time, known after a GNSS fix or a frame of the server (authenticated)
// The UTC is kept as an offset from the RTC clock: setting it never moves the schedules.

#include <stdint.h>
#include <time.h>

time_t clockNow();

// Unix seconds, 0 while unknown
uint32_t utcNow();
bool utcKnown();

// GNSS time is trusted in both directions; server frames only move the clock forward
// (an old frame replayed can't move it back)
void utcFromGnss(uint32_t utc);
void utcFromServer(uint32_t utc);

// Clears the UTC at power on (the RTC memory is not initialized after a power loss)
void clockReset();

#endif
