// Official images of the GitHub releases (.github/workflows/release.yml), included through
// CT_CONFIG_OVERRIDE by the variant files of this folder. Public binaries: no credential
// and no server inside. A tracker gets them only after a first installation of a build
// with its own secrets.h (DEVICE_KEY, SERVER_HOST, APN / WiFi): key and network settings
// stay in its NVS (settings.cpp). The other settings are the ones of configurations.h.
#undef SERVER_HOST
#define SERVER_HOST ""
#undef AUTO_UPDATE
#define AUTO_UPDATE 1
// Real board: LilyGO TinyGSM library (TLS on the modem)
#undef COMPILING_WITH_STANDARD_TINYGSM
