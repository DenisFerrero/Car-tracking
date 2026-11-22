#include "chacha_poly.h"
#include <string.h>

#define ROTL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

#define QUARTERROUND(x, a, b, c, d) \
    x[a] += x[b]; x[d] ^= x[a]; x[d] = ROTL32(x[d], 16); \
    x[c] += x[d]; x[b] ^= x[c]; x[b] = ROTL32(x[b], 12); \
    x[a] += x[b]; x[d] ^= x[a]; x[d] = ROTL32(x[d], 8);  \
    x[c] += x[d]; x[b] ^= x[c]; x[b] = ROTL32(x[b], 7);

static void chacha20_block(uint32_t out[16], const uint32_t in[16]) {
    int i;
    uint32_t x[16];
    for (i = 0; i < 16; i++) {
        x[i] = in[i];
    }
    for (i = 0; i < 10; i++) {
        // Column rounds
        QUARTERROUND(x, 0, 4, 8, 12)
        QUARTERROUND(x, 1, 5, 9, 13)
        QUARTERROUND(x, 2, 6, 10, 14)
        QUARTERROUND(x, 3, 7, 11, 15)
        // Diagonal rounds
        QUARTERROUND(x, 0, 5, 10, 15)
        QUARTERROUND(x, 1, 6, 11, 12)
        QUARTERROUND(x, 2, 7, 8, 13)
        QUARTERROUND(x, 3, 4, 9, 14)
    }
    for (i = 0; i < 16; i++) {
        out[i] = x[i] + in[i];
    }
}

static void chacha20_init(uint32_t state[16], const uint8_t key[32], const uint8_t nonce[12], uint32_t counter) {
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;
    
    int i;
    for (i = 0; i < 8; i++) {
        state[4 + i] = ((uint32_t)key[i*4]) |
                       ((uint32_t)key[i*4 + 1] << 8) |
                       ((uint32_t)key[i*4 + 2] << 16) |
                       ((uint32_t)key[i*4 + 3] << 24);
    }
    
    state[12] = counter;
    
    for (i = 0; i < 3; i++) {
        state[13 + i] = ((uint32_t)nonce[i*4]) |
                        ((uint32_t)nonce[i*4 + 1] << 8) |
                        ((uint32_t)nonce[i*4 + 2] << 16) |
                        ((uint32_t)nonce[i*4 + 3] << 24);
    }
}

void chacha20_xor(uint8_t *out, const uint8_t *in, size_t len, const uint8_t key[32], const uint8_t nonce[12], uint32_t counter) {
    uint32_t state[16];
    uint32_t block[16];
    uint8_t keystream[64];
    size_t i;
    
    chacha20_init(state, key, nonce, counter);
    
    while (len > 0) {
        chacha20_block(block, state);
        
        for (i = 0; i < 16; i++) {
            keystream[i*4]     = (block[i]      ) & 0xFF;
            keystream[i*4 + 1] = (block[i] >> 8 ) & 0xFF;
            keystream[i*4 + 2] = (block[i] >> 16) & 0xFF;
            keystream[i*4 + 3] = (block[i] >> 24) & 0xFF;
        }
        
        size_t chunk = len < 64 ? len : 64;
        for (i = 0; i < chunk; i++) {
            out[i] = in[i] ^ keystream[i];
        }
        
        out += chunk;
        in += chunk;
        len -= chunk;
        state[12]++; // Increment counter
    }
}

void rfc8439_keygen(uint8_t poly_key[32], const uint8_t key[32], const uint8_t nonce[12]) {
    uint8_t block0[64];
    memset(block0, 0, sizeof(block0));
    chacha20_xor(block0, block0, 64, key, nonce, 0);
    memcpy(poly_key, block0, 32);
}

static uint32_t U8TO32(const uint8_t *p) {
    return (((uint32_t)p[0]      ) |
            ((uint32_t)p[1] << 8 ) |
            ((uint32_t)p[2] << 16) |
            ((uint32_t)p[3] << 24));
}

void poly1305_init(poly1305_ctx *ctx, const uint8_t key[32]) {
    uint32_t t0 = U8TO32(&key[0]);
    uint32_t t1 = U8TO32(&key[4]);
    uint32_t t2 = U8TO32(&key[8]);
    uint32_t t3 = U8TO32(&key[12]);
    
    ctx->r[0] = t0 & 0x3ffffff;
    ctx->r[1] = ((t0 >> 26) | (t1 << 6)) & 0x3ffff03;
    ctx->r[2] = ((t1 >> 20) | (t2 << 12)) & 0x3ffc0ff;
    ctx->r[3] = ((t2 >> 14) | (t3 << 18)) & 0x3f03fff;
    ctx->r[4] = (t3 >> 8) & 0x00fffff;
    
    ctx->h[0] = 0;
    ctx->h[1] = 0;
    ctx->h[2] = 0;
    ctx->h[3] = 0;
    ctx->h[4] = 0;
    
    ctx->pad[0] = U8TO32(&key[16]);
    ctx->pad[1] = U8TO32(&key[20]);
    ctx->pad[2] = U8TO32(&key[24]);
    ctx->pad[3] = U8TO32(&key[28]);
    
    ctx->buffer_len = 0;
}

