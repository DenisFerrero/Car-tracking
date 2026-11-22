#ifndef SETTINGS_H
#define SETTINGS_H

#include <Arduino.h>

// Network settings of secrets.h / configurations.h, kept in the NVS like the device key.
// A build with SERVER_HOST "" (the public images of the releases, built without any
// credential) uses the saved ones: the first installation of a tracker is a build with
// its real settings, then the official images update it without knowing them.
struct NetworkSettings {
  String wifiSsid;
  String wifiPassword;
  String simApn;
  String simUser;
  String simPassword;
  String simPin;
  String serverHost;
};

// Loaded at the first call. serverHost is empty when nothing was ever saved.
const NetworkSettings &networkSettings();

#endif
