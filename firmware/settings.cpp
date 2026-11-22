#include "settings.h"
#include "configurations.h"
#include <Preferences.h>

#ifndef WIFI_SSID
  #define WIFI_SSID ""
#endif
#ifndef WIFI_PASSWORD
  #define WIFI_PASSWORD ""
#endif
#ifndef SIM_APN
  #define SIM_APN ""
#endif
#ifndef SIM_USER
  #define SIM_USER ""
#endif
#ifndef SIM_PASSWORD
  #define SIM_PASSWORD ""
#endif
#ifndef SIM_PIN
  #define SIM_PIN ""
#endif

static NetworkSettings current;
static bool loaded = false;

static const char *const KEYS[] = {"ssid", "wifipw", "apn", "simuser", "simpw", "simpin", "host"};

const NetworkSettings &networkSettings() {
  if (loaded) return current;
  loaded = true;

  String *list[] = {&current.wifiSsid, &current.wifiPassword, &current.simApn, &current.simUser,
                    &current.simPassword, &current.simPin, &current.serverHost};
  const char *compiled[] = {WIFI_SSID, WIFI_PASSWORD, SIM_APN, SIM_USER, SIM_PASSWORD, SIM_PIN, SERVER_HOST};
  Preferences prefs;
  prefs.begin("network", false);
  bool configured = strlen(SERVER_HOST) > 0;
  for (size_t i = 0; i < 7; i++) {
    if (configured) {
      *list[i] = compiled[i];
      if (prefs.getString(KEYS[i], "") != *list[i]) prefs.putString(KEYS[i], *list[i]);
    } else {
      *list[i] = prefs.getString(KEYS[i], "");
    }
  }
  prefs.end();
  if (!configured) {
    Serial.println(current.serverHost.length() ? "[SETTINGS] Network settings of the first installation"
                                               : "[SETTINGS] No network settings: flash once a build with SERVER_HOST");
  }
  return current;
}
