#include "spool.h"
#include "configurations.h"
#include <Arduino.h>
#include <LittleFS.h>

using namespace proto;

#define SPOOL_FILE "/spool.bin"
#define SPOOL_HEAD_FILE "/spool.idx"
#define SPOOL_TMP_FILE "/spool.tmp"
// 192 KB: about 4900 points, many hours of driving with the adaptive sampling. Reduced
// on the small file systems (Minimal SPIFFS partition scheme, needed by OWNER_TAG): the
// queue gets at most 40% of the partition, dropOldest() needs room for a copy of half.
#ifndef SPOOL_MAX_BYTES
  #define SPOOL_MAX_BYTES 196608
#endif

static const size_t RECORD = sizeof(Point);
// Stored with the head: a queue written by a firmware with a different Point is discarded
static const uint32_t SPOOL_MAGIC = 0x53500000UL | (uint32_t)RECORD;
static bool ready = false;
static size_t maxBytes = SPOOL_MAX_BYTES;
// Byte offset of the oldest point not sent yet
static uint32_t head = 0;

static size_t fileSize() {
  File file = LittleFS.open(SPOOL_FILE, FILE_READ);
  if (!file) return 0;
  size_t size = file.size();
  file.close();
  return size;
}

static void saveHead() {
  File file = LittleFS.open(SPOOL_HEAD_FILE, FILE_WRITE);
  if (!file) return;
  uint32_t index[2] = {SPOOL_MAGIC, head};
  file.write((const uint8_t *)index, sizeof(index));
  file.close();
}

static void clearSpool() {
  LittleFS.remove(SPOOL_FILE);
  LittleFS.remove(SPOOL_HEAD_FILE);
  head = 0;
}

// Keeps the newest half of the queue when it's full
static void dropOldest() {
  size_t size = fileSize();
  size_t pending = (size - head) / RECORD;
  uint32_t from = head + (pending / 2) * RECORD;

  File source = LittleFS.open(SPOOL_FILE, FILE_READ);
  File target = LittleFS.open(SPOOL_TMP_FILE, FILE_WRITE);
  if (source && target && source.seek(from)) {
    uint8_t buffer[RECORD * 16];
    size_t read;
    while ((read = source.read(buffer, sizeof(buffer))) > 0) target.write(buffer, read);
  }
  if (source) source.close();
  if (target) target.close();

  clearSpool();
  LittleFS.rename(SPOOL_TMP_FILE, SPOOL_FILE);
  Serial.printf("[SPOOL] Full, dropped the %u oldest points\n", (unsigned)(pending / 2));
}

bool spoolInit() {
  // Formats the partition when it can't be mounted
  ready = LittleFS.begin(true);
  if (!ready) {
    Serial.println("[SPOOL] LittleFS mount failed");
    return false;
  }

  size_t limit = LittleFS.totalBytes() * 2 / 5;
  maxBytes = (limit < SPOOL_MAX_BYTES ? limit : SPOOL_MAX_BYTES) / RECORD * RECORD;

  head = 0;
  bool valid = true;
  File file = LittleFS.open(SPOOL_HEAD_FILE, FILE_READ);
  if (file) {
    uint32_t index[2] = {0, 0};
    valid = file.read((uint8_t *)index, sizeof(index)) == sizeof(index) && index[0] == SPOOL_MAGIC;
    head = index[1];
    file.close();
  } else if (fileSize() > 0) {
    // Queue without index: written by an older firmware, or the index was lost
    valid = false;
  }

  // A head beyond the data or not aligned means a corrupted index
  size_t size = fileSize();
  if (!valid || head > size || head % RECORD != 0) {
    Serial.println("[SPOOL] Invalid index, queue discarded");
    clearSpool();
  }

  Serial.printf("[SPOOL] %u points waiting, room for %u\n", (unsigned)spoolCount(), (unsigned)(maxBytes / RECORD));
  return true;
}

bool spoolAppend(const Point *points, size_t count) {
  if (!ready || count == 0) return false;
  if (fileSize() + count * RECORD > maxBytes) dropOldest();

  File file = LittleFS.open(SPOOL_FILE, FILE_APPEND);
  if (!file) return false;
  size_t written = file.write((const uint8_t *)points, count * RECORD);
  file.close();
  // The index marks the queue as written by this firmware
  if (!LittleFS.exists(SPOOL_HEAD_FILE)) saveHead();

  Serial.printf("[SPOOL] Stored %u points offline\n", (unsigned)count);
  return written == count * RECORD;
}

size_t spoolCount() {
  if (!ready) return 0;
  size_t size = fileSize();
  return size > head ? (size - head) / RECORD : 0;
}

size_t spoolPeek(Point *points, size_t max) {
  if (!ready || max == 0) return 0;

  File file = LittleFS.open(SPOOL_FILE, FILE_READ);
  if (!file) return 0;
  size_t read = 0;
  if (file.seek(head)) read = file.read((uint8_t *)points, max * RECORD) / RECORD;
  file.close();
  return read;
}

void spoolConsume(size_t count) {
  if (!ready || count == 0) return;

  head += count * RECORD;
  if (head >= fileSize()) {
    // Everything sent: removing the files limits the flash writes
    clearSpool();
  } else {
    saveHead();
  }
}