void poly1305_blocks(poly1305_ctx *ctx, const uint8_t *m, size_t bytes, uint32_t final_byte) {
    uint32_t r0 = ctx->r[0];
    uint32_t r1 = ctx->r[1];
    uint32_t r2 = ctx->r[2];
    uint32_t r3 = ctx->r[3];
    uint32_t r4 = ctx->r[4];
    
    uint32_t s1 = r1 * 5;
    uint32_t s2 = r2 * 5;
    uint32_t s3 = r3 * 5;
    uint32_t s4 = r4 * 5;
    
    uint32_t h0 = ctx->h[0];
    uint32_t h1 = ctx->h[1];
    uint32_t h2 = ctx->h[2];
    uint32_t h3 = ctx->h[3];
    uint32_t h4 = ctx->h[4];
    
    while (bytes >= 16) {
        uint32_t t0 = U8TO32(&m[0]);
        uint32_t t1 = U8TO32(&m[4]);
        uint32_t t2 = U8TO32(&m[8]);
        uint32_t t3 = U8TO32(&m[12]);
        
        h0 += t0 & 0x3ffffff;
        h1 += ((t0 >> 26) | (t1 << 6)) & 0x3ffffff;
        h2 += ((t1 >> 20) | (t2 << 12)) & 0x3ffffff;
        h3 += ((t2 >> 14) | (t3 << 18)) & 0x3ffffff;
        h4 += (t3 >> 8) | (final_byte << 24);
        
        uint64_t d0 = (uint64_t)h0 * r0 + (uint64_t)h1 * s4 + (uint64_t)h2 * s3 + (uint64_t)h3 * s2 + (uint64_t)h4 * s1;
        uint64_t d1 = (uint64_t)h0 * r1 + (uint64_t)h1 * r0 + (uint64_t)h2 * s4 + (uint64_t)h3 * s3 + (uint64_t)h4 * s2;
        uint64_t d2 = (uint64_t)h0 * r2 + (uint64_t)h1 * r1 + (uint64_t)h2 * r0 + (uint64_t)h3 * s4 + (uint64_t)h4 * s3;
        uint64_t d3 = (uint64_t)h0 * r3 + (uint64_t)h1 * r2 + (uint64_t)h2 * r1 + (uint64_t)h3 * r0 + (uint64_t)h4 * s4;
        uint64_t d4 = (uint64_t)h0 * r4 + (uint64_t)h1 * r3 + (uint64_t)h2 * r2 + (uint64_t)h3 * r1 + (uint64_t)h4 * r0;
        
        uint32_t c;
        c = (uint32_t)(d0 >> 26); h0 = (uint32_t)d0 & 0x3ffffff; d1 += c;
        c = (uint32_t)(d1 >> 26); h1 = (uint32_t)d1 & 0x3ffffff; d2 += c;
        c = (uint32_t)(d2 >> 26); h2 = (uint32_t)d2 & 0x3ffffff; d3 += c;
        c = (uint32_t)(d3 >> 26); h3 = (uint32_t)d3 & 0x3ffffff; d4 += c;
        c = (uint32_t)(d4 >> 26); h4 = (uint32_t)d4 & 0x3ffffff;
        h0 += c * 5;
        
        c = h0 >> 26; h0 &= 0x3ffffff; h1 += c;
        
        m += 16;
        bytes -= 16;
    }
    
    ctx->h[0] = h0;
    ctx->h[1] = h1;
    ctx->h[2] = h2;
    ctx->h[3] = h3;
    ctx->h[4] = h4;
}

