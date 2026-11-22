#ifndef OWNER_TAG_H
#define OWNER_TAG_H

// Owner presence (OWNER_TAG in configurations.h): a BLE scan at the motion alarm, the
// alarm is ignored when the owner's keychain is nearby.
//  - OWNER_TAG 1: any BLE tag with a fixed address (OWNER_TAG_ADDRESS). Easy but the
//    address can be cloned. Samsung SmartTag, AirTag & co. rotate it: not usable.
//  - OWNER_TAG 2: the beacon of hardware/owner-beacon with a rolling code (owner_code.h)

#include <Arduino.h>

// Scans for scanMs, true when the owner's tag is nearby
bool ownerTagNearby(unsigned long scanMs);

#endif
