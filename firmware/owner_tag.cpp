#include "owner_tag.h"
#include "configurations.h"

#if OWNER_TAG

#include <BLEDevice.h>
#include <BLEScan.h>
#include <Preferences.h>
#include "clock.h"
#include "owner_code.h"
#include "protocol.h"

#if OWNER_TAG == 2
// Last counter accepted: an advertising recorded near the owner can't be replayed later.
// The same counter is accepted again only for a short time (the beacon keeps it for
// COUNTER_PERIOD_SEC, the owner may open and close the car twice).
RTC_DATA_ATTR static uint32_t rtcLastCounter = 0;
RTC_DATA_ATTR static time_t rtcLastCounterClock = 0;
#define SAME_COUNTER_SEC (2 * owner::COUNTER_PERIOD_SEC)

static bool acceptCounter(uint32_t counter) {
  Preferences prefs;
  prefs.begin("tracker", false);
  uint32_t last = prefs.getUInt("tagctr", 0);
  if (rtcLastCounter > last) last = rtcLastCounter;

  bool accepted = counter > last ||
                  (counter == last && rtcLastCounter == counter && clockNow() - rtcLastCounterClock < SAME_COUNTER_SEC);
  if (accepted && counter != last) {
    prefs.putUInt("tagctr", counter);
    rtcLastCounter = counter;
    rtcLastCounterClock = clockNow();
  }
  prefs.end();
  return accepted;
}
#endif

static bool isOwnerTag(BLEAdvertisedDevice &device) {
#if OWNER_TAG == 1
  return device.getAddress().toString().equalsIgnoreCase(OWNER_TAG_ADDRESS);
#else
  if (!device.haveManufacturerData()) return false;
  String data = device.getManufacturerData();

  uint8_t key[owner::KEY_SIZE];
  if (!proto::parseHexKey(OWNER_TAG_KEY, key)) return false;

  uint8_t tagId = 0;
  uint32_t counter = 0;
  if (!owner::parseAdvertising((const uint8_t *)data.c_str(), data.length(), key, &tagId, &counter)) return false;
  if (!acceptCounter(counter)) {
    Serial.printf("[OWNER] Tag %u with an old counter %u: replayed?\n", (unsigned)tagId, (unsigned)counter);
    return false;
  }
  Serial.printf("[OWNER] Tag %u, counter %u\n", (unsigned)tagId, (unsigned)counter);
  return true;
#endif
}

bool ownerTagNearby(unsigned long scanMs) {
  BLEDevice::init("");
  BLEScan *scan = BLEDevice::getScan();
  scan->setActiveScan(false);  // Advertising only: no scan requests, less power
  scan->setInterval(100);
  scan->setWindow(99);

  // Short scans, stops at the first match
  bool found = false;
  unsigned long start = millis();
  while (!found && millis() - start < scanMs) {
    BLEScanResults *results = scan->start(1, false);
    for (int i = 0; results && i < results->getCount() && !found; i++) {
      BLEAdvertisedDevice device = results->getDevice(i);
      found = isOwnerTag(device);
    }
    scan->clearResults();
  }

  BLEDevice::deinit(false);
  return found;
}

#endif