void poly1305_finish(poly1305_ctx *ctx, uint8_t mac[16]) {
    uint32_t h0 = ctx->h[0];
    uint32_t h1 = ctx->h[1];
    uint32_t h2 = ctx->h[2];
    uint32_t h3 = ctx->h[3];
    uint32_t h4 = ctx->h[4];
    
    uint32_t c;
    c = h1 >> 26; h1 &= 0x3ffffff; h2 += c;
    c = h2 >> 26; h2 &= 0x3ffffff; h3 += c;
    c = h3 >> 26; h3 &= 0x3ffffff; h4 += c;
    c = h4 >> 26; h4 &= 0x3ffffff;
    h0 += c * 5;
    c = h0 >> 26; h0 &= 0x3ffffff; h1 += c;
    
    uint32_t g0 = h0 + 5;
    uint32_t g1 = h1 + (g0 >> 26); g0 &= 0x3ffffff;
    uint32_t g2 = h2 + (g1 >> 26); g1 &= 0x3ffffff;
    uint32_t g3 = h3 + (g2 >> 26); g2 &= 0x3ffffff;
    uint32_t g4 = h4 + (g3 >> 26) - (1 << 26); g3 &= 0x3ffffff;
    
    uint32_t mask = (g4 >> 31) - 1;
    uint32_t nmask = ~mask;
    
    h0 = (h0 & nmask) | (g0 & mask);
    h1 = (h1 & nmask) | (g1 & mask);
    h2 = (h2 & nmask) | (g2 & mask);
    h3 = (h3 & nmask) | (g3 & mask);
    h4 = (h4 & nmask) | (g4 & mask);
    
    // Repack the 26 bit limbs in 32 bit words: the shifts must truncate to 32 bits,
    // otherwise the high bits are added twice through the carries below
    uint32_t w0 = h0 | (h1 << 26);
    uint32_t w1 = (h1 >> 6) | (h2 << 20);
    uint32_t w2 = (h2 >> 12) | (h3 << 14);
    uint32_t w3 = (h3 >> 18) | (h4 << 8);

    uint64_t f0 = (uint64_t)w0 + ctx->pad[0];
    uint64_t f1 = (uint64_t)w1 + ctx->pad[1] + (f0 >> 32);
    uint64_t f2 = (uint64_t)w2 + ctx->pad[2] + (f1 >> 32);
    uint64_t f3 = (uint64_t)w3 + ctx->pad[3] + (f2 >> 32);
    
    mac[0]  = (f0      ) & 0xff; mac[1]  = (f0 >> 8 ) & 0xff; mac[2]  = (f0 >> 16) & 0xff; mac[3]  = (f0 >> 24) & 0xff;
    mac[4]  = (f1      ) & 0xff; mac[5]  = (f1 >> 8 ) & 0xff; mac[6]  = (f1 >> 16) & 0xff; mac[7]  = (f1 >> 24) & 0xff;
    mac[8]  = (f2      ) & 0xff; mac[9]  = (f2 >> 8 ) & 0xff; mac[10] = (f2 >> 16) & 0xff; mac[11] = (f2 >> 24) & 0xff;
    mac[12] = (f3      ) & 0xff; mac[13] = (f3 >> 8 ) & 0xff; mac[14] = (f3 >> 16) & 0xff; mac[15] = (f3 >> 24) & 0xff;
}

// Poly1305 over a buffer padded with zeros to a multiple of 16 bytes (RFC 8439 2.8)
static void poly1305_padded(poly1305_ctx *pctx, const uint8_t *data, size_t len) {
    size_t full_blocks = len / 16;
    if (full_blocks > 0) {
        poly1305_blocks(pctx, data, full_blocks * 16, 1);
    }
    size_t rem = len % 16;
    if (rem > 0) {
        uint8_t pad_block[16];
        memset(pad_block, 0, 16);
        memcpy(pad_block, data + full_blocks * 16, rem);
        poly1305_blocks(pctx, pad_block, 16, 1);
    }
}

static void store64_le(uint8_t *out, uint64_t value) {
    for (int i = 0; i < 8; i++) {
        out[i] = (uint8_t)(value >> (8 * i));
    }
}

// Tag of AAD + ciphertext. Lengths are widened to 64 bits: size_t is 32 bits on the ESP32
static void aead_tag(
    uint8_t tag[16],
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
) {
    uint8_t otk[32];
    rfc8439_keygen(otk, key, nonce);

    poly1305_ctx pctx;
    poly1305_init(&pctx, otk);

    poly1305_padded(&pctx, aad, aad_len);
    poly1305_padded(&pctx, ciphertext, ciphertext_len);

    uint8_t len_block[16];
    store64_le(len_block, (uint64_t)aad_len);
    store64_le(len_block + 8, (uint64_t)ciphertext_len);

    poly1305_blocks(&pctx, len_block, 16, 1);
    poly1305_finish(&pctx, tag);
}

void chacha20_poly1305_encrypt(
    uint8_t *ciphertext,
    uint8_t tag[16],
    const uint8_t *plaintext,
    size_t plaintext_len,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
) {
    // In place encryption is allowed (ciphertext == plaintext)
    chacha20_xor(ciphertext, plaintext, plaintext_len, key, nonce, 1);
    aead_tag(tag, ciphertext, plaintext_len, aad, aad_len, key, nonce);
}

int chacha20_poly1305_decrypt(
    uint8_t *plaintext,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t tag[16],
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
) {
    return chacha20_poly1305_decrypt_truncated(plaintext, ciphertext, ciphertext_len, tag, 16, aad, aad_len, key, nonce);
}

int chacha20_poly1305_decrypt_truncated(
    uint8_t *plaintext,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t *tag,
    size_t tag_len,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
) {
    if (tag_len == 0 || tag_len > 16) {
        return -1;
    }

    uint8_t computed_tag[16];
    aead_tag(computed_tag, ciphertext, ciphertext_len, aad, aad_len, key, nonce);

    // Constant time comparison
    uint8_t diff = 0;
    for (size_t i = 0; i < tag_len; i++) {
        diff |= computed_tag[i] ^ tag[i];
    }

    if (diff != 0) {
        return -1; // Auth failure
    }

    chacha20_xor(plaintext, ciphertext, ciphertext_len, key, nonce, 1);
    return 0; // Success
}
