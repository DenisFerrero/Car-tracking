// Copy this file to secrets.h (ignored by git) and fill in the values

// Number of this keychain (0-255): more keychains share the key, the tracker logs which one
#define TAG_ID 1

// Same value of OWNER_TAG_KEY in firmware/secrets.h, e.g. openssl rand -hex 32
#define TAG_KEY "0000000000000000000000000000000000000000000000000000000000000000"
