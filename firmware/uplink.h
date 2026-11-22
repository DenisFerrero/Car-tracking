#ifndef UPLINK_H
#define UPLINK_H

#include "connections.h"
#include "modem.h"
#include "protocol.h"

// Device identity and encrypted frames on the WebSocket of the server. Every connection
// starts with a HELLO (it authenticates the tracker), the server answers with the ACK and
// then sends the pending commands; TELEMETRY and COMMAND_RESULT only after the ACK.

// Applies one command of the server, frameTimestamp is the server time of the frame
typedef proto::CommandResult (*CommandHandler)(const proto::Command &command, uint32_t frameTimestamp);

// Loads key, device id and nonce counter (NVS). False with an invalid key or IMEI.
bool uplinkInit(const ModemInfo &info);

// To call after every connection: sends the HELLO
void uplinkOnConnected(uint32_t timestamp);
// Waits for the ACK of this connection up to timeoutMs
bool uplinkWaitAck(unsigned long timeoutMs);
// Connected and acknowledged: frames can be sent
bool uplinkReady();

// Commands are received after the ACK (kept by the server until answered)
void uplinkSetCommandHandler(CommandHandler handler);

// Replaces serverLoop(): frames received, keepalive and commands
void uplinkLoop();

// Keeps the loop running for timeoutMs, gives time to the pending commands to arrive
void uplinkPoll(unsigned long timeoutMs);

// Frames of the server, passed to serverBegin()
void uplinkOnFrame(const uint8_t *data, size_t length);

// Sends points in as few frames as possible, returns how many were sent
size_t uplinkSend(const proto::Point *points, size_t count);

// Longest JSON of the extra data (one frame)
const size_t EXTRA_MAX_SIZE = 400;
// Extra data of the vehicle: a JSON object, e.g. read from another board on a serial line
// (the reading is not part of this firmware). The server stores it as it comes, new fields
// need no change here. Sent with the time of this call as soon as the connection is ready;
// at most EXTRA_QUEUE readings wait in RAM (the oldest is dropped, lost on deep sleep).
// False when the text is empty or too long.
bool uplinkQueueExtra(const char *json);

#endif
