// Copy of firmware/owner_code.cpp, keep them aligned
#include "owner_code.h"
#include <string.h>

namespace owner {

namespace {

const uint32_t K[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

uint32_t rotr(uint32_t x, int n) {
  return (x >> n) | (x << (32 - n));
}

struct Sha256 {
  uint32_t state[8];
  uint8_t block[64];
  size_t blockLength;
  uint64_t totalLength;

  Sha256() : blockLength(0), totalLength(0) {
    const uint32_t init[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(state, init, sizeof(state));
  }

  void compress() {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
      w[i] = (uint32_t)block[4 * i] << 24 | (uint32_t)block[4 * i + 1] << 16 |
             (uint32_t)block[4 * i + 2] << 8 | (uint32_t)block[4 * i + 3];
    }
    for (int i = 16; i < 64; i++) {
      uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];
    for (int i = 0; i < 64; i++) {
      uint32_t t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
      uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }

  void update(const uint8_t *data, size_t length) {
    totalLength += length;
    while (length > 0) {
      size_t chunk = 64 - blockLength;
      if (chunk > length) chunk = length;
      memcpy(block + blockLength, data, chunk);
      blockLength += chunk;
      data += chunk;
      length -= chunk;
      if (blockLength == 64) {
        compress();
        blockLength = 0;
      }
    }
  }

  void finish(uint8_t out[32]) {
    uint64_t bits = totalLength * 8;
    uint8_t pad = 0x80;
    update(&pad, 1);
    uint8_t zero = 0;
    while (blockLength != 56) update(&zero, 1);
    uint8_t length[8];
    for (int i = 0; i < 8; i++) length[i] = (uint8_t)(bits >> (56 - 8 * i));
    update(length, 8);
    for (int i = 0; i < 8; i++) {
      out[4 * i] = (uint8_t)(state[i] >> 24);
      out[4 * i + 1] = (uint8_t)(state[i] >> 16);
      out[4 * i + 2] = (uint8_t)(state[i] >> 8);
      out[4 * i + 3] = (uint8_t)state[i];
    }
  }
};

const size_t CODE_SIZE = 8;

void computeCode(const uint8_t key[KEY_SIZE], uint8_t tagId, uint32_t counter, uint8_t code[CODE_SIZE]) {
  uint8_t message[9] = {'C', 'T', 'B', '1', tagId, (uint8_t)counter, (uint8_t)(counter >> 8),
                        (uint8_t)(counter >> 16), (uint8_t)(counter >> 24)};
  uint8_t mac[32];
  hmacSha256(key, KEY_SIZE, message, sizeof(message), mac);
  memcpy(code, mac, CODE_SIZE);
}

}  // namespace

void sha256(const uint8_t *data, size_t length, uint8_t out[32]) {
  Sha256 hash;
  hash.update(data, length);
  hash.finish(out);
}

void hmacSha256(const uint8_t *key, size_t keyLength, const uint8_t *data, size_t length, uint8_t out[32]) {
  uint8_t block[64] = {0};
  if (keyLength > 64) {
    sha256(key, keyLength, block);
  } else {
    memcpy(block, key, keyLength);
  }

  uint8_t pad[64];
  for (int i = 0; i < 64; i++) pad[i] = block[i] ^ 0x36;
  Sha256 inner;
  inner.update(pad, 64);
  inner.update(data, length);
  uint8_t innerHash[32];
  inner.finish(innerHash);

  for (int i = 0; i < 64; i++) pad[i] = block[i] ^ 0x5c;
  Sha256 outer;
  outer.update(pad, 64);
  outer.update(innerHash, 32);
  outer.finish(out);
}

void buildAdvertising(uint8_t out[ADVERTISING_SIZE], const uint8_t key[KEY_SIZE], uint8_t tagId, uint32_t counter) {
  out[0] = (uint8_t)(COMPANY_ID & 0xFF);
  out[1] = (uint8_t)(COMPANY_ID >> 8);
  out[2] = 'C';
  out[3] = 'T';
  out[4] = VERSION;
  out[5] = tagId;
  for (int i = 0; i < 4; i++) out[6 + i] = (uint8_t)(counter >> (8 * i));
  computeCode(key, tagId, counter, out + 10);
}

bool parseAdvertising(const uint8_t *data, size_t length, const uint8_t key[KEY_SIZE], uint8_t *tagId,
                      uint32_t *counter) {
  if (length != ADVERTISING_SIZE) return false;
  if (data[0] != (uint8_t)(COMPANY_ID & 0xFF) || data[1] != (uint8_t)(COMPANY_ID >> 8)) return false;
  if (data[2] != 'C' || data[3] != 'T' || data[4] != VERSION) return false;

  uint32_t value = 0;
  for (int i = 0; i < 4; i++) value |= (uint32_t)data[6 + i] << (8 * i);

  uint8_t expected[CODE_SIZE];
  computeCode(key, data[5], value, expected);
  // Constant time comparison
  uint8_t difference = 0;
  for (size_t i = 0; i < CODE_SIZE; i++) difference |= expected[i] ^ data[10 + i];
  if (difference != 0) return false;

  *tagId = data[5];
  *counter = value;
  return true;
}

}  // namespace owner
