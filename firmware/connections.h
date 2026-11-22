#ifndef CONNECTIONS_H
#define CONNECTIONS_H

// Network of the tracker: WiFi and/or the cellular data of the modem (modem.h) according
// to CONNECTION_MODE, and on top of them a WebSocket to the server (TLS with SERVER_TLS)
// carrying one frame of the protocol per binary message.

#include <Arduino.h>

void printVariables();

// WiFi and/or cellular according to CONNECTION_MODE
bool startNetwork();
bool networkConnected();

// Called by serverLoop() for every frame received
typedef void (*FrameHandler)(const uint8_t *frame, size_t length);

// WebSocket to the server, a single attempt: the caller handles the back-off
void serverBegin(FrameHandler onFrame);
bool serverConnect();
bool serverConnected();
// Reads the frames received and keeps the connection alive (pings every KEEP_ALIVE_SEC)
void serverLoop();
bool serverSend(const uint8_t *frame, size_t length);
// Closes the WebSocket, the network stays up
void serverDisconnect();

// Signal strength of the active network in dBm, 0 when unknown
int signalDbm();

// Disconnects and powers down the radios
void prepareForSleep();

#endif
