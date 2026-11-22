// Modem driver of the SIMCom A76xx family (A7670E/SA/G, A7608), see modem.h

#include "configurations.h"
#include "settings.h"

#if BOARD_MODEM_FAMILY == MODEM_FAMILY_SIMCOM_A76XX

#ifdef COMPILING_WITH_STANDARD_TINYGSM
  // CLI builds without the LilyGO library: close enough to compile, no TLS on the modem
  #define TINY_GSM_MODEM_SIM7600
#else
  // LilyGO TinyGSM: A76xx with the TLS client of the modem
  #define TINY_GSM_MODEM_A76XXSSL
#endif
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include "modem.h"
#include "nmea.h"
#if SERVER_TLS && SERVER_TLS_VERIFY
  #include "certificates.h"
#endif

#define KNOTS_TO_KMH 1.852f
// Name of the CA bundle in the modem file system
#define CA_FILE "ct_ca.pem"
// AT+CNMP: 38 = LTE only, 2 = automatic
#define NETWORK_MODE_LTE 38
#define NETWORK_MODE_AUTO 2

static HardwareSerial modemSerial(BOARD_MODEM_UART);
static TinyGsm modem(modemSerial);

#if SERVER_TLS && !defined(COMPILING_WITH_STANDARD_TINYGSM)
static TinyGsmClientSecure client(modem, 0);
#else
static TinyGsmClient client(modem, 0);
#endif

static void pulsePowerKey() {
  digitalWrite(BOARD_MODEM_PWRKEY_PIN, LOW);
  delay(100);
  digitalWrite(BOARD_MODEM_PWRKEY_PIN, HIGH);
  delay(1000);  // Ton = 1000ms, min 500ms, max 2000ms
  digitalWrite(BOARD_MODEM_PWRKEY_PIN, LOW);
}

// Plain AT query, the LilyGO TinyGSM doesn't expose manufacturer/model/revision
static String atQuery(const char *command, const char *prefix = nullptr) {
  modem.sendAT(command);
  String data;
  if (modem.waitResponse(2000L, data) != 1) return "";
  data.replace("OK", "");
  if (prefix) data.replace(prefix, "");
  data.trim();
  return data;
}

// 4G only: the 2G networks are being switched off, and the GSM bursts (2 A) disappear
static void configureNetworkMode() {
  modem.sendAT("+CNMP=", MODEM_LTE_ONLY ? NETWORK_MODE_LTE : NETWORK_MODE_AUTO);
  if (modem.waitResponse(5000L) != 1) Serial.println("[MODEM] Network mode not set");
}

static void configureTls() {
#if SERVER_TLS && SERVER_TLS_VERIFY && !defined(COMPILING_WITH_STANDARD_TINYGSM)
  // Written at every boot: a local transfer on the UART, no data on the SIM
  if (modem.downloadCertificate(CA_FILE, SERVER_CA_BUNDLE) && client.setCertificate(CA_FILE)) {
    Serial.println("[MODEM] TLS root certificates loaded");
  } else {
    Serial.println("[MODEM] TLS root certificates NOT loaded, connections will fail");
  }
#endif
}

bool modemPowerOn() {
#if BOARD_LED_PIN >= 0
  pinMode(BOARD_LED_PIN, OUTPUT);
  digitalWrite(BOARD_LED_PIN, HIGH);
#endif

  // Reset the modem
  pinMode(BOARD_MODEM_RESET_PIN, OUTPUT);
  digitalWrite(BOARD_MODEM_RESET_PIN, !BOARD_MODEM_RESET_LEVEL);
  delay(100);
  digitalWrite(BOARD_MODEM_RESET_PIN, BOARD_MODEM_RESET_LEVEL);
  delay(2600);
  digitalWrite(BOARD_MODEM_RESET_PIN, !BOARD_MODEM_RESET_LEVEL);

  pinMode(BOARD_MODEM_PWRKEY_PIN, OUTPUT);
  pulsePowerKey();

  modemSerial.begin(BOARD_MODEM_BAUD, SERIAL_8N1, BOARD_MODEM_RX_PIN, BOARD_MODEM_TX_PIN);

  Serial.print("Starting modem");
  for (int attempt = 1; attempt <= 30; attempt++) {
    if (modem.testAT(1000)) {
      Serial.println(" OK");
      configureNetworkMode();
      configureTls();
      return true;
    }
    Serial.print(".");
    // The modem may have missed the power key pulse
    if (attempt % 10 == 0) pulsePowerKey();
  }

  Serial.println(" FAILED");
  return false;
}

