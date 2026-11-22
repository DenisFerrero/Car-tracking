# Android and web app

The same Flutter app runs on Android (9+) and in the browser, served by the backend. At the
first start the Android app asks for the address of the server (or gets it already with
`--dart-define=API_URL`).

## Installation

- **From the releases**: every GitHub release has `car-tracking-<version>.apk` attached,
  always signed with the same key.
- **Alternative stores**: [Obtainium](https://github.com/ImranR98/Obtainium) (add the URL of
  the repository) or GitHub Store; see the requirements below.
- **Built by yourself**:

```sh
cd app
flutter build apk --release --dart-define=API_URL=https://tracking.mydomain.com   # optional
```

Requirements and notes:

- **Android 9+** (minSdk 28, needed by the Credential Manager of the passkeys).
- **Signing**: create a keystore and `android/key.properties` (`storeFile`, `storePassword`,
  `keyAlias`, `keyPassword`; excluded from git). Without it the release is signed with the
  debug key.
- **Passkeys in the app**: set `ANDROID_CERT_SHA256` to the SHA-256 fingerprint of the signing
  certificate (`keytool -list -v -keystore <keystore>`). The backend publishes
  `/.well-known/assetlinks.json` and accepts the `android:apk-key-hash:` origin of the app.
- **Push notifications**, optional: create a Firebase project with an Android app
  `com.cartracking.app`, save the service account in `secrets/fcm.json`, set
  `FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json` and build the app with
  `--dart-define=FIREBASE_API_KEY=...`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
  `FIREBASE_PROJECT_ID` (no `google-services.json` needed). Without Firebase notifications
  arrive only while the app is open.
- **Web**: `app/web/passkeys_bundle.js` is the `bundle.js` of the `passkeys_web` 2.11.0
  package, built from its source (`javascript/`, `npm ci && rollup -c`): rebuild it when the
  package is upgraded.

## Updates

The APK attached to the releases (built with `--dart-define=APP_VERSION`) is read by the
backend together with the firmware (`GITHUB_REPO`). The Android app compares its version with
the latest release and shows a banner with *Download* (once per version, *Later* hides it).
The web app is served by the backend and is always in step with the server.

## Alternative stores

Obtainium, GitHub Store and similar read the releases of a **public** repository and offer the
attached APK. The release pipeline is enough, plus:

- `vX.Y.Z` tags with a growing `versionCode` (the pipeline derives it from the tag:
  `MAJOR×10000 + MINOR×100 + PATCH`);
- a release that is neither *draft* nor *pre-release* with a single `.apk` among the assets
  (the firmware `.bin` files are ignored);
- **always the same signing key** (`ANDROID_KEYSTORE_*` secrets): with another key Android
  refuses the update and the passkeys of the app stop working.

GitHub Store lists on its own the public repositories with an APK in the latest release: the
description and the *topics* of the repository help finding it.

## Look

"Night road" theme: petrol bars, amber actions and indicators like road signs, squared
corners, [Barlow](https://github.com/jpt/barlow) font (SIL Open Font License) bundled with the
app. The map is desaturated with a petrol tint; at night (dark theme) it turns dark with light
roads; devices are diamonds of their color, like road signs.
