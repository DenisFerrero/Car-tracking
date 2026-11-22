// Owner keychain for the tracker (OWNER_TAG 2 in firmware/configurations.h): a BLE
// beacon that advertises a rolling code every second. The tracker ignores the motion
// alarms while it receives a valid code with a counter never seen before.
//
// Board: Seeed XIAO nRF52840 (core "Seeed nRF52 Boards", not the mbed one), Adafruit
// Bluefruit library included in the core. See hardware/README.md, "Portachiavi".

#include <bluefruit.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
#include "owner_code.h"
// TAG_ID and TAG_KEY, not versioned: copy secrets.example.h to secrets.h
#include "secrets.h"

using namespace Adafruit_LittleFS_Namespace;

#define COUNTER_FILE "/counter"
// The counter is reserved in blocks (one flash write a day): after a reset the unused part
// is skipped, a counter is never advertised twice
#define COUNTER_BLOCK 2880
// Advertising interval in units of 0.625 ms: 1600 = 1 second
#define ADVERTISING_INTERVAL 1600
// dBm: 0 reaches the car from a few meters, -8 limits it to the door
#define TX_POWER 0

static uint8_t key[owner::KEY_SIZE];
static uint32_t counterBase = 0;
static uint32_t reservedUntil = 0;
static uint32_t advertised = 0xFFFFFFFF;

static bool parseKey(const char *hex) {
  if (strlen(hex) != 2 * owner::KEY_SIZE) return false;
  for (size_t i = 0; i < owner::KEY_SIZE; i++) {
    char byte[3] = {hex[2 * i], hex[2 * i + 1], 0};
    char *end;
    key[i] = (uint8_t)strtoul(byte, &end, 16);
    if (*end) return false;
  }
  return true;
}

static uint32_t readStoredCounter() {
  File file(InternalFS);
  uint32_t value = 0;
  if (file.open(COUNTER_FILE, FILE_O_READ)) {
    file.read(&value, sizeof(value));
    file.close();
  }
  return value;
}

static void storeCounter(uint32_t value) {
  InternalFS.remove(COUNTER_FILE);
  File file(InternalFS);
  if (file.open(COUNTER_FILE, FILE_O_WRITE)) {
    file.write((const uint8_t *)&value, sizeof(value));
    file.close();
  }
}

static uint32_t currentCounter() {
  uint32_t counter = counterBase + millis() / (owner::COUNTER_PERIOD_SEC * 1000UL);
  if (counter >= reservedUntil) {
    reservedUntil = counter + COUNTER_BLOCK;
    storeCounter(reservedUntil);
  }
  return counter;
}

static void advertise(uint32_t counter) {
  uint8_t data[owner::ADVERTISING_SIZE];
  owner::buildAdvertising(data, key, TAG_ID, counter);

  Bluefruit.Advertising.stop();
  Bluefruit.Advertising.clearData();
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAG_BR_EDR_NOT_SUPPORTED);
  Bluefruit.Advertising.addManufacturerData(data, sizeof(data));
  Bluefruit.Advertising.setType(BLE_GAP_ADV_TYPE_NONCONNECTABLE_NONSCANNABLE_UNDIRECTED);
  Bluefruit.Advertising.setInterval(ADVERTISING_INTERVAL, ADVERTISING_INTERVAL);
  Bluefruit.Advertising.restartOnDisconnect(false);
  Bluefruit.Advertising.start(0);
  advertised = counter;
}

void setup() {
  // LEDs off: they would drain the battery
  pinMode(LED_RED, OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_BLUE, OUTPUT);
  digitalWrite(LED_RED, HIGH);
  digitalWrite(LED_GREEN, HIGH);
  digitalWrite(LED_BLUE, HIGH);

  if (!parseKey(TAG_KEY)) {
    // Invalid key: red LED on, nothing advertised
    digitalWrite(LED_RED, LOW);
    while (true) delay(60000);
  }

  InternalFS.begin();
  counterBase = readStoredCounter();
  reservedUntil = counterBase + COUNTER_BLOCK;
  storeCounter(reservedUntil);

  Bluefruit.begin();
  Bluefruit.setTxPower(TX_POWER);
  Bluefruit.autoConnLed(false);
  advertise(currentCounter());
}

void loop() {
  // delay() lets FreeRTOS put the CPU to sleep between the advertising events
  delay(1000);
  uint32_t counter = currentCounter();
  if (counter != advertised) advertise(counter);
}
