# Releases and pipeline

## Continuous integration

`.github/workflows/ci.yml` runs at every push and pull request: backend (types, tests on
TimescaleDB with a coverage threshold, `npm audit` of the production dependencies), app
(strings in step with `tool/strings.py`, analysis, tests with coverage ≥ 98%) and firmware
(build of the default and full variants, unit tests and cross test of the protocol with g++).
Actions are pinned by commit.

`.github/workflows/docs.yml` publishes this documentation on GitHub Pages at every push to
`main` that changes it (and checks it in pull requests).

`renovate.json` (the [Renovate](https://github.com/apps/renovate) app, to be installed on the
repository) proposes on Mondays the updates of npm, pub, Docker images and actions, **only for
versions published at least 14 days earlier**, with exact versions.

## Publishing a release

1. Update the version where needed (release notes, migrations if any).
2. On GitHub: **Releases → Draft a new release**, tag `vX.Y.Z` (e.g. `v2.5.0`), title and
   notes, **Publish release**.
3. `.github/workflows/release.yml` repeats the CI checks, then in parallel:
    - builds the firmware images (`firmware-lilygo-sim.bin`, `firmware-lilygo-wifi-sim.bin`)
      with the version of the tag and attaches them to the release;
    - builds the signed APK `car-tracking-X.Y.Z.apk` (`versionCode` = `X×10000 + Y×100 + Z`)
      and attaches it to the release;
    - builds the backend image for amd64 and arm64 and publishes it on
      `ghcr.io/<owner>/<repository>` with the tags `X.Y.Z`, `X.Y`, `X` and `latest`.
4. Servers with `GITHUB_REPO` see the new release within 6 hours (firmware and app); those
   with Watchtower update the backend the next night.

The name of the repository is never written in the files: the pipeline uses
`github.repository`, the backend the `GITHUB_REPO` variable. Renaming the repository needs no
code change.

## Secrets and variables

From **Settings → Secrets and variables → Actions** of the repository.

### APK signing (required)

Without these secrets the pipeline stops: an APK signed with the debug key couldn't be updated
by the following ones.

| Secret | Value |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | The keystore file (`.jks`) base64-encoded, on a single line |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password (`-storepass`) |
| `ANDROID_KEY_ALIAS` | The alias of the key inside the keystore (`-alias`) |
| `ANDROID_KEY_PASSWORD` | The key password (`-keypass`; with PKCS12 keystores it's the same as the keystore's) |

Create the keystore **only once** and keep it (with the passwords) in a password manager: if
it's lost, the installed app no longer updates and the passkeys of the app must be registered
again.

Step by step:

1. You need `keytool`, included in every JDK (e.g. Temurin 21) and in Android Studio
   (`<Android Studio>/jbr/bin/keytool`).
2. Run the `keytool -genkeypair` command below. It asks for:
    - the **keystore password** (at least 6 characters, e.g. `openssl rand -hex 16`): it's
      `ANDROID_KEYSTORE_PASSWORD`;
    - name, organization, city, country: they go in the certificate, any value;
    - the keystore created is PKCS12, so the **key password** is the same as the keystore's:
      `ANDROID_KEY_PASSWORD` = `ANDROID_KEYSTORE_PASSWORD`.
3. The alias chosen with `-alias` (here `car-tracking`) is `ANDROID_KEY_ALIAS`.
4. Encode the file in base64 on a single line: it's `ANDROID_KEYSTORE_BASE64`.
5. On GitHub, **Settings → Secrets and variables → Actions → New repository secret**, create
   the four secrets with the exact names of the table.
6. Read the SHA-256 fingerprint and put it in `ANDROID_CERT_SHA256` in the `.env` of the
   server.

```sh
# Keystore (valid 30 years); asks for the passwords and the name to put in the certificate
keytool -genkeypair -v -keystore car-tracking-release.jks -alias car-tracking \
  -keyalg RSA -keysize 4096 -validity 10950

# Value of ANDROID_KEYSTORE_BASE64
base64 -w0 car-tracking-release.jks            # Linux
base64 -i car-tracking-release.jks | tr -d '\n' # macOS
[Convert]::ToBase64String([IO.File]::ReadAllBytes("car-tracking-release.jks"))  # PowerShell

# Fingerprint for ANDROID_CERT_SHA256 of the backend (passkeys in the app): the "SHA256:" line
keytool -list -v -keystore car-tracking-release.jks -alias car-tracking
```

If you already use a keystore to build the APK by hand (`android/key.properties`), use that
one: `storeFile` → `ANDROID_KEYSTORE_BASE64`, `storePassword` → `ANDROID_KEYSTORE_PASSWORD`,
`keyAlias` → `ANDROID_KEY_ALIAS`, `keyPassword` → `ANDROID_KEY_PASSWORD`. This way the APKs
installed so far update without uninstalling.

### Firmware and image on GHCR

No secrets: the firmware uses the public LilyGO library pinned by commit, the backend image
goes to GHCR with the automatic `GITHUB_TOKEN` of the workflow (`packages: write`
permission). After the first release make the package public (see
[Updates](../server/updates.md)).

### Backend (not GitHub secrets)

`GITHUB_REPO` and, optionally, `GITHUB_TOKEN` go in the `.env` of the **server**: the backend
reads public releases without a token (60 requests an hour per IP, it uses 4 a day). A
*fine-grained* token with no permissions (read-only access to public repositories) raises the
limit; it needs *Contents: read* only if the repository is private.

## GitHub Pages

Once: **Settings → Pages → Build and deployment → Source: GitHub Actions**. The site is public
with GitHub Free too if the repository is public (with a private repository Pages needs a
paid plan).