void modemPowerOff() {
  modem.gprsDisconnect();
  modem.poweroff();
#if BOARD_LED_PIN >= 0
  digitalWrite(BOARD_LED_PIN, LOW);
#endif
}

ModemInfo modemReadInfo() {
  ModemInfo info;
  info.imei = modem.getIMEI();
  info.imei.trim();
  info.manufacturer = atQuery("+CGMI");
  info.model = atQuery("+CGMM");
  info.revision = atQuery("+CGMR", "+CGMR:");
  return info;
}

bool modemAttach() {
#if CONNECTION_MODE == 2 || CONNECTION_MODE == 3
  if (modem.isGprsConnected()) return true;

  const NetworkSettings &net = networkSettings();
  if (net.simPin.length() > 0 && modem.getSimStatus() != 3) {
    modem.simUnlock(net.simPin.c_str());
  }

  Serial.print("Waiting for the cellular network...");
  if (!modem.waitForNetwork(60000L)) {
    Serial.println(" FAILED");
    return false;
  }
  Serial.println(" OK");

  Serial.printf("Connecting to APN %s...", net.simApn.c_str());
  if (!modem.gprsConnect(net.simApn.c_str(), net.simUser.c_str(), net.simPassword.c_str())) {
    Serial.println(" FAILED");
    return false;
  }
  Serial.println(" OK");
  return true;
#else
  return false;
#endif
}

bool modemAttached() {
  return modem.isGprsConnected();
}

void modemDetach() {
  modem.gprsDisconnect();
}

Client &modemClient() {
  return client;
}

int modemSignalDbm() {
  // CSQ: 0 = -113 dBm or less, 31 = -51 dBm or more, 99 = unknown
  int csq = modem.getSignalQuality();
  if (csq >= 0 && csq <= 31) return -113 + 2 * csq;
  return 0;
}

bool modemCellInfo(CellInfo &cell) {
  modem.sendAT("+CPSI?");
  String data;
  if (modem.waitResponse(2000L, data) != 1) return false;
  return parseCpsi(data.c_str(), cell);
}

bool modemGnssEnable() {
#if BOARD_MODEM_HAS_GNSS
  Serial.print("Enabling GNSS");
  for (int attempt = 0; attempt < 10; attempt++) {
#ifdef COMPILING_WITH_STANDARD_TINYGSM
    bool enabled = modem.enableGPS();
#else
    bool enabled = modem.enableGPS(BOARD_MODEM_GNSS_ENABLE_PIN, BOARD_MODEM_GNSS_ENABLE_LEVEL);
#endif
    if (enabled) {
#ifndef COMPILING_WITH_STANDARD_TINYGSM
      modem.setGPSMode(3);  // GPS + GLONASS + Galileo
#endif
      Serial.println(" OK");
      return true;
    }
    Serial.print(".");
    delay(1000);
  }
  Serial.println(" FAILED");
#endif
  return false;
}

bool modemGnssRead(GnssReading &reading) {
#if BOARD_MODEM_HAS_GNSS
  float lat = 0, lon = 0, speed = 0, alt = 0, accuracy = 0;
  int vsat = 0, usat = 0, year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;

#ifdef COMPILING_WITH_STANDARD_TINYGSM
  bool fix = modem.getGPS(&lat, &lon, &speed, &alt, &vsat, &usat, &accuracy,
                          &year, &month, &day, &hour, &minute, &second);
#else
  uint8_t fixMode = 0;
  bool fix = modem.getGPS(&fixMode, &lat, &lon, &speed, &alt, &vsat, &usat, &accuracy,
                          &year, &month, &day, &hour, &minute, &second);
#endif

  if (!fix || year < 2024 || (lat == 0 && lon == 0)) return false;

  reading.timestamp = nmeaUnixTime(year, month, day, hour, minute, second);
  reading.lat = (int32_t)lround((double)lat * 1e5);
  reading.lon = (int32_t)lround((double)lon * 1e5);
  reading.speedKmh = speed * KNOTS_TO_KMH;
  reading.altitude = (int16_t)lroundf(alt);
  reading.hasAltitude = true;
  int satellites = usat > 0 ? usat : vsat;
  reading.satellites = (uint8_t)(satellites > 255 ? 255 : (satellites < 0 ? 0 : satellites));
  return true;
#else
  (void)reading;
  return false;
#endif
}

#endif
