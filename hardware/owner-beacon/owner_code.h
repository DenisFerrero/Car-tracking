#ifndef OWNER_CODE_H
#define OWNER_CODE_H

// Rolling code of the owner beacon (OWNER_TAG 2). Manufacturer data of the advertising,
// 18 bytes:
//   u16 LE  company id     0xFFFF (reserved for tests, the beacon is not a product)
//   2       magic          'C' 'T'
//   u8      version        1
//   u8      tag id         more beacons share a key, the id distinguishes them
//   u32 LE  counter        +1 every 30 seconds, never repeated (persisted in blocks)
//   8       code           HMAC-SHA256(key, "CTB1" | tag id | counter LE), first 8 bytes
// Copy of firmware/owner_code.h (an Arduino sketch can't include files outside its folder):
// keep them aligned. Plain C++, tested on the PC (firmware/test).

#include <stddef.h>
#include <stdint.h>

namespace owner {

const size_t KEY_SIZE = 32;
const size_t ADVERTISING_SIZE = 18;
const uint16_t COMPANY_ID = 0xFFFF;
const uint8_t VERSION = 1;
const uint32_t COUNTER_PERIOD_SEC = 30;

void sha256(const uint8_t *data, size_t length, uint8_t out[32]);
void hmacSha256(const uint8_t *key, size_t keyLength, const uint8_t *data, size_t length, uint8_t out[32]);

// Writes the manufacturer data of the advertising
void buildAdvertising(uint8_t out[ADVERTISING_SIZE], const uint8_t key[KEY_SIZE], uint8_t tagId, uint32_t counter);

// Verifies the manufacturer data (company id included), returns the counter
bool parseAdvertising(const uint8_t *data, size_t length, const uint8_t key[KEY_SIZE], uint8_t *tagId,
                      uint32_t *counter);

}  // namespace owner

#endif
