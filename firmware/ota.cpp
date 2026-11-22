#include "ota.h"
#include "connections.h"
#include "uplink.h"
#include <Arduino.h>
#include <Update.h>
#include <esp_ota_ops.h>
#include <mbedtls/sha256.h>

using namespace proto;

// Window requested at a time: the modem and TCP buffer it, the flash keeps up
static const uint32_t WINDOW = 16 * 1024;
// No chunk for this long: the window is requested again from the last byte received
static const unsigned long CHUNK_TIMEOUT_MS = 20000;

static bool offered = false;
static bool started = false;
static FirmwareOffer current;
static uint32_t received = 0;
static uint32_t windowEnd = 0;
static unsigned long lastChunk = 0;
static bool failed = false;
static FirmwareStatus failure = FW_WRITE_FAILED;
static mbedtls_sha256_context sha;

// The app is marked valid at the first ACK (otaConfirm), not at the boot
extern "C" bool verifyRollbackLater() {
  return true;
}

static void reset() {
  if (started) {
    Update.abort();
    mbedtls_sha256_free(&sha);
  }
  started = false;
  offered = false;
  received = 0;
  windowEnd = 0;
  failed = false;
}

static void sendResult(FirmwareStatus status) {
  uint8_t frame[2];
  size_t length = buildFirmwareResult(frame, status);
  if (uplinkReady()) serverSend(frame, length);
  Serial.printf("[OTA] Result %u\n", (unsigned)status);
}

static void requestWindow() {
  uint32_t length = current.size - received;
  if (length > WINDOW) length = WINDOW;
  uint8_t frame[7];
  size_t size = buildFirmwareRequest(frame, received, (uint16_t)length);
  if (serverSend(frame, size)) windowEnd = received + length;
  lastChunk = millis();
}

void otaOffer(const FirmwareOffer &offer) {
  if (started && offer.size == current.size && memcmp(offer.sha256, current.sha256, 32) == 0) {
    // Same image after a reconnection: resume from the bytes received
    windowEnd = received;
    return;
  }
  reset();
  current = offer;
  offered = true;
  Serial.printf("[OTA] Offer of firmware %s, %u bytes\n", current.version, (unsigned)current.size);
}

void otaOnChunk(const uint8_t *data, size_t length) {
  if (!started || failed || length < 5) return;
  uint32_t offset = 0;
  for (int i = 0; i < 4; i++) offset |= (uint32_t)data[1 + i] << (8 * i);
  const uint8_t *payload = data + 5;
  size_t size = length - 5;
  // A window requested again may repeat bytes already written: only the next ones count
  if (offset != received) return;
  if (received + size > current.size || Update.write((uint8_t *)payload, size) != size) {
    failed = true;
    failure = FW_WRITE_FAILED;
    return;
  }
  mbedtls_sha256_update(&sha, payload, size);
  received += size;
  lastChunk = millis();
}

bool otaPending() {
  return offered;
}

void otaRun(unsigned long budgetMs, ConnectFunction connect) {
  if (!offered) return;
  if (!started) {
    if (!Update.begin(current.size, U_FLASH)) {
      sendResult(FW_TOO_BIG);
      reset();
      return;
    }
    mbedtls_sha256_init(&sha);
    mbedtls_sha256_starts(&sha, 0);
    started = true;
  }

  unsigned long start = millis();
  windowEnd = received;
  while (!failed && received < current.size && millis() - start < budgetMs) {
    if (!uplinkReady()) {
      // The offer of the new connection sets windowEnd = received: the download resumes
      if (!connect()) delay(1000);
      continue;
    }
    if (received >= windowEnd || millis() - lastChunk > CHUNK_TIMEOUT_MS) requestWindow();
    uplinkLoop();
    delay(2);
  }

  if (failed || received < current.size) {
    sendResult(failed ? failure : FW_TIMEOUT);
    reset();
    return;
  }

  uint8_t digest[32];
  mbedtls_sha256_finish(&sha, digest);
  if (memcmp(digest, current.sha256, 32) != 0) {
    sendResult(FW_BAD_HASH);
    reset();
    return;
  }
  mbedtls_sha256_free(&sha);
  started = false;
  if (!Update.end(true)) {
    sendResult(FW_WRITE_FAILED);
    reset();
    return;
  }
  sendResult(FW_INSTALLED);
  Serial.printf("[OTA] Firmware %s installed, rebooting\n", current.version);
  uplinkPoll(1000);
  serverDisconnect();
  ESP.restart();
}

void otaConfirm() {
  static bool confirmed = false;
  if (confirmed) return;
  confirmed = true;
  esp_ota_mark_app_valid_cancel_rollback();
}
