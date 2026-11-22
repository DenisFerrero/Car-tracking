#ifndef CHACHA_POLY_H
#define CHACHA_POLY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t r[5];
    uint32_t h[5];
    uint32_t pad[4];
    uint8_t buffer[16];
    size_t buffer_len;
} poly1305_ctx;

void poly1305_init(poly1305_ctx *ctx, const uint8_t key[32]);
void poly1305_blocks(poly1305_ctx *ctx, const uint8_t *m, size_t bytes, uint32_t final_byte);
void poly1305_finish(poly1305_ctx *ctx, uint8_t mac[16]);

void chacha20_xor(uint8_t *out, const uint8_t *in, size_t len, const uint8_t key[32], const uint8_t nonce[12], uint32_t counter);
void rfc8439_keygen(uint8_t poly_key[32], const uint8_t key[32], const uint8_t nonce[12]);

void chacha20_poly1305_encrypt(
    uint8_t *ciphertext,
    uint8_t tag[16],
    const uint8_t *plaintext,
    size_t plaintext_len,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
);

int chacha20_poly1305_decrypt(
    uint8_t *plaintext,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t tag[16],
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t key[32],
    const uint8_t nonce[12]
);

// Same as chacha20_poly1305_decrypt, with a tag truncated to tag_len bytes (1-16)
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
);

#ifdef __cplusplus
}
#endif

#endif // CHACHA_POLY_H
