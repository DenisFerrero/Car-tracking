#ifndef OTA_H
#define OTA_H

#include "protocol.h"

// Firmware update over the air, on the connection of the server. The FW_OFFER (size and
// SHA-256, authenticated with the device key) arrives after the ACK; otaRun() downloads
// the image in windows into the other OTA partition and activates it only if the SHA-256
// matches, then reboots. The new firmware is confirmed at its first ACK: if it never
// reaches the server, the bootloader goes back to the previous one (when the rollback is
// enabled in the bootloader).

typedef bool (*ConnectFunction)();

// Frames of the server, from uplinkOnFrame()
void otaOffer(const proto::FirmwareOffer &offer);
void otaOnChunk(const uint8_t *data, size_t length);

// An offer is waiting for otaRun()
bool otaPending();

// Downloads and installs the offered image within budgetMs, reconnecting with connect when
// the connection drops (the server offers the image again, the download resumes). Reboots
// on success, otherwise it reports the failure to the server and returns.
void otaRun(unsigned long budgetMs, ConnectFunction connect);

// First ACK of this firmware: it works, no rollback
void otaConfirm();

#endif
