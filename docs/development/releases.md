# Release e pipeline

## Integrazione continua

`.github/workflows/ci.yml` gira a ogni push e pull request: backend (tipi, test su TimescaleDB
con soglia di copertura, `npm audit` delle dipendenze di produzione), app (testi allineati a
`tool/strings.py`, analisi, test con copertura ≥ 98%) e firmware (compilazione della variante
predefinita e completa, test unitari e test incrociato del protocollo con g++). Le action sono
fissate per commit.

`.github/workflows/docs.yml` pubblica questa documentazione su GitHub Pages a ogni push su
`main` che la modifica (e la controlla nelle pull request).

`renovate.json` (app [Renovate](https://github.com/apps/renovate) da installare sul
repository) propone il lunedì gli aggiornamenti di npm, pub, immagini Docker e action, **solo
per versioni pubblicate da almeno 14 giorni**, con versioni esatte.

## Pubblicare una release

1. Aggiorna la versione dove serve (note di rilascio, eventuali migrazioni).
2. Su GitHub: **Releases → Draft a new release**, tag `vX.Y.Z` (es. `v2.5.0`), titolo e note,
   **Publish release**.
3. `.github/workflows/release.yml` ripete i controlli della CI, poi in parallelo:
    - compila le immagini del firmware (`firmware-lilygo-sim.bin`, `firmware-lilygo-wifi-sim.bin`)
      con la versione del tag e le allega alla release;
    - compila l'APK firmato `car-tracking-X.Y.Z.apk` (`versionCode` = `X×10000 + Y×100 + Z`)
      e lo allega alla release;
    - costruisce l'immagine del backend per amd64 e arm64 e la pubblica su
      `ghcr.io/<proprietario>/<repository>` con i tag `X.Y.Z`, `X.Y`, `X` e `latest`.
4. I server con `GITHUB_REPO` vedono la nuova release entro 6 ore (firmware e app); quelli con
   Watchtower aggiornano il backend la notte successiva.

Il nome del repository non è mai scritto nei file: la pipeline usa `github.repository`, il
backend la variabile `GITHUB_REPO`. Rinominare il repository non richiede modifiche al codice.

## Segreti e variabili

Da **Settings → Secrets and variables → Actions** del repository.

### Firma dell'APK (obbligatori)

Senza questi segreti la pipeline si ferma: un APK firmato con la chiave di debug non potrebbe
essere aggiornato da quelli successivi.

| Segreto | Valore |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | Il file del keystore (`.jks`) codificato in base64, su una sola riga |
| `ANDROID_KEYSTORE_PASSWORD` | La password del keystore (`-storepass`) |
| `ANDROID_KEY_ALIAS` | L'alias della chiave dentro il keystore (`-alias`) |
| `ANDROID_KEY_PASSWORD` | La password della chiave (`-keypass`; con i keystore PKCS12 è la stessa del keystore) |

Creare il keystore **una sola volta** e conservarlo (con le password) in un gestore di password:
se si perde, l'app installata non si aggiorna più e le passkey dell'app vanno registrate di
nuovo.

Passo per passo:

1. Serve `keytool`, incluso in ogni JDK (es. Temurin 21) e in Android Studio
   (`<Android Studio>/jbr/bin/keytool`).
2. Esegui il comando `keytool -genkeypair` qui sotto. Chiede:
    - la **password del keystore** (almeno 6 caratteri, es. `openssl rand -hex 16`): è
      `ANDROID_KEYSTORE_PASSWORD`;
    - nome, organizzazione, città, paese: finiscono nel certificato, valori qualsiasi;
    - il keystore creato è PKCS12, quindi la **password della chiave** è la stessa del
      keystore: `ANDROID_KEY_PASSWORD` = `ANDROID_KEYSTORE_PASSWORD`.
3. L'alias scelto con `-alias` (qui `car-tracking`) è `ANDROID_KEY_ALIAS`.
4. Codifica il file in base64 su una sola riga: è `ANDROID_KEYSTORE_BASE64`.
5. Su GitHub, **Settings → Secrets and variables → Actions → New repository secret**, crea i
   quattro segreti con i nomi esatti della tabella.
6. Leggi l'impronta SHA-256 e mettila in `ANDROID_CERT_SHA256` nel `.env` del server.

```sh
# Keystore (validità 30 anni); chiede le password e il nome da mettere nel certificato
keytool -genkeypair -v -keystore car-tracking-release.jks -alias car-tracking \
  -keyalg RSA -keysize 4096 -validity 10950

# Valore di ANDROID_KEYSTORE_BASE64
base64 -w0 car-tracking-release.jks            # Linux
base64 -i car-tracking-release.jks | tr -d '\n' # macOS
[Convert]::ToBase64String([IO.File]::ReadAllBytes("car-tracking-release.jks"))  # PowerShell

# Impronta per ANDROID_CERT_SHA256 del backend (passkey nell'app): la riga "SHA256:"
keytool -list -v -keystore car-tracking-release.jks -alias car-tracking
```

Se usi già un keystore per compilare l'APK a mano (`android/key.properties`), metti quello:
`storeFile` → `ANDROID_KEYSTORE_BASE64`, `storePassword` → `ANDROID_KEYSTORE_PASSWORD`,
`keyAlias` → `ANDROID_KEY_ALIAS`, `keyPassword` → `ANDROID_KEY_PASSWORD`. Così gli APK
installati finora si aggiornano senza disinstallare.

### Firmware e immagine su GHCR

Nessun segreto: il firmware usa la libreria LilyGO pubblica fissata per commit, l'immagine del
backend va su GHCR con il `GITHUB_TOKEN` automatico del workflow (permesso `packages: write`).
Dopo la prima release rendi pubblico il pacchetto (vedi [Aggiornamenti](../server/updates.md)).

### Backend (non sono segreti di GitHub)

`GITHUB_REPO` e, facoltativo, `GITHUB_TOKEN` vanno nel `.env` del **server**: il backend legge
le release pubbliche senza token (60 richieste l'ora per IP, ne usa 4 al giorno). Un token
*fine-grained* senza permessi (sola lettura dei repository pubblici) alza il limite; serve con
permesso *Contents: read* solo se il repository è privato.

## GitHub Pages

Una volta: **Settings → Pages → Build and deployment → Source: GitHub Actions**. Il sito è
pubblico anche con GitHub Free se il repository è pubblico (con un repository privato Pages
richiede un piano a pagamento).
