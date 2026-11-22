#ifndef SPOOL_H
#define SPOOL_H

#include <stddef.h>
#include "protocol.h"

// Offline queue on LittleFS: raw 20 bytes points, oldest first. Points are encrypted
// only when sent, so a reconnection sends them in a few big frames.

bool spoolInit();
bool spoolAppend(const proto::Point *points, size_t count);
size_t spoolCount();
// Copies up to max points from the head (oldest), without removing them
size_t spoolPeek(proto::Point *points, size_t max);
// Removes count points from the head, after they have been sent
void spoolConsume(size_t count);

#endif
