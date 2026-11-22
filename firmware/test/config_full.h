// Build test with every optional feature enabled, included through CT_CONFIG_OVERRIDE:
// see README.md, "Compilazione"
#undef CONNECTION_MODE
#define CONNECTION_MODE 3
#ifndef SIM_APN
  #define SIM_APN "test"
#endif
#undef GNSS_SOURCE
#define GNSS_SOURCE GNSS_SOURCE_EXTERNAL
#undef GNSS_POWER_PIN
#define GNSS_POWER_PIN 23
#undef VEHICLE_VOLTAGE_SENSE
#define VEHICLE_VOLTAGE_SENSE 1
#undef POWER_GOOD_SENSE
#define POWER_GOOD_SENSE 1
#undef OWNER_TAG
#define OWNER_TAG 2
#ifndef OWNER_TAG_KEY
  #define OWNER_TAG_KEY "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
#endif
