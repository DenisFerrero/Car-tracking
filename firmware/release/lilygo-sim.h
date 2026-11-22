// LilyGO T-Call A7670, SIM only. To receive these images a personal build must report
// the same variant: #define FIRMWARE_VARIANT "lilygo-sim" in configurations.h
#include "common.h"
#undef FIRMWARE_VARIANT
#define FIRMWARE_VARIANT "lilygo-sim"
#undef CONNECTION_MODE
#define CONNECTION_MODE 2
