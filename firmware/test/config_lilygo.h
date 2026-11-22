// Build test with the LilyGO TinyGSM (modem TLS, A76xx GNSS API), included through
// CT_CONFIG_OVERRIDE: see docs/development/index.md, "Tests"
#undef COMPILING_WITH_STANDARD_TINYGSM
#undef CONNECTION_MODE
#define CONNECTION_MODE 2
#ifndef SIM_APN
  #define SIM_APN "test"
#endif
