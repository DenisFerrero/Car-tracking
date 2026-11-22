# App Android e web

La stessa app Flutter gira su Android (9+) e nel browser, servita dal backend. Al primo avvio
l'app Android chiede l'indirizzo del server (o lo riceve già con `--dart-define=API_URL`).

## Installazione

- **Dalle release**: ogni release su GitHub ha in allegato `car-tracking-<versione>.apk`,
  firmato sempre con la stessa chiave.
- **Store alternativi**: [Obtainium](https://github.com/ImranR98/Obtainium) (si aggiunge l'URL
  del repository) o GitHub Store; vedi sotto i requisiti.
- **Compilata in proprio**:

```sh
cd app
flutter build apk --release --dart-define=API_URL=https://tracking.mydomain.com   # opzionale
```

Requisiti e note:

- **Android 9+** (minSdk 28, richiesto dal Credential Manager delle passkey).
- **Firma**: crea un keystore e `android/key.properties` (`storeFile`, `storePassword`,
  `keyAlias`, `keyPassword`; escluso da git). Senza, la release è firmata con la chiave di
  debug.
- **Passkey nell'app**: imposta `ANDROID_CERT_SHA256` con l'impronta SHA-256 del certificato
  di firma (`keytool -list -v -keystore <keystore>`). Il backend pubblica
  `/.well-known/assetlinks.json` e accetta l'origine `android:apk-key-hash:` dell'app.
- **Notifiche push**, opzionali: crea un progetto Firebase con un'app Android
  `com.cartracking.app`, salva il service account in `secrets/fcm.json`, imposta
  `FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json` e compila l'app con
  `--dart-define=FIREBASE_API_KEY=...`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
  `FIREBASE_PROJECT_ID` (non serve `google-services.json`). Senza Firebase le notifiche
  arrivano solo con l'app aperta.
- **Web**: `app/web/passkeys_bundle.js` è il `bundle.js` del pacchetto `passkeys_web` 2.11.0,
  compilato dal suo sorgente (`javascript/`, `npm ci && rollup -c`): va ricompilato se si
  aggiorna il pacchetto.

## Aggiornamenti

L'APK allegato alle release (compilato con `--dart-define=APP_VERSION`) viene letto dal
backend insieme al firmware (`GITHUB_REPO`). L'app Android confronta la sua versione con
l'ultima release e mostra un banner con *Scarica* (una volta per versione, *Più tardi* lo
nasconde). L'app web è servita dal backend ed è sempre aggiornata con il server.

## Store alternativi

Obtainium, GitHub Store e simili leggono le release di un repository **pubblico** e propongono
l'APK allegato. Bastano la pipeline di release e:

- tag `vX.Y.Z` con `versionCode` crescente (la pipeline lo ricava dal tag:
  `MAJOR×10000 + MINOR×100 + PATCH`);
- una release non *draft* e non *pre-release* con un solo `.apk` fra gli allegati (i `.bin`
  del firmware vengono ignorati);
- **sempre la stessa chiave di firma** (segreti `ANDROID_KEYSTORE_*`): con una chiave diversa
  Android rifiuta l'aggiornamento e le passkey dell'app smettono di funzionare.

GitHub Store elenca da solo i repository pubblici con un APK nell'ultima release: descrizione
e *topic* del repository aiutano a trovarlo.

## Aspetto

Tema "strada notturna": barre color petrolio, azioni e indicatori ambra come la segnaletica,
angoli squadrati, carattere [Barlow](https://github.com/jpt/barlow) (SIL Open Font License)
incluso nell'app. La mappa è desaturata con una tinta petrolio, di notte (tema scuro) diventa
scura con le strade chiare; i dispositivi sono rombi del loro colore, come cartelli stradali.
