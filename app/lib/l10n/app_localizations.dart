import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In it, this message translates to:
  /// **'Car Tracking'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get save;

  /// No description provided for @ok.
  ///
  /// In it, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get copy;

  /// No description provided for @done.
  ///
  /// In it, this message translates to:
  /// **'Fatto'**
  String get done;

  /// No description provided for @delete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get retry;

  /// No description provided for @continueLabel.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get continueLabel;

  /// No description provided for @back.
  ///
  /// In it, this message translates to:
  /// **'Indietro'**
  String get back;

  /// No description provided for @open.
  ///
  /// In it, this message translates to:
  /// **'Apri'**
  String get open;

  /// No description provided for @verify.
  ///
  /// In it, this message translates to:
  /// **'Verifica'**
  String get verify;

  /// No description provided for @noData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato nel periodo'**
  String get noData;

  /// No description provided for @operationCancelled.
  ///
  /// In it, this message translates to:
  /// **'Operazione annullata'**
  String get operationCancelled;

  /// No description provided for @you.
  ///
  /// In it, this message translates to:
  /// **'tu'**
  String get you;

  /// No description provided for @nameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get nameLabel;

  /// No description provided for @emailLabel.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @notAvailable.
  ///
  /// In it, this message translates to:
  /// **'n/d'**
  String get notAvailable;

  /// No description provided for @navMap.
  ///
  /// In it, this message translates to:
  /// **'Mappa'**
  String get navMap;

  /// No description provided for @navDevices.
  ///
  /// In it, this message translates to:
  /// **'Dispositivi'**
  String get navDevices;

  /// No description provided for @navNotifications.
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get navNotifications;

  /// No description provided for @navAccount.
  ///
  /// In it, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @never.
  ///
  /// In it, this message translates to:
  /// **'mai'**
  String get never;

  /// No description provided for @now.
  ///
  /// In it, this message translates to:
  /// **'adesso'**
  String get now;

  /// No description provided for @minutesAgo.
  ///
  /// In it, this message translates to:
  /// **'{n} min fa'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In it, this message translates to:
  /// **'{n} h fa'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In it, this message translates to:
  /// **'{n} g fa'**
  String daysAgo(int n);

  /// No description provided for @durationMinutes.
  ///
  /// In it, this message translates to:
  /// **'{m} min'**
  String durationMinutes(int m);

  /// No description provided for @durationHours.
  ///
  /// In it, this message translates to:
  /// **'{h} h {m} min'**
  String durationHours(int h, int m);

  /// No description provided for @qualityExcellent.
  ///
  /// In it, this message translates to:
  /// **'Ottimo'**
  String get qualityExcellent;

  /// No description provided for @qualityGood.
  ///
  /// In it, this message translates to:
  /// **'Buono'**
  String get qualityGood;

  /// No description provided for @qualityPoor.
  ///
  /// In it, this message translates to:
  /// **'Scarso'**
  String get qualityPoor;

  /// No description provided for @qualityBad.
  ///
  /// In it, this message translates to:
  /// **'Pessimo'**
  String get qualityBad;

  /// No description provided for @qualityWeak.
  ///
  /// In it, this message translates to:
  /// **'Debole'**
  String get qualityWeak;

  /// No description provided for @qualityNone.
  ///
  /// In it, this message translates to:
  /// **'Assente'**
  String get qualityNone;

  /// No description provided for @statusMoving.
  ///
  /// In it, this message translates to:
  /// **'In movimento'**
  String get statusMoving;

  /// No description provided for @statusEngineOff.
  ///
  /// In it, this message translates to:
  /// **'Motore spento'**
  String get statusEngineOff;

  /// No description provided for @statusParked.
  ///
  /// In it, this message translates to:
  /// **'Parcheggiata'**
  String get statusParked;

  /// No description provided for @statusAlarm.
  ///
  /// In it, this message translates to:
  /// **'Allarme'**
  String get statusAlarm;

  /// No description provided for @eventMotion.
  ///
  /// In it, this message translates to:
  /// **'Movimento'**
  String get eventMotion;

  /// No description provided for @eventTilt.
  ///
  /// In it, this message translates to:
  /// **'Inclinazione'**
  String get eventTilt;

  /// No description provided for @eventPowerLost.
  ///
  /// In it, this message translates to:
  /// **'Alimentazione scollegata'**
  String get eventPowerLost;

  /// No description provided for @eventLowBattery.
  ///
  /// In it, this message translates to:
  /// **'Batteria scarica'**
  String get eventLowBattery;

  /// No description provided for @kindMotion.
  ///
  /// In it, this message translates to:
  /// **'Movimento ad auto parcheggiata'**
  String get kindMotion;

  /// No description provided for @kindTilt.
  ///
  /// In it, this message translates to:
  /// **'Auto sollevata o inclinata'**
  String get kindTilt;

  /// No description provided for @kindPowerLost.
  ///
  /// In it, this message translates to:
  /// **'Alimentazione scollegata'**
  String get kindPowerLost;

  /// No description provided for @kindLowBattery.
  ///
  /// In it, this message translates to:
  /// **'Batteria dell\'auto scarica'**
  String get kindLowBattery;

  /// No description provided for @kindOffline.
  ///
  /// In it, this message translates to:
  /// **'Tracker non raggiungibile'**
  String get kindOffline;

  /// No description provided for @kindOnline.
  ///
  /// In it, this message translates to:
  /// **'Tracker di nuovo raggiungibile'**
  String get kindOnline;

  /// No description provided for @kindGeofenceEnter.
  ///
  /// In it, this message translates to:
  /// **'{device} è arrivato'**
  String kindGeofenceEnter(String device);

  /// No description provided for @kindGeofenceExit.
  ///
  /// In it, this message translates to:
  /// **'{device} è partito'**
  String kindGeofenceExit(String device);

  /// No description provided for @notificationBodyAt.
  ///
  /// In it, this message translates to:
  /// **'{device}, ore {time}'**
  String notificationBodyAt(String device, String time);

  /// No description provided for @notificationBodyEnter.
  ///
  /// In it, this message translates to:
  /// **'Entrato in {area}, ore {time}'**
  String notificationBodyEnter(String area, String time);

  /// No description provided for @notificationBodyExit.
  ///
  /// In it, this message translates to:
  /// **'Uscito da {area}, ore {time}'**
  String notificationBodyExit(String area, String time);

  /// No description provided for @notificationsTitle.
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get notificationsTitle;

  /// No description provided for @markAllRead.
  ///
  /// In it, this message translates to:
  /// **'Segna tutte come lette'**
  String get markAllRead;

  /// No description provided for @noNotifications.
  ///
  /// In it, this message translates to:
  /// **'Nessuna notifica'**
  String get noNotifications;

  /// No description provided for @errNetwork.
  ///
  /// In it, this message translates to:
  /// **'Server non raggiungibile'**
  String get errNetwork;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In it, this message translates to:
  /// **'Email o password errate'**
  String get errInvalidCredentials;

  /// No description provided for @errLocked.
  ///
  /// In it, this message translates to:
  /// **'Troppi tentativi: account bloccato temporaneamente'**
  String get errLocked;

  /// No description provided for @errInvalidCode.
  ///
  /// In it, this message translates to:
  /// **'Codice non valido'**
  String get errInvalidCode;

  /// No description provided for @errEnrollExpired.
  ///
  /// In it, this message translates to:
  /// **'Configurazione scaduta: ricomincia'**
  String get errEnrollExpired;

  /// No description provided for @errStepUp.
  ///
  /// In it, this message translates to:
  /// **'Serve il codice dell\'app di autenticazione'**
  String get errStepUp;

  /// No description provided for @errInvalidPassword.
  ///
  /// In it, this message translates to:
  /// **'Password attuale errata'**
  String get errInvalidPassword;

  /// No description provided for @errEmailTaken.
  ///
  /// In it, this message translates to:
  /// **'Esiste già un account con questa email'**
  String get errEmailTaken;

  /// No description provided for @errSelf.
  ///
  /// In it, this message translates to:
  /// **'Non puoi farlo sul tuo account'**
  String get errSelf;

  /// No description provided for @errInvalidPairing.
  ///
  /// In it, this message translates to:
  /// **'IMEI o codice di abbinamento errati'**
  String get errInvalidPairing;

  /// No description provided for @errAlreadyClaimed.
  ///
  /// In it, this message translates to:
  /// **'Il tracker appartiene a un altro account'**
  String get errAlreadyClaimed;

  /// No description provided for @errOwnerOnly.
  ///
  /// In it, this message translates to:
  /// **'Solo il proprietario può farlo'**
  String get errOwnerOnly;

  /// No description provided for @errShareSelf.
  ///
  /// In it, this message translates to:
  /// **'Il dispositivo è già tuo'**
  String get errShareSelf;

  /// No description provided for @errTooManyShares.
  ///
  /// In it, this message translates to:
  /// **'Troppe condivisioni per questo dispositivo'**
  String get errTooManyShares;

  /// No description provided for @errOwnerCannotLeave.
  ///
  /// In it, this message translates to:
  /// **'Il proprietario rimuove il tracker invece di lasciarlo'**
  String get errOwnerCannotLeave;

  /// No description provided for @errTooManyAreas.
  ///
  /// In it, this message translates to:
  /// **'Massimo 20 aree per dispositivo'**
  String get errTooManyAreas;

  /// No description provided for @errTooManyPhones.
  ///
  /// In it, this message translates to:
  /// **'Massimo 5 telefoni per account'**
  String get errTooManyPhones;

  /// No description provided for @errTooManyVehicles.
  ///
  /// In it, this message translates to:
  /// **'Massimo 10 veicoli per account'**
  String get errTooManyVehicles;

  /// No description provided for @errNotATracker.
  ///
  /// In it, this message translates to:
  /// **'Disponibile solo per i tracker'**
  String get errNotATracker;

  /// No description provided for @errFriendSelf.
  ///
  /// In it, this message translates to:
  /// **'È il tuo codice'**
  String get errFriendSelf;

  /// No description provided for @errTooManyFriends.
  ///
  /// In it, this message translates to:
  /// **'Massimo 200 amici'**
  String get errTooManyFriends;

  /// No description provided for @errLiveTooLong.
  ///
  /// In it, this message translates to:
  /// **'Il live dura al massimo 2 ore'**
  String get errLiveTooLong;

  /// No description provided for @errPeriodTooLong.
  ///
  /// In it, this message translates to:
  /// **'Periodo massimo 93 giorni'**
  String get errPeriodTooLong;

  /// No description provided for @errRateLimited.
  ///
  /// In it, this message translates to:
  /// **'Troppe richieste: riprova tra poco'**
  String get errRateLimited;

  /// No description provided for @errNotFound.
  ///
  /// In it, this message translates to:
  /// **'Non trovato'**
  String get errNotFound;

  /// No description provided for @errValidation.
  ///
  /// In it, this message translates to:
  /// **'Dati non validi'**
  String get errValidation;

  /// No description provided for @errInvalidPasskey.
  ///
  /// In it, this message translates to:
  /// **'Passkey non valida'**
  String get errInvalidPasskey;

  /// No description provided for @errChallengeExpired.
  ///
  /// In it, this message translates to:
  /// **'Richiesta scaduta: riprova'**
  String get errChallengeExpired;

  /// No description provided for @errUnauthorized.
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta: accedi di nuovo'**
  String get errUnauthorized;

  /// No description provided for @errForbidden.
  ///
  /// In it, this message translates to:
  /// **'Operazione non consentita'**
  String get errForbidden;

  /// No description provided for @errGeneric.
  ///
  /// In it, this message translates to:
  /// **'Errore {status}'**
  String errGeneric(int status);

  /// No description provided for @serverAddress.
  ///
  /// In it, this message translates to:
  /// **'Indirizzo della tua piattaforma'**
  String get serverAddress;

  /// No description provided for @serverLabel.
  ///
  /// In it, this message translates to:
  /// **'Server'**
  String get serverLabel;

  /// No description provided for @serverUnreachable.
  ///
  /// In it, this message translates to:
  /// **'Server non raggiungibile o non compatibile'**
  String get serverUnreachable;

  /// No description provided for @loginPasskey.
  ///
  /// In it, this message translates to:
  /// **'Accedi con passkey'**
  String get loginPasskey;

  /// No description provided for @loginPassword.
  ///
  /// In it, this message translates to:
  /// **'Accedi con password'**
  String get loginPassword;

  /// No description provided for @or.
  ///
  /// In it, this message translates to:
  /// **'oppure'**
  String get or;

  /// No description provided for @passkeyNotCompleted.
  ///
  /// In it, this message translates to:
  /// **'Accesso con passkey non completato'**
  String get passkeyNotCompleted;

  /// No description provided for @serverChange.
  ///
  /// In it, this message translates to:
  /// **'Server: {host} · cambia'**
  String serverChange(String host);

  /// No description provided for @mfaTitle.
  ///
  /// In it, this message translates to:
  /// **'Verifica in due passaggi'**
  String get mfaTitle;

  /// No description provided for @mfaTotpHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il codice a 6 cifre dell\'app di autenticazione'**
  String get mfaTotpHint;

  /// No description provided for @mfaRecoveryHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci uno dei codici di recupero salvati'**
  String get mfaRecoveryHint;

  /// No description provided for @useAuthenticator.
  ///
  /// In it, this message translates to:
  /// **'Usa l\'app di autenticazione'**
  String get useAuthenticator;

  /// No description provided for @useRecoveryCode.
  ///
  /// In it, this message translates to:
  /// **'Usa un codice di recupero'**
  String get useRecoveryCode;

  /// No description provided for @recoveryCodesLeft.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{Ti resta 1 codice di recupero} other{Ti restano {n} codici di recupero}}: generane di nuovi dal tuo account'**
  String recoveryCodesLeft(int n);

  /// No description provided for @inviteInvalid.
  ///
  /// In it, this message translates to:
  /// **'Invito non valido'**
  String get inviteInvalid;

  /// No description provided for @goToLogin.
  ///
  /// In it, this message translates to:
  /// **'Vai all\'accesso'**
  String get goToLogin;

  /// No description provided for @resetTitle.
  ///
  /// In it, this message translates to:
  /// **'Ripristino accesso'**
  String get resetTitle;

  /// No description provided for @welcome.
  ///
  /// In it, this message translates to:
  /// **'Benvenuto, {name}'**
  String welcome(String name);

  /// No description provided for @inviteHint.
  ///
  /// In it, this message translates to:
  /// **'{email}\nScegli una password di almeno 12 caratteri, poi configurerai l\'app di autenticazione.'**
  String inviteHint(String email);

  /// No description provided for @newPassword.
  ///
  /// In it, this message translates to:
  /// **'Nuova password'**
  String get newPassword;

  /// No description provided for @repeatPassword.
  ///
  /// In it, this message translates to:
  /// **'Ripeti password'**
  String get repeatPassword;

  /// No description provided for @passwordTooShort.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 12 caratteri'**
  String get passwordTooShort;

  /// No description provided for @passwordsDiffer.
  ///
  /// In it, this message translates to:
  /// **'Le password non coincidono'**
  String get passwordsDiffer;

  /// No description provided for @sessionExpired.
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta'**
  String get sessionExpired;

  /// No description provided for @loginAgain.
  ///
  /// In it, this message translates to:
  /// **'Accedi di nuovo'**
  String get loginAgain;

  /// No description provided for @enrollTitle.
  ///
  /// In it, this message translates to:
  /// **'Configura la verifica in due passaggi'**
  String get enrollTitle;

  /// No description provided for @enrollHint.
  ///
  /// In it, this message translates to:
  /// **'Obbligatoria. Inquadra il codice con un\'app di autenticazione (Aegis, Google Authenticator, 2FAS...) e inserisci il codice generato.'**
  String get enrollHint;

  /// No description provided for @keyCopied.
  ///
  /// In it, this message translates to:
  /// **'Chiave copiata'**
  String get keyCopied;

  /// No description provided for @copyKey.
  ///
  /// In it, this message translates to:
  /// **'Copia la chiave'**
  String get copyKey;

  /// No description provided for @activate.
  ///
  /// In it, this message translates to:
  /// **'Attiva'**
  String get activate;

  /// No description provided for @recoveryTitle.
  ///
  /// In it, this message translates to:
  /// **'Codici di recupero'**
  String get recoveryTitle;

  /// No description provided for @recoveryHint.
  ///
  /// In it, this message translates to:
  /// **'Conservali in un posto sicuro: ognuno permette un accesso se perdi il telefono. Non verranno mostrati di nuovo.'**
  String get recoveryHint;

  /// No description provided for @codesCopied.
  ///
  /// In it, this message translates to:
  /// **'Codici copiati'**
  String get codesCopied;

  /// No description provided for @codesSaved.
  ///
  /// In it, this message translates to:
  /// **'Ho salvato i codici'**
  String get codesSaved;

  /// No description provided for @createPasskey.
  ///
  /// In it, this message translates to:
  /// **'Crea una passkey (impronta)'**
  String get createPasskey;

  /// No description provided for @later.
  ///
  /// In it, this message translates to:
  /// **'Più tardi'**
  String get later;

  /// No description provided for @passkeyCreated.
  ///
  /// In it, this message translates to:
  /// **'Passkey creata: potrai accedere con l\'impronta'**
  String get passkeyCreated;

  /// No description provided for @passkeyNotCreated.
  ///
  /// In it, this message translates to:
  /// **'Passkey non creata'**
  String get passkeyNotCreated;

  /// No description provided for @defaultPasskeyBrowser.
  ///
  /// In it, this message translates to:
  /// **'Browser'**
  String get defaultPasskeyBrowser;

  /// No description provided for @defaultPasskeyPhone.
  ///
  /// In it, this message translates to:
  /// **'Telefono'**
  String get defaultPasskeyPhone;

  /// No description provided for @devicesTitle.
  ///
  /// In it, this message translates to:
  /// **'Dispositivi'**
  String get devicesTitle;

  /// No description provided for @add.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi'**
  String get add;

  /// No description provided for @noDevices.
  ///
  /// In it, this message translates to:
  /// **'Nessun dispositivo. Aggiungi il tuo tracker con il codice sull\'etichetta.'**
  String get noDevices;

  /// No description provided for @noDevicesShort.
  ///
  /// In it, this message translates to:
  /// **'Nessun dispositivo'**
  String get noDevicesShort;

  /// No description provided for @addYourTracker.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi il tuo tracker'**
  String get addYourTracker;

  /// No description provided for @waitingFirstContact.
  ///
  /// In it, this message translates to:
  /// **'In attesa del primo collegamento'**
  String get waitingFirstContact;

  /// No description provided for @noPosition.
  ///
  /// In it, this message translates to:
  /// **'Nessuna posizione'**
  String get noPosition;

  /// No description provided for @sharedBy.
  ///
  /// In it, this message translates to:
  /// **'condiviso da {name}'**
  String sharedBy(String name);

  /// No description provided for @signalTooltip.
  ///
  /// In it, this message translates to:
  /// **'Segnale {quality}'**
  String signalTooltip(String quality);

  /// No description provided for @satellitesTooltip.
  ///
  /// In it, this message translates to:
  /// **'Satelliti {quality}'**
  String satellitesTooltip(String quality);

  /// No description provided for @fromCell.
  ///
  /// In it, this message translates to:
  /// **'posizione dalla cella'**
  String get fromCell;

  /// No description provided for @lastKnown.
  ///
  /// In it, this message translates to:
  /// **'ultima posizione nota'**
  String get lastKnown;

  /// No description provided for @device.
  ///
  /// In it, this message translates to:
  /// **'Dispositivo'**
  String get device;

  /// No description provided for @tabLive.
  ///
  /// In it, this message translates to:
  /// **'Live'**
  String get tabLive;

  /// No description provided for @tabHistory.
  ///
  /// In it, this message translates to:
  /// **'Storico'**
  String get tabHistory;

  /// No description provided for @tabAnalysis.
  ///
  /// In it, this message translates to:
  /// **'Analisi'**
  String get tabAnalysis;

  /// No description provided for @tabAreas.
  ///
  /// In it, this message translates to:
  /// **'Aree'**
  String get tabAreas;

  /// No description provided for @tabSettings.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get tabSettings;

  /// No description provided for @last24h.
  ///
  /// In it, this message translates to:
  /// **'24 ore'**
  String get last24h;

  /// No description provided for @periodLast24h.
  ///
  /// In it, this message translates to:
  /// **'Ultime 24 ore'**
  String get periodLast24h;

  /// No description provided for @periodLast7d.
  ///
  /// In it, this message translates to:
  /// **'Ultimi 7 giorni'**
  String get periodLast7d;

  /// No description provided for @periodLast30d.
  ///
  /// In it, this message translates to:
  /// **'Ultimi 30 giorni'**
  String get periodLast30d;

  /// No description provided for @periodLast90d.
  ///
  /// In it, this message translates to:
  /// **'Ultimi 90 giorni'**
  String get periodLast90d;

  /// No description provided for @periodCustom.
  ///
  /// In it, this message translates to:
  /// **'Intervallo personalizzato'**
  String get periodCustom;

  /// No description provided for @accessRevoked.
  ///
  /// In it, this message translates to:
  /// **'La condivisione di {device} è terminata'**
  String accessRevoked(String device);

  /// No description provided for @leaveShare.
  ///
  /// In it, this message translates to:
  /// **'Smetti di ricevere'**
  String get leaveShare;

  /// No description provided for @leaveShareTitle.
  ///
  /// In it, this message translates to:
  /// **'Smettere di ricevere {device}?'**
  String leaveShareTitle(String device);

  /// No description provided for @leaveShareBody.
  ///
  /// In it, this message translates to:
  /// **'Non lo vedrai più e le tue aree su questo dispositivo vengono cancellate.'**
  String get leaveShareBody;

  /// No description provided for @followOn.
  ///
  /// In it, this message translates to:
  /// **'Segui il veicolo (attivo)'**
  String get followOn;

  /// No description provided for @followOff.
  ///
  /// In it, this message translates to:
  /// **'Segui il veicolo'**
  String get followOff;

  /// No description provided for @liveUntil.
  ///
  /// In it, this message translates to:
  /// **'Live fino alle {time}'**
  String liveUntil(String time);

  /// No description provided for @connected.
  ///
  /// In it, this message translates to:
  /// **'Collegato'**
  String get connected;

  /// No description provided for @notConnected.
  ///
  /// In it, this message translates to:
  /// **'Non collegato · ultimo contatto {ago}'**
  String notConnected(String ago);

  /// No description provided for @noPositionReceived.
  ///
  /// In it, this message translates to:
  /// **'Nessuna posizione ricevuta'**
  String get noPositionReceived;

  /// No description provided for @cellEstimate.
  ///
  /// In it, this message translates to:
  /// **'stimata dalla cella (±{meters} m)'**
  String cellEstimate(String meters);

  /// No description provided for @noFix.
  ///
  /// In it, this message translates to:
  /// **'senza fix GPS'**
  String get noFix;

  /// No description provided for @commandSent.
  ///
  /// In it, this message translates to:
  /// **'Comando inviato'**
  String get commandSent;

  /// No description provided for @commandQueued.
  ///
  /// In it, this message translates to:
  /// **'Comando in coda: il tracker lo riceverà al prossimo collegamento'**
  String get commandQueued;

  /// No description provided for @live30.
  ///
  /// In it, this message translates to:
  /// **'Live 30 min'**
  String get live30;

  /// No description provided for @stopLive.
  ///
  /// In it, this message translates to:
  /// **'Ferma live'**
  String get stopLive;

  /// No description provided for @locate.
  ///
  /// In it, this message translates to:
  /// **'Localizza'**
  String get locate;

  /// No description provided for @resumeAntitheft.
  ///
  /// In it, this message translates to:
  /// **'Riattiva antifurto (in pausa fino alle {time})'**
  String resumeAntitheft(String time);

  /// No description provided for @pauseAntitheftTooltip.
  ///
  /// In it, this message translates to:
  /// **'Metti in pausa l\'antifurto (officina, lavaggio...)'**
  String get pauseAntitheftTooltip;

  /// No description provided for @pause1h.
  ///
  /// In it, this message translates to:
  /// **'Pausa 1 ora'**
  String get pause1h;

  /// No description provided for @pause24h.
  ///
  /// In it, this message translates to:
  /// **'Pausa 24 ore'**
  String get pause24h;

  /// No description provided for @pause7d.
  ///
  /// In it, this message translates to:
  /// **'Pausa 7 giorni'**
  String get pause7d;

  /// No description provided for @pauseAntitheft.
  ///
  /// In it, this message translates to:
  /// **'Pausa antifurto'**
  String get pauseAntitheft;

  /// No description provided for @viewerNotice.
  ///
  /// In it, this message translates to:
  /// **'Condiviso da {owner} in sola visione{until}'**
  String viewerNotice(String owner, String until);

  /// No description provided for @viewerUntil.
  ///
  /// In it, this message translates to:
  /// **' fino al {date}'**
  String viewerUntil(String date);

  /// No description provided for @noPositions.
  ///
  /// In it, this message translates to:
  /// **'Nessuna posizione nel periodo'**
  String get noPositions;

  /// No description provided for @truncated.
  ///
  /// In it, this message translates to:
  /// **'Troppi punti: mostrati i primi 50.000, riduci il periodo'**
  String get truncated;

  /// No description provided for @pointsRange.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 punto} other{{n} punti}} dal {from} al {to}'**
  String pointsRange(int n, String from, String to);

  /// No description provided for @noFixShort.
  ///
  /// In it, this message translates to:
  /// **'senza fix'**
  String get noFixShort;

  /// No description provided for @coloringPlain.
  ///
  /// In it, this message translates to:
  /// **'Percorso'**
  String get coloringPlain;

  /// No description provided for @coloringSpeed.
  ///
  /// In it, this message translates to:
  /// **'Velocità'**
  String get coloringSpeed;

  /// No description provided for @coloringSignal.
  ///
  /// In it, this message translates to:
  /// **'Segnale'**
  String get coloringSignal;

  /// No description provided for @coloringSatellites.
  ///
  /// In it, this message translates to:
  /// **'Satelliti'**
  String get coloringSatellites;

  /// No description provided for @legendNoFix.
  ///
  /// In it, this message translates to:
  /// **'4 sat / senza fix'**
  String get legendNoFix;

  /// No description provided for @kpiDistance.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get kpiDistance;

  /// No description provided for @kpiDriving.
  ///
  /// In it, this message translates to:
  /// **'Alla guida'**
  String get kpiDriving;

  /// No description provided for @kpiMaxSpeed.
  ///
  /// In it, this message translates to:
  /// **'Velocità max'**
  String get kpiMaxSpeed;

  /// No description provided for @kpiTrips.
  ///
  /// In it, this message translates to:
  /// **'Viaggi'**
  String get kpiTrips;

  /// No description provided for @kmPerDay.
  ///
  /// In it, this message translates to:
  /// **'Km per giorno'**
  String get kmPerDay;

  /// No description provided for @drivingPerDay.
  ///
  /// In it, this message translates to:
  /// **'Tempo di guida per giorno'**
  String get drivingPerDay;

  /// No description provided for @tripsList.
  ///
  /// In it, this message translates to:
  /// **'Viaggi ({n})'**
  String tripsList(int n);

  /// No description provided for @tripDetail.
  ///
  /// In it, this message translates to:
  /// **'{km} km · {duration} · media {avg} km/h · max {max} km/h'**
  String tripDetail(String km, String duration, String avg, String max);

  /// No description provided for @bucket2m.
  ///
  /// In it, this message translates to:
  /// **'2 minuti'**
  String get bucket2m;

  /// No description provided for @bucket10m.
  ///
  /// In it, this message translates to:
  /// **'10 minuti'**
  String get bucket10m;

  /// No description provided for @bucket1h.
  ///
  /// In it, this message translates to:
  /// **'ora'**
  String get bucket1h;

  /// No description provided for @bucket6h.
  ///
  /// In it, this message translates to:
  /// **'6 ore'**
  String get bucket6h;

  /// No description provided for @bucket1d.
  ///
  /// In it, this message translates to:
  /// **'giorno'**
  String get bucket1d;

  /// No description provided for @chartSpeed.
  ///
  /// In it, this message translates to:
  /// **'Velocità'**
  String get chartSpeed;

  /// No description provided for @chartSpeedSub.
  ///
  /// In it, this message translates to:
  /// **'media e massima ogni {bucket}'**
  String chartSpeedSub(String bucket);

  /// No description provided for @seriesMax.
  ///
  /// In it, this message translates to:
  /// **'Massima'**
  String get seriesMax;

  /// No description provided for @seriesAvgMoving.
  ///
  /// In it, this message translates to:
  /// **'Media in movimento'**
  String get seriesAvgMoving;

  /// No description provided for @chartSignal.
  ///
  /// In it, this message translates to:
  /// **'Segnale LTE'**
  String get chartSignal;

  /// No description provided for @chartSignalSub.
  ///
  /// In it, this message translates to:
  /// **'sotto -105 dBm il collegamento diventa instabile'**
  String get chartSignalSub;

  /// No description provided for @seriesAvg.
  ///
  /// In it, this message translates to:
  /// **'Medio'**
  String get seriesAvg;

  /// No description provided for @seriesMin.
  ///
  /// In it, this message translates to:
  /// **'Minimo'**
  String get seriesMin;

  /// No description provided for @thresholdPoor.
  ///
  /// In it, this message translates to:
  /// **'scarso'**
  String get thresholdPoor;

  /// No description provided for @chartSatellites.
  ///
  /// In it, this message translates to:
  /// **'Satelliti in uso'**
  String get chartSatellites;

  /// No description provided for @chartSatellitesSub.
  ///
  /// In it, this message translates to:
  /// **'sotto 6 la posizione è poco precisa'**
  String get chartSatellitesSub;

  /// No description provided for @thresholdWeakFix.
  ///
  /// In it, this message translates to:
  /// **'fix debole'**
  String get thresholdWeakFix;

  /// No description provided for @chartAltitude.
  ///
  /// In it, this message translates to:
  /// **'Altitudine'**
  String get chartAltitude;

  /// No description provided for @chartBattery.
  ///
  /// In it, this message translates to:
  /// **'Batteria dell\'auto'**
  String get chartBattery;

  /// No description provided for @chartBatterySub.
  ///
  /// In it, this message translates to:
  /// **'tensione minima e media: sotto 11,8 V a motore spento la batteria è scarica'**
  String get chartBatterySub;

  /// No description provided for @chartTemperature.
  ///
  /// In it, this message translates to:
  /// **'Temperatura nell\'abitacolo'**
  String get chartTemperature;

  /// No description provided for @chartPressure.
  ///
  /// In it, this message translates to:
  /// **'Pressione atmosferica'**
  String get chartPressure;

  /// No description provided for @chartPoints.
  ///
  /// In it, this message translates to:
  /// **'Punti ricevuti'**
  String get chartPoints;

  /// No description provided for @chartPointsSub.
  ///
  /// In it, this message translates to:
  /// **'in rosso quelli senza fix GPS'**
  String get chartPointsSub;

  /// No description provided for @seriesPoints.
  ///
  /// In it, this message translates to:
  /// **'Punti'**
  String get seriesPoints;

  /// No description provided for @seriesNoFix.
  ///
  /// In it, this message translates to:
  /// **'Senza fix'**
  String get seriesNoFix;

  /// No description provided for @chartFixQuality.
  ///
  /// In it, this message translates to:
  /// **'Qualità della posizione'**
  String get chartFixQuality;

  /// No description provided for @fixGood.
  ///
  /// In it, this message translates to:
  /// **'Fix buono'**
  String get fixGood;

  /// No description provided for @fixWeak.
  ///
  /// In it, this message translates to:
  /// **'Fix debole (<6 sat)'**
  String get fixWeak;

  /// No description provided for @chartSignalDistribution.
  ///
  /// In it, this message translates to:
  /// **'Distribuzione del segnale'**
  String get chartSignalDistribution;

  /// No description provided for @weakSignalShare.
  ///
  /// In it, this message translates to:
  /// **'{p}% dei punti sotto -105 dBm'**
  String weakSignalShare(int p);

  /// No description provided for @chartSatelliteDistribution.
  ///
  /// In it, this message translates to:
  /// **'Distribuzione dei satelliti'**
  String get chartSatelliteDistribution;

  /// No description provided for @chartSpeedDistribution.
  ///
  /// In it, this message translates to:
  /// **'Distribuzione della velocità'**
  String get chartSpeedDistribution;

  /// No description provided for @chartSpeedDistributionSub.
  ///
  /// In it, this message translates to:
  /// **'punti in movimento per fascia di 10 km/h'**
  String get chartSpeedDistributionSub;

  /// No description provided for @chartCoverage.
  ///
  /// In it, this message translates to:
  /// **'Copertura della rete'**
  String get chartCoverage;

  /// No description provided for @chartCoverageSub.
  ///
  /// In it, this message translates to:
  /// **'segnale medio per zona: in rosso dove il tracker perde la rete'**
  String get chartCoverageSub;

  /// No description provided for @simMonth.
  ///
  /// In it, this message translates to:
  /// **'Dati SIM del mese'**
  String get simMonth;

  /// No description provided for @simUsed.
  ///
  /// In it, this message translates to:
  /// **'Usati {used} di {budget} · stima a fine mese {projected} ({p}%)'**
  String simUsed(String used, String budget, String projected, int p);

  /// No description provided for @simEstimate.
  ///
  /// In it, this message translates to:
  /// **'Stima: frame cifrati + intestazioni TLS/WebSocket + connessioni'**
  String get simEstimate;

  /// No description provided for @dataPerDay.
  ///
  /// In it, this message translates to:
  /// **'Dati per giorno'**
  String get dataPerDay;

  /// No description provided for @dataPerDaySub.
  ///
  /// In it, this message translates to:
  /// **'la linea è il consumo giornaliero che rispetta il piano'**
  String get dataPerDaySub;

  /// No description provided for @budget.
  ///
  /// In it, this message translates to:
  /// **'budget'**
  String get budget;

  /// No description provided for @deviceName.
  ///
  /// In it, this message translates to:
  /// **'Nome del dispositivo'**
  String get deviceName;

  /// No description provided for @tapToRename.
  ///
  /// In it, this message translates to:
  /// **'Tocca per rinominare'**
  String get tapToRename;

  /// No description provided for @imei.
  ///
  /// In it, this message translates to:
  /// **'IMEI'**
  String get imei;

  /// No description provided for @modemFirmware.
  ///
  /// In it, this message translates to:
  /// **'Modem e firmware'**
  String get modemFirmware;

  /// No description provided for @firmwareVersion.
  ///
  /// In it, this message translates to:
  /// **'firmware {v}'**
  String firmwareVersion(String v);

  /// No description provided for @neverConnected.
  ///
  /// In it, this message translates to:
  /// **'mai collegato'**
  String get neverConnected;

  /// No description provided for @connectedSince.
  ///
  /// In it, this message translates to:
  /// **'collegato dal {date}'**
  String connectedSince(String date);

  /// No description provided for @alarmNotifications.
  ///
  /// In it, this message translates to:
  /// **'Notifiche di allarme'**
  String get alarmNotifications;

  /// No description provided for @sharing.
  ///
  /// In it, this message translates to:
  /// **'Condivisione'**
  String get sharing;

  /// No description provided for @sharingHint.
  ///
  /// In it, this message translates to:
  /// **'Chi riceve la condivisione vede solo posizione, velocità e stato, senza poter cambiare nulla.'**
  String get sharingHint;

  /// No description provided for @shareWith.
  ///
  /// In it, this message translates to:
  /// **'Condividi con un amico'**
  String get shareWith;

  /// No description provided for @shareTitle.
  ///
  /// In it, this message translates to:
  /// **'Condividi in sola visione'**
  String get shareTitle;

  /// No description provided for @shareFriend.
  ///
  /// In it, this message translates to:
  /// **'Amico'**
  String get shareFriend;

  /// No description provided for @noFriendsToShare.
  ///
  /// In it, this message translates to:
  /// **'Puoi condividere solo con gli amici: aggiungine uno con il suo codice.'**
  String get noFriendsToShare;

  /// No description provided for @goToFriends.
  ///
  /// In it, this message translates to:
  /// **'Vai agli amici'**
  String get goToFriends;

  /// No description provided for @shareDuration.
  ///
  /// In it, this message translates to:
  /// **'Durata'**
  String get shareDuration;

  /// No description provided for @permanent.
  ///
  /// In it, this message translates to:
  /// **'Permanente'**
  String get permanent;

  /// No description provided for @hoursShort.
  ///
  /// In it, this message translates to:
  /// **'{n} h'**
  String hoursShort(int n);

  /// No description provided for @daysShort.
  ///
  /// In it, this message translates to:
  /// **'{n} g'**
  String daysShort(int n);

  /// No description provided for @customEnd.
  ///
  /// In it, this message translates to:
  /// **'Data e ora'**
  String get customEnd;

  /// No description provided for @endsAt.
  ///
  /// In it, this message translates to:
  /// **'Fino al {date}'**
  String endsAt(String date);

  /// No description provided for @share.
  ///
  /// In it, this message translates to:
  /// **'Condividi'**
  String get share;

  /// No description provided for @shared.
  ///
  /// In it, this message translates to:
  /// **'Dispositivo condiviso'**
  String get shared;

  /// No description provided for @noShares.
  ///
  /// In it, this message translates to:
  /// **'Non condiviso con nessuno'**
  String get noShares;

  /// No description provided for @sharePermanent.
  ///
  /// In it, this message translates to:
  /// **'Permanente'**
  String get sharePermanent;

  /// No description provided for @shareUntil.
  ///
  /// In it, this message translates to:
  /// **'Fino al {date}'**
  String shareUntil(String date);

  /// No description provided for @changeEnd.
  ///
  /// In it, this message translates to:
  /// **'Cambia scadenza'**
  String get changeEnd;

  /// No description provided for @revoke.
  ///
  /// In it, this message translates to:
  /// **'Revoca'**
  String get revoke;

  /// No description provided for @revokeTitle.
  ///
  /// In it, this message translates to:
  /// **'Revocare la condivisione a {name}?'**
  String revokeTitle(String name);

  /// No description provided for @revokeBody.
  ///
  /// In it, this message translates to:
  /// **'Non vedrà più il dispositivo e le sue aree vengono cancellate.'**
  String get revokeBody;

  /// No description provided for @shareRevoked.
  ///
  /// In it, this message translates to:
  /// **'Condivisione revocata'**
  String get shareRevoked;

  /// No description provided for @dangerZone.
  ///
  /// In it, this message translates to:
  /// **'Zona pericolosa'**
  String get dangerZone;

  /// No description provided for @removeTracker.
  ///
  /// In it, this message translates to:
  /// **'Elimina il veicolo'**
  String get removeTracker;

  /// No description provided for @removeTrackerSub.
  ///
  /// In it, this message translates to:
  /// **'Con il suo storico; il tracker torna libero'**
  String get removeTrackerSub;

  /// No description provided for @removeTrackerTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il veicolo?'**
  String get removeTrackerTitle;

  /// No description provided for @removeTrackerBody.
  ///
  /// In it, this message translates to:
  /// **'Storico, km, scadenze, costi, aree, condivisioni e notifiche vengono cancellati. Il tracker torna libero e si potrà abbinare di nuovo con il codice dell\'etichetta. Per tenere lo storico usa «Rimuovi il tracker dal veicolo».'**
  String get removeTrackerBody;

  /// No description provided for @errVehicleHasTracker.
  ///
  /// In it, this message translates to:
  /// **'Il veicolo ha già un tracker'**
  String get errVehicleHasTracker;

  /// No description provided for @pairInHint.
  ///
  /// In it, this message translates to:
  /// **'In quale veicolo lo installi? In un veicolo che hai già restano il suo storico, i km e le scadenze.'**
  String get pairInHint;

  /// No description provided for @pairNewVehicle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo veicolo'**
  String get pairNewVehicle;

  /// No description provided for @trackerSection.
  ///
  /// In it, this message translates to:
  /// **'Tracker'**
  String get trackerSection;

  /// No description provided for @moveTracker.
  ///
  /// In it, this message translates to:
  /// **'Sposta su un altro veicolo'**
  String get moveTracker;

  /// No description provided for @moveTrackerSub.
  ///
  /// In it, this message translates to:
  /// **'Questo veicolo resta con il suo storico'**
  String get moveTrackerSub;

  /// No description provided for @moveTrackerTitle.
  ///
  /// In it, this message translates to:
  /// **'Spostare il tracker?'**
  String get moveTrackerTitle;

  /// No description provided for @moveTarget.
  ///
  /// In it, this message translates to:
  /// **'Veicolo di destinazione'**
  String get moveTarget;

  /// No description provided for @archivePrevious.
  ///
  /// In it, this message translates to:
  /// **'Archivia questo veicolo'**
  String get archivePrevious;

  /// No description provided for @move.
  ///
  /// In it, this message translates to:
  /// **'Sposta'**
  String get move;

  /// No description provided for @trackerMoved.
  ///
  /// In it, this message translates to:
  /// **'Tracker spostato su {name}'**
  String trackerMoved(String name);

  /// No description provided for @detachTracker.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi il tracker dal veicolo'**
  String get detachTracker;

  /// No description provided for @detachTrackerSub.
  ///
  /// In it, this message translates to:
  /// **'Il veicolo resta, il tracker si può abbinare di nuovo'**
  String get detachTrackerSub;

  /// No description provided for @detachTrackerTitle.
  ///
  /// In it, this message translates to:
  /// **'Rimuovere il tracker?'**
  String get detachTrackerTitle;

  /// No description provided for @detachTrackerBody.
  ///
  /// In it, this message translates to:
  /// **'Il veicolo resta con storico, km, scadenze e condivisioni, senza tracker. Il tracker si potrà abbinare di nuovo con il codice dell\'etichetta.'**
  String get detachTrackerBody;

  /// No description provided for @trackerDetached.
  ///
  /// In it, this message translates to:
  /// **'Tracker rimosso'**
  String get trackerDetached;

  /// No description provided for @archived.
  ///
  /// In it, this message translates to:
  /// **'Archiviato'**
  String get archived;

  /// No description provided for @archiveSub.
  ///
  /// In it, this message translates to:
  /// **'Nascosto dalla mappa; storico e scadenze restano'**
  String get archiveSub;

  /// No description provided for @installations.
  ///
  /// In it, this message translates to:
  /// **'Tracker installati'**
  String get installations;

  /// No description provided for @installedRange.
  ///
  /// In it, this message translates to:
  /// **'dal {from} al {to}'**
  String installedRange(String from, String to);

  /// No description provided for @installedSince.
  ///
  /// In it, this message translates to:
  /// **'dal {from}'**
  String installedSince(String from);

  /// No description provided for @areasHint.
  ///
  /// In it, this message translates to:
  /// **'Ricevi una notifica quando il dispositivo entra (o esce) da un\'area: per esempio quando sta per arrivare a destinazione.'**
  String get areasHint;

  /// No description provided for @noAreas.
  ///
  /// In it, this message translates to:
  /// **'Nessuna area'**
  String get noAreas;

  /// No description provided for @addArea.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi un\'area'**
  String get addArea;

  /// No description provided for @editArea.
  ///
  /// In it, this message translates to:
  /// **'Modifica area'**
  String get editArea;

  /// No description provided for @areaName.
  ///
  /// In it, this message translates to:
  /// **'Nome dell\'area'**
  String get areaName;

  /// No description provided for @areaDefaultName.
  ///
  /// In it, this message translates to:
  /// **'Destinazione'**
  String get areaDefaultName;

  /// No description provided for @radius.
  ///
  /// In it, this message translates to:
  /// **'Raggio: {distance}'**
  String radius(String distance);

  /// No description provided for @notifyEnter.
  ///
  /// In it, this message translates to:
  /// **'Avvisa all\'arrivo'**
  String get notifyEnter;

  /// No description provided for @notifyExit.
  ///
  /// In it, this message translates to:
  /// **'Avvisa alla partenza'**
  String get notifyExit;

  /// No description provided for @tapMapToPlace.
  ///
  /// In it, this message translates to:
  /// **'Tocca la mappa per spostare il centro'**
  String get tapMapToPlace;

  /// No description provided for @areaInside.
  ///
  /// In it, this message translates to:
  /// **'dentro'**
  String get areaInside;

  /// No description provided for @areaOutside.
  ///
  /// In it, this message translates to:
  /// **'fuori'**
  String get areaOutside;

  /// No description provided for @areaSummary.
  ///
  /// In it, this message translates to:
  /// **'{radius} · {state}'**
  String areaSummary(String radius, String state);

  /// No description provided for @deleteAreaTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare {name}?'**
  String deleteAreaTitle(String name);

  /// No description provided for @areaSaved.
  ///
  /// In it, this message translates to:
  /// **'Area salvata'**
  String get areaSaved;

  /// No description provided for @addTracker.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi tracker'**
  String get addTracker;

  /// No description provided for @scanTitle.
  ///
  /// In it, this message translates to:
  /// **'Inquadra il QR dell\'etichetta'**
  String get scanTitle;

  /// No description provided for @stepLabel.
  ///
  /// In it, this message translates to:
  /// **'Etichetta del tracker'**
  String get stepLabel;

  /// No description provided for @stepLabelSub.
  ///
  /// In it, this message translates to:
  /// **'QR code o IMEI e codice di abbinamento'**
  String get stepLabelSub;

  /// No description provided for @stepName.
  ///
  /// In it, this message translates to:
  /// **'Veicolo'**
  String get stepName;

  /// No description provided for @stepPower.
  ///
  /// In it, this message translates to:
  /// **'Accensione'**
  String get stepPower;

  /// No description provided for @stepPowerSub.
  ///
  /// In it, this message translates to:
  /// **'Primo collegamento del tracker'**
  String get stepPowerSub;

  /// No description provided for @stepDone.
  ///
  /// In it, this message translates to:
  /// **'Fatto'**
  String get stepDone;

  /// No description provided for @labelHint.
  ///
  /// In it, this message translates to:
  /// **'Sul tracker (o sulla sua scatola) c\'è un\'etichetta con un QR code, l\'IMEI e il codice di abbinamento. Il codice dimostra che hai il tracker in mano: tienilo riservato.'**
  String get labelHint;

  /// No description provided for @scanQr.
  ///
  /// In it, this message translates to:
  /// **'Scansiona il QR code'**
  String get scanQr;

  /// No description provided for @manualEntry.
  ///
  /// In it, this message translates to:
  /// **'oppure inserisci i dati a mano'**
  String get manualEntry;

  /// No description provided for @imeiLabel.
  ///
  /// In it, this message translates to:
  /// **'IMEI (15 cifre)'**
  String get imeiLabel;

  /// No description provided for @pairingCode.
  ///
  /// In it, this message translates to:
  /// **'Codice di abbinamento'**
  String get pairingCode;

  /// No description provided for @imeiInvalid.
  ///
  /// In it, this message translates to:
  /// **'L\'IMEI ha 15 cifre'**
  String get imeiInvalid;

  /// No description provided for @alreadyMine.
  ///
  /// In it, this message translates to:
  /// **'Questo tracker è già nel tuo account'**
  String get alreadyMine;

  /// No description provided for @ownedByOther.
  ///
  /// In it, this message translates to:
  /// **'Il tracker appartiene a un altro account: chiedi al proprietario di condividerlo'**
  String get ownedByOther;

  /// No description provided for @defaultDeviceName.
  ///
  /// In it, this message translates to:
  /// **'La mia auto'**
  String get defaultDeviceName;

  /// No description provided for @mapColor.
  ///
  /// In it, this message translates to:
  /// **'Colore sulla mappa'**
  String get mapColor;

  /// No description provided for @addToAccount.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi al mio account'**
  String get addToAccount;

  /// No description provided for @insertSim.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la SIM nel tracker'**
  String get insertSim;

  /// No description provided for @connectPower.
  ///
  /// In it, this message translates to:
  /// **'Collegalo all\'alimentazione dell\'auto'**
  String get connectPower;

  /// No description provided for @parkOutside.
  ///
  /// In it, this message translates to:
  /// **'Lascia l\'auto all\'aperto'**
  String get parkOutside;

  /// No description provided for @firstFixHint.
  ///
  /// In it, this message translates to:
  /// **'Il primo fix GPS può richiedere qualche minuto'**
  String get firstFixHint;

  /// No description provided for @waitingTracker.
  ///
  /// In it, this message translates to:
  /// **'In attesa del primo collegamento del tracker...'**
  String get waitingTracker;

  /// No description provided for @continueLater.
  ///
  /// In it, this message translates to:
  /// **'Continua in seguito'**
  String get continueLater;

  /// No description provided for @trackerConnected.
  ///
  /// In it, this message translates to:
  /// **'Il tracker è collegato. La prima posizione arriva appena l\'auto si muove o al prossimo controllo periodico.'**
  String get trackerConnected;

  /// No description provided for @openDevice.
  ///
  /// In it, this message translates to:
  /// **'Apri il dispositivo'**
  String get openDevice;

  /// No description provided for @accountTitle.
  ///
  /// In it, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// No description provided for @editName.
  ///
  /// In it, this message translates to:
  /// **'Modifica nome'**
  String get editName;

  /// No description provided for @language.
  ///
  /// In it, this message translates to:
  /// **'Lingua'**
  String get language;

  /// No description provided for @administration.
  ///
  /// In it, this message translates to:
  /// **'Amministrazione'**
  String get administration;

  /// No description provided for @administrationSub.
  ///
  /// In it, this message translates to:
  /// **'Utenti, inviti, ripristino accessi'**
  String get administrationSub;

  /// No description provided for @passkeys.
  ///
  /// In it, this message translates to:
  /// **'Passkey'**
  String get passkeys;

  /// No description provided for @passkeyCreatedAgo.
  ///
  /// In it, this message translates to:
  /// **'Creata {ago}'**
  String passkeyCreatedAgo(String ago);

  /// No description provided for @passkeyUsedAgo.
  ///
  /// In it, this message translates to:
  /// **' · usata {ago}'**
  String passkeyUsedAgo(String ago);

  /// No description provided for @passkeySynced.
  ///
  /// In it, this message translates to:
  /// **' · sincronizzata'**
  String get passkeySynced;

  /// No description provided for @passkeyRemoved.
  ///
  /// In it, this message translates to:
  /// **'Passkey rimossa'**
  String get passkeyRemoved;

  /// No description provided for @addPasskey.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi una passkey'**
  String get addPasskey;

  /// No description provided for @addPasskeySub.
  ///
  /// In it, this message translates to:
  /// **'Accesso con impronta o blocco schermo'**
  String get addPasskeySub;

  /// No description provided for @passkeyName.
  ///
  /// In it, this message translates to:
  /// **'Nome della passkey'**
  String get passkeyName;

  /// No description provided for @passkeyAdded.
  ///
  /// In it, this message translates to:
  /// **'Passkey aggiunta'**
  String get passkeyAdded;

  /// No description provided for @security.
  ///
  /// In it, this message translates to:
  /// **'Sicurezza'**
  String get security;

  /// No description provided for @changePassword.
  ///
  /// In it, this message translates to:
  /// **'Cambia password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In it, this message translates to:
  /// **'Password attuale'**
  String get currentPassword;

  /// No description provided for @passwordMin.
  ///
  /// In it, this message translates to:
  /// **'Almeno 12 caratteri'**
  String get passwordMin;

  /// No description provided for @change.
  ///
  /// In it, this message translates to:
  /// **'Cambia'**
  String get change;

  /// No description provided for @passwordChanged.
  ///
  /// In it, this message translates to:
  /// **'Password cambiata: le altre sessioni sono state chiuse'**
  String get passwordChanged;

  /// No description provided for @changeAuthenticator.
  ///
  /// In it, this message translates to:
  /// **'Cambia app di autenticazione'**
  String get changeAuthenticator;

  /// No description provided for @newPhone.
  ///
  /// In it, this message translates to:
  /// **'Nuovo telefono'**
  String get newPhone;

  /// No description provided for @newAuthenticator.
  ///
  /// In it, this message translates to:
  /// **'Nuova app di autenticazione'**
  String get newAuthenticator;

  /// No description provided for @newAppCode.
  ///
  /// In it, this message translates to:
  /// **'Codice della nuova app'**
  String get newAppCode;

  /// No description provided for @authenticatorUpdated.
  ///
  /// In it, this message translates to:
  /// **'App di autenticazione aggiornata'**
  String get authenticatorUpdated;

  /// No description provided for @authenticatorCode.
  ///
  /// In it, this message translates to:
  /// **'Codice dell\'app di autenticazione'**
  String get authenticatorCode;

  /// No description provided for @confirmWithCode.
  ///
  /// In it, this message translates to:
  /// **'Conferma con il codice'**
  String get confirmWithCode;

  /// No description provided for @recoveryLeft.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 rimasto} other{{n} rimasti}} · genera nuovi codici'**
  String recoveryLeft(int n);

  /// No description provided for @newRecoveryCodes.
  ///
  /// In it, this message translates to:
  /// **'Nuovi codici di recupero'**
  String get newRecoveryCodes;

  /// No description provided for @newRecoveryHint.
  ///
  /// In it, this message translates to:
  /// **'I codici precedenti non sono più validi. Conservali in un posto sicuro.'**
  String get newRecoveryHint;

  /// No description provided for @activeSessions.
  ///
  /// In it, this message translates to:
  /// **'Sessioni attive'**
  String get activeSessions;

  /// No description provided for @thisSession.
  ///
  /// In it, this message translates to:
  /// **' (questa)'**
  String get thisSession;

  /// No description provided for @sessionActive.
  ///
  /// In it, this message translates to:
  /// **'{ip} · attiva {ago}'**
  String sessionActive(String ip, String ago);

  /// No description provided for @disconnect.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti'**
  String get disconnect;

  /// No description provided for @disconnectOthers.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti le altre sessioni'**
  String get disconnectOthers;

  /// No description provided for @sessionsClosed.
  ///
  /// In it, this message translates to:
  /// **'Sessioni chiuse'**
  String get sessionsClosed;

  /// No description provided for @app.
  ///
  /// In it, this message translates to:
  /// **'App'**
  String get app;

  /// No description provided for @pushTitle.
  ///
  /// In it, this message translates to:
  /// **'Notifiche push'**
  String get pushTitle;

  /// No description provided for @pushOn.
  ///
  /// In it, this message translates to:
  /// **'Attive'**
  String get pushOn;

  /// No description provided for @pushOff.
  ///
  /// In it, this message translates to:
  /// **'Non configurate: le notifiche arrivano solo con l\'app aperta'**
  String get pushOff;

  /// No description provided for @logout.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get logout;

  /// No description provided for @unknownAgent.
  ///
  /// In it, this message translates to:
  /// **'Sconosciuto'**
  String get unknownAgent;

  /// No description provided for @androidApp.
  ///
  /// In it, this message translates to:
  /// **'App Android'**
  String get androidApp;

  /// No description provided for @invite.
  ///
  /// In it, this message translates to:
  /// **'Invita'**
  String get invite;

  /// No description provided for @users.
  ///
  /// In it, this message translates to:
  /// **'Utenti'**
  String get users;

  /// No description provided for @userSummary.
  ///
  /// In it, this message translates to:
  /// **'{email} · {devices, plural, =1{1 dispositivo} other{{devices} dispositivi}} · {passkeys} passkey'**
  String userSummary(String email, int devices, int passkeys);

  /// No description provided for @twoFactorPending.
  ///
  /// In it, this message translates to:
  /// **' · 2FA da configurare'**
  String get twoFactorPending;

  /// No description provided for @lastLogin.
  ///
  /// In it, this message translates to:
  /// **' · accesso {ago}'**
  String lastLogin(String ago);

  /// No description provided for @resetAccess.
  ///
  /// In it, this message translates to:
  /// **'Ripristina accesso (nuova password e 2FA)'**
  String get resetAccess;

  /// No description provided for @resetLink.
  ///
  /// In it, this message translates to:
  /// **'Link di ripristino'**
  String get resetLink;

  /// No description provided for @enable.
  ///
  /// In it, this message translates to:
  /// **'Riattiva'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In it, this message translates to:
  /// **'Disattiva'**
  String get disable;

  /// No description provided for @removeAdmin.
  ///
  /// In it, this message translates to:
  /// **'Togli amministratore'**
  String get removeAdmin;

  /// No description provided for @makeAdmin.
  ///
  /// In it, this message translates to:
  /// **'Rendi amministratore'**
  String get makeAdmin;

  /// No description provided for @deleteUserTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare {name}?'**
  String deleteUserTitle(String name);

  /// No description provided for @deleteUserBody.
  ///
  /// In it, this message translates to:
  /// **'I suoi dispositivi restano senza proprietario e le sue condivisioni terminano.'**
  String get deleteUserBody;

  /// No description provided for @pendingInvites.
  ///
  /// In it, this message translates to:
  /// **'Inviti in attesa'**
  String get pendingInvites;

  /// No description provided for @none.
  ///
  /// In it, this message translates to:
  /// **'Nessuno'**
  String get none;

  /// No description provided for @expires.
  ///
  /// In it, this message translates to:
  /// **'Scade {date}'**
  String expires(String date);

  /// No description provided for @cancelInvite.
  ///
  /// In it, this message translates to:
  /// **'Annulla invito'**
  String get cancelInvite;

  /// No description provided for @inviteUser.
  ///
  /// In it, this message translates to:
  /// **'Invita un utente'**
  String get inviteUser;

  /// No description provided for @administrator.
  ///
  /// In it, this message translates to:
  /// **'Amministratore'**
  String get administrator;

  /// No description provided for @createInvite.
  ///
  /// In it, this message translates to:
  /// **'Crea invito'**
  String get createInvite;

  /// No description provided for @inviteCreated.
  ///
  /// In it, this message translates to:
  /// **'Invito creato'**
  String get inviteCreated;

  /// No description provided for @linkHint.
  ///
  /// In it, this message translates to:
  /// **'Invia questo link alla persona: vale 72 ore e si può usare una sola volta.'**
  String get linkHint;

  /// No description provided for @linkCopied.
  ///
  /// In it, this message translates to:
  /// **'Link copiato'**
  String get linkCopied;

  /// No description provided for @addChooseTitle.
  ///
  /// In it, this message translates to:
  /// **'Cosa vuoi aggiungere?'**
  String get addChooseTitle;

  /// No description provided for @addTrackerOption.
  ///
  /// In it, this message translates to:
  /// **'Tracker GPS'**
  String get addTrackerOption;

  /// No description provided for @addTrackerOptionSub.
  ///
  /// In it, this message translates to:
  /// **'Con il codice sull\'etichetta'**
  String get addTrackerOptionSub;

  /// No description provided for @phoneOption.
  ///
  /// In it, this message translates to:
  /// **'Questo telefono'**
  String get phoneOption;

  /// No description provided for @phoneOptionSub.
  ///
  /// In it, this message translates to:
  /// **'Condividi la posizione del telefono, senza hardware'**
  String get phoneOptionSub;

  /// No description provided for @vehicleOption.
  ///
  /// In it, this message translates to:
  /// **'Veicolo senza tracker'**
  String get vehicleOption;

  /// No description provided for @vehicleOptionSub.
  ///
  /// In it, this message translates to:
  /// **'La posizione arriva dal tuo telefono quando sei a bordo'**
  String get vehicleOptionSub;

  /// No description provided for @addVehicleTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo veicolo'**
  String get addVehicleTitle;

  /// No description provided for @addVehicle.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi veicolo'**
  String get addVehicle;

  /// No description provided for @vehicleIntro.
  ///
  /// In it, this message translates to:
  /// **'Quando condividi dal veicolo, il telefono registra i viaggi dell\'auto: costi, chilometri, scadenze e aree come con un tracker, senza comandi né allarmi.'**
  String get vehicleIntro;

  /// No description provided for @vehicleName.
  ///
  /// In it, this message translates to:
  /// **'Nome del veicolo'**
  String get vehicleName;

  /// No description provided for @vehicleKind.
  ///
  /// In it, this message translates to:
  /// **'Veicolo, posizione dal telefono'**
  String get vehicleKind;

  /// No description provided for @vehicleDriving.
  ///
  /// In it, this message translates to:
  /// **'In viaggio con il telefono'**
  String get vehicleDriving;

  /// No description provided for @shareAs.
  ///
  /// In it, this message translates to:
  /// **'Condividi come'**
  String get shareAs;

  /// No description provided for @shareAsPerson.
  ///
  /// In it, this message translates to:
  /// **'Me stesso'**
  String get shareAsPerson;

  /// No description provided for @shareAsPersonSub.
  ///
  /// In it, this message translates to:
  /// **'La tua posizione, vista dagli amici'**
  String get shareAsPersonSub;

  /// No description provided for @shareAsVehicleSub.
  ///
  /// In it, this message translates to:
  /// **'Viaggi e costi del veicolo; la tua posizione personale resta ferma'**
  String get shareAsVehicleSub;

  /// No description provided for @shareAsChanged.
  ///
  /// In it, this message translates to:
  /// **'Ora condividi come {name}'**
  String shareAsChanged(String name);

  /// No description provided for @phoneTitle.
  ///
  /// In it, this message translates to:
  /// **'Posizione del telefono'**
  String get phoneTitle;

  /// No description provided for @phoneIntro.
  ///
  /// In it, this message translates to:
  /// **'Senza un tracker puoi condividere la posizione di questo telefono con i tuoi amici. I dati sono meno completi di quelli di un tracker: niente satelliti, segnale o batteria dell\'auto, e la precisione dipende da GPS, Wi-Fi e rete del telefono.'**
  String get phoneIntro;

  /// No description provided for @phoneAndroidHint.
  ///
  /// In it, this message translates to:
  /// **'La condivisione continua in background con una notifica fissa, anche con l\'app chiusa. Si ferma con Interrompi, eliminando il telefono o uscendo dall\'account.'**
  String get phoneAndroidHint;

  /// No description provided for @phoneOnlyAndroid.
  ///
  /// In it, this message translates to:
  /// **'La posizione si condivide dall\'app Android: il browser non può inviarla in background.'**
  String get phoneOnlyAndroid;

  /// No description provided for @phoneBackgroundHint.
  ///
  /// In it, this message translates to:
  /// **'Per riprendere da sola dopo un riavvio del telefono, la condivisione ha bisogno della posizione consentita «Sempre».'**
  String get phoneBackgroundHint;

  /// No description provided for @phoneBackgroundAllow.
  ///
  /// In it, this message translates to:
  /// **'Consenti sempre'**
  String get phoneBackgroundAllow;

  /// No description provided for @phoneChannel.
  ///
  /// In it, this message translates to:
  /// **'Condivisione della posizione'**
  String get phoneChannel;

  /// No description provided for @phoneName.
  ///
  /// In it, this message translates to:
  /// **'Nome del telefono'**
  String get phoneName;

  /// No description provided for @phoneDefaultName.
  ///
  /// In it, this message translates to:
  /// **'Telefono di {name}'**
  String phoneDefaultName(String name);

  /// No description provided for @phoneStart.
  ///
  /// In it, this message translates to:
  /// **'Inizia a condividere'**
  String get phoneStart;

  /// No description provided for @phoneStop.
  ///
  /// In it, this message translates to:
  /// **'Interrompi'**
  String get phoneStop;

  /// No description provided for @kindPhoneBattery.
  ///
  /// In it, this message translates to:
  /// **'{device}: batteria al {n}%'**
  String kindPhoneBattery(String device, int n);

  /// No description provided for @notificationBodyPhoneBattery.
  ///
  /// In it, this message translates to:
  /// **'La posizione potrebbe interrompersi presto, ore {time}'**
  String notificationBodyPhoneBattery(String time);

  /// No description provided for @kindLongStop.
  ///
  /// In it, this message translates to:
  /// **'{device} è fermo da più di {h, plural, =1{un\'ora} other{{h} ore}}'**
  String kindLongStop(String device, int h);

  /// No description provided for @notificationBodyLongStop.
  ///
  /// In it, this message translates to:
  /// **'Fermo dalle {time}, fuori dalle tue aree'**
  String notificationBodyLongStop(String time);

  /// No description provided for @stopAlert.
  ///
  /// In it, this message translates to:
  /// **'Sosta prolungata'**
  String get stopAlert;

  /// No description provided for @stopAlertHint.
  ///
  /// In it, this message translates to:
  /// **'Ti avvisa se il dispositivo resta fermo più a lungo di così fuori dalle tue aree (casa, lavoro...). Ognuno sceglie il proprio avviso, anche chi riceve la condivisione.'**
  String get stopAlertHint;

  /// No description provided for @stopAlertOff.
  ///
  /// In it, this message translates to:
  /// **'Avviso disattivato'**
  String get stopAlertOff;

  /// No description provided for @batteryAlert.
  ///
  /// In it, this message translates to:
  /// **'Batteria bassa'**
  String get batteryAlert;

  /// No description provided for @batteryAlertAt.
  ///
  /// In it, this message translates to:
  /// **'Avvisa al {n}%'**
  String batteryAlertAt(int n);

  /// No description provided for @stopAlertAfter.
  ///
  /// In it, this message translates to:
  /// **'Avvisa dopo {h, plural, =1{1 ora} other{{h} ore}}'**
  String stopAlertAfter(int h);

  /// No description provided for @stopAlertAfterOne.
  ///
  /// In it, this message translates to:
  /// **'Avvisa dopo un\'ora'**
  String get stopAlertAfterOne;

  /// No description provided for @areaSchedule.
  ///
  /// In it, this message translates to:
  /// **'Solo in certi orari'**
  String get areaSchedule;

  /// No description provided for @areaScheduleHint.
  ///
  /// In it, this message translates to:
  /// **'Avvisa solo nei giorni e nelle ore scelti; se la fine è prima dell\'inizio, la fascia passa la mezzanotte.'**
  String get areaScheduleHint;

  /// No description provided for @areaFrom.
  ///
  /// In it, this message translates to:
  /// **'Dalle {time}'**
  String areaFrom(String time);

  /// No description provided for @areaTo.
  ///
  /// In it, this message translates to:
  /// **'Alle {time}'**
  String areaTo(String time);

  /// No description provided for @areaAllDay.
  ///
  /// In it, this message translates to:
  /// **'tutto il giorno'**
  String get areaAllDay;

  /// No description provided for @firmwareAvailable.
  ///
  /// In it, this message translates to:
  /// **'Disponibile il firmware {version}'**
  String firmwareAvailable(String version);

  /// No description provided for @firmwareInstall.
  ///
  /// In it, this message translates to:
  /// **'Installa'**
  String get firmwareInstall;

  /// No description provided for @firmwareInstallTitle.
  ///
  /// In it, this message translates to:
  /// **'Installare il firmware {version}?'**
  String firmwareInstallTitle(String version);

  /// No description provided for @firmwareInstallBody.
  ///
  /// In it, this message translates to:
  /// **'Il tracker scarica l\'aggiornamento alla prossima connessione ({mb} MB di dati della SIM), lo verifica e si riavvia. Se il nuovo firmware non riesce a collegarsi al server torna da solo a quello attuale.'**
  String firmwareInstallBody(String mb);

  /// No description provided for @firmwareWaiting.
  ///
  /// In it, this message translates to:
  /// **'Firmware {version}: in attesa della prossima connessione del tracker'**
  String firmwareWaiting(String version);

  /// No description provided for @firmwareDownloading.
  ///
  /// In it, this message translates to:
  /// **'Download del firmware {version} in corso'**
  String firmwareDownloading(String version);

  /// No description provided for @firmwareRebooting.
  ///
  /// In it, this message translates to:
  /// **'Firmware {version} installato, riavvio del tracker'**
  String firmwareRebooting(String version);

  /// No description provided for @firmwareDone.
  ///
  /// In it, this message translates to:
  /// **'Aggiornato al firmware {version}'**
  String firmwareDone(String version);

  /// No description provided for @firmwareNotApplied.
  ///
  /// In it, this message translates to:
  /// **'Il firmware {version} non si è avviato: il tracker è tornato alla versione precedente'**
  String firmwareNotApplied(String version);

  /// No description provided for @firmwareFailed.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento al firmware {version} non riuscito: riprova'**
  String firmwareFailed(String version);

  /// No description provided for @firmwareUpToDate.
  ///
  /// In it, this message translates to:
  /// **'Firmware {version}, aggiornato'**
  String firmwareUpToDate(String version);

  /// No description provided for @firmwareImages.
  ///
  /// In it, this message translates to:
  /// **'Firmware per gli aggiornamenti'**
  String get firmwareImages;

  /// No description provided for @firmwareImagesHint.
  ///
  /// In it, this message translates to:
  /// **'Si caricano dal server con npm run firmware; i proprietari li installano dalle impostazioni del tracker.'**
  String get firmwareImagesHint;

  /// No description provided for @firmwarePending.
  ///
  /// In it, this message translates to:
  /// **'{n} in corso'**
  String firmwarePending(int n);

  /// No description provided for @errFirmware.
  ///
  /// In it, this message translates to:
  /// **'Questo firmware non è adatto al tracker'**
  String get errFirmware;

  /// No description provided for @yourData.
  ///
  /// In it, this message translates to:
  /// **'I tuoi dati'**
  String get yourData;

  /// No description provided for @exportData.
  ///
  /// In it, this message translates to:
  /// **'Esporta i miei dati'**
  String get exportData;

  /// No description provided for @exportDataSub.
  ///
  /// In it, this message translates to:
  /// **'Profilo, accessi, amici, dispositivi con le loro posizioni, aree e notifiche in un file JSON'**
  String get exportDataSub;

  /// No description provided for @deleteAccount.
  ///
  /// In it, this message translates to:
  /// **'Elimina account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSub.
  ///
  /// In it, this message translates to:
  /// **'Elimina per sempre l\'account e i dati'**
  String get deleteAccountSub;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare l\'account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In it, this message translates to:
  /// **'Vengono eliminati per sempre: i telefoni e le posizioni di tutti i tuoi dispositivi, le condivisioni, gli amici, le aree e le notifiche. I tracker tornano liberi e si possono abbinare di nuovo con il codice dell\'etichetta. Prima puoi esportare i tuoi dati.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountEmail.
  ///
  /// In it, this message translates to:
  /// **'Scrivi {email} per confermare'**
  String deleteAccountEmail(String email);

  /// No description provided for @errEmailMismatch.
  ///
  /// In it, this message translates to:
  /// **'L\'email non corrisponde'**
  String get errEmailMismatch;

  /// No description provided for @errLastAdmin.
  ///
  /// In it, this message translates to:
  /// **'Sei l\'unico amministratore: nomina prima un altro amministratore'**
  String get errLastAdmin;

  /// No description provided for @exportPeriod.
  ///
  /// In it, this message translates to:
  /// **'Esporta il periodo'**
  String get exportPeriod;

  /// No description provided for @exportHint.
  ///
  /// In it, this message translates to:
  /// **'GPX: un tracciato per viaggio. CSV: tutti i punti.'**
  String get exportHint;

  /// No description provided for @phonePauseHour.
  ///
  /// In it, this message translates to:
  /// **'Pausa 1 ora'**
  String get phonePauseHour;

  /// No description provided for @phoneResume.
  ///
  /// In it, this message translates to:
  /// **'Riprendi'**
  String get phoneResume;

  /// No description provided for @phonePausedUntil.
  ///
  /// In it, this message translates to:
  /// **'In pausa fino alle {time}'**
  String phonePausedUntil(String time);

  /// No description provided for @battery.
  ///
  /// In it, this message translates to:
  /// **'Batteria {n}%'**
  String battery(int n);

  /// No description provided for @phoneSharing.
  ///
  /// In it, this message translates to:
  /// **'Stai condividendo la posizione di questo telefono'**
  String get phoneSharing;

  /// No description provided for @phoneLastFix.
  ///
  /// In it, this message translates to:
  /// **'Ultima posizione {time} · ±{meters} m'**
  String phoneLastFix(String time, String meters);

  /// No description provided for @phoneWaitingFix.
  ///
  /// In it, this message translates to:
  /// **'In attesa della prima posizione…'**
  String get phoneWaitingFix;

  /// No description provided for @phoneQueued.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 posizione da inviare} other{{n} posizioni da inviare}}'**
  String phoneQueued(int n);

  /// No description provided for @phoneOpenDevice.
  ///
  /// In it, this message translates to:
  /// **'Condivisione con gli amici e aree'**
  String get phoneOpenDevice;

  /// No description provided for @phoneLocationOff.
  ///
  /// In it, this message translates to:
  /// **'Attiva la localizzazione del telefono'**
  String get phoneLocationOff;

  /// No description provided for @phoneDenied.
  ///
  /// In it, this message translates to:
  /// **'Permesso di posizione negato'**
  String get phoneDenied;

  /// No description provided for @phoneDeniedForever.
  ///
  /// In it, this message translates to:
  /// **'Permesso di posizione negato: abilitalo dalle impostazioni del telefono'**
  String get phoneDeniedForever;

  /// No description provided for @phoneNotificationTitle.
  ///
  /// In it, this message translates to:
  /// **'Posizione condivisa'**
  String get phoneNotificationTitle;

  /// No description provided for @phoneNotificationText.
  ///
  /// In it, this message translates to:
  /// **'L\'app sta inviando la posizione di questo telefono'**
  String get phoneNotificationText;

  /// No description provided for @phoneGone.
  ///
  /// In it, this message translates to:
  /// **'Il telefono è stato eliminato: condivisione interrotta'**
  String get phoneGone;

  /// No description provided for @accuracyMeters.
  ///
  /// In it, this message translates to:
  /// **'±{meters} m'**
  String accuracyMeters(String meters);

  /// No description provided for @sharingActive.
  ///
  /// In it, this message translates to:
  /// **'Condivisione attiva'**
  String get sharingActive;

  /// No description provided for @removePhone.
  ///
  /// In it, this message translates to:
  /// **'Elimina il telefono'**
  String get removePhone;

  /// No description provided for @removePhoneSub.
  ///
  /// In it, this message translates to:
  /// **'Smette di condividere la posizione'**
  String get removePhoneSub;

  /// No description provided for @removePhoneTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il telefono?'**
  String get removePhoneTitle;

  /// No description provided for @removePhoneBody.
  ///
  /// In it, this message translates to:
  /// **'Storico, aree, condivisioni e notifiche vengono cancellati.'**
  String get removePhoneBody;

  /// No description provided for @removeVehicle.
  ///
  /// In it, this message translates to:
  /// **'Elimina il veicolo'**
  String get removeVehicle;

  /// No description provided for @removeVehicleSub.
  ///
  /// In it, this message translates to:
  /// **'Con viaggi, costi e scadenze'**
  String get removeVehicleSub;

  /// No description provided for @removeVehicleTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il veicolo?'**
  String get removeVehicleTitle;

  /// No description provided for @removeVehicleBody.
  ///
  /// In it, this message translates to:
  /// **'Storico, costi, scadenze, aree e condivisioni vengono cancellati.'**
  String get removeVehicleBody;

  /// No description provided for @friends.
  ///
  /// In it, this message translates to:
  /// **'Amici'**
  String get friends;

  /// No description provided for @friendsSub.
  ///
  /// In it, this message translates to:
  /// **'Il tuo codice e le persone con cui condividere'**
  String get friendsSub;

  /// No description provided for @friendsHint.
  ///
  /// In it, this message translates to:
  /// **'Gli utenti non si vedono tra loro: uno dei due inserisce o inquadra il codice dell\'altro, che riceve una richiesta di amicizia da accettare. Puoi condividere i dispositivi solo con gli amici.'**
  String get friendsHint;

  /// No description provided for @friendRequested.
  ///
  /// In it, this message translates to:
  /// **'Richiesta inviata a {name}: diventerete amici quando la accetta'**
  String friendRequested(String name);

  /// No description provided for @friendRequestReceived.
  ///
  /// In it, this message translates to:
  /// **'{name} ti ha inviato una richiesta di amicizia'**
  String friendRequestReceived(String name);

  /// No description provided for @requestsReceived.
  ///
  /// In it, this message translates to:
  /// **'Richieste ricevute'**
  String get requestsReceived;

  /// No description provided for @requestsSent.
  ///
  /// In it, this message translates to:
  /// **'Richieste inviate'**
  String get requestsSent;

  /// No description provided for @requestedOn.
  ///
  /// In it, this message translates to:
  /// **'Richiesta del {date}'**
  String requestedOn(String date);

  /// No description provided for @requestWaiting.
  ///
  /// In it, this message translates to:
  /// **'In attesa di risposta'**
  String get requestWaiting;

  /// No description provided for @accept.
  ///
  /// In it, this message translates to:
  /// **'Accetta'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In it, this message translates to:
  /// **'Rifiuta'**
  String get decline;

  /// No description provided for @withdraw.
  ///
  /// In it, this message translates to:
  /// **'Ritira'**
  String get withdraw;

  /// No description provided for @errTooManyRequests.
  ///
  /// In it, this message translates to:
  /// **'Hai già 20 richieste in attesa: aspetta una risposta o ritirane qualcuna'**
  String get errTooManyRequests;

  /// No description provided for @yourCode.
  ///
  /// In it, this message translates to:
  /// **'Il tuo codice'**
  String get yourCode;

  /// No description provided for @codeCopied.
  ///
  /// In it, this message translates to:
  /// **'Codice copiato'**
  String get codeCopied;

  /// No description provided for @newCode.
  ///
  /// In it, this message translates to:
  /// **'Nuovo codice'**
  String get newCode;

  /// No description provided for @newCodeTitle.
  ///
  /// In it, this message translates to:
  /// **'Generare un nuovo codice?'**
  String get newCodeTitle;

  /// No description provided for @newCodeBody.
  ///
  /// In it, this message translates to:
  /// **'Il codice attuale smette di funzionare. Gli amici che hai restano.'**
  String get newCodeBody;

  /// No description provided for @addFriend.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi un amico'**
  String get addFriend;

  /// No description provided for @friendCode.
  ///
  /// In it, this message translates to:
  /// **'Codice dell\'amico'**
  String get friendCode;

  /// No description provided for @scanFriend.
  ///
  /// In it, this message translates to:
  /// **'Inquadra il QR dell\'amico'**
  String get scanFriend;

  /// No description provided for @friendCodeUnknown.
  ///
  /// In it, this message translates to:
  /// **'Nessun utente con questo codice'**
  String get friendCodeUnknown;

  /// No description provided for @friendAdded.
  ///
  /// In it, this message translates to:
  /// **'{name} è ora tuo amico'**
  String friendAdded(String name);

  /// No description provided for @friendAddedYou.
  ///
  /// In it, this message translates to:
  /// **'{name} ha accettato la tua richiesta di amicizia'**
  String friendAddedYou(String name);

  /// No description provided for @noFriends.
  ///
  /// In it, this message translates to:
  /// **'Nessun amico ancora'**
  String get noFriends;

  /// No description provided for @friendsSince.
  ///
  /// In it, this message translates to:
  /// **'Amici dal {date}'**
  String friendsSince(String date);

  /// No description provided for @removeFriend.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get removeFriend;

  /// No description provided for @removeFriendTitle.
  ///
  /// In it, this message translates to:
  /// **'Rimuovere {name} dagli amici?'**
  String removeFriendTitle(String name);

  /// No description provided for @removeFriendBody.
  ///
  /// In it, this message translates to:
  /// **'Le condivisioni tra voi due terminano, in entrambe le direzioni.'**
  String get removeFriendBody;

  /// No description provided for @friendRemoved.
  ///
  /// In it, this message translates to:
  /// **'Amico rimosso'**
  String get friendRemoved;

  /// No description provided for @filterMine.
  ///
  /// In it, this message translates to:
  /// **'Miei'**
  String get filterMine;

  /// No description provided for @filterShared.
  ///
  /// In it, this message translates to:
  /// **'Condivisi con me'**
  String get filterShared;

  /// No description provided for @filterMoving.
  ///
  /// In it, this message translates to:
  /// **'In movimento'**
  String get filterMoving;

  /// No description provided for @filterParked.
  ///
  /// In it, this message translates to:
  /// **'Fermi'**
  String get filterParked;

  /// No description provided for @filterOffline.
  ///
  /// In it, this message translates to:
  /// **'Non raggiungibili'**
  String get filterOffline;

  /// No description provided for @filterTrackers.
  ///
  /// In it, this message translates to:
  /// **'Veicoli'**
  String get filterTrackers;

  /// No description provided for @filterPhones.
  ///
  /// In it, this message translates to:
  /// **'Telefoni'**
  String get filterPhones;

  /// No description provided for @filterAllOwners.
  ///
  /// In it, this message translates to:
  /// **'Tutti i proprietari'**
  String get filterAllOwners;

  /// No description provided for @filterOwner.
  ///
  /// In it, this message translates to:
  /// **'Di {name}'**
  String filterOwner(String name);

  /// No description provided for @searchDevices.
  ///
  /// In it, this message translates to:
  /// **'Cerca per nome'**
  String get searchDevices;

  /// No description provided for @shownCount.
  ///
  /// In it, this message translates to:
  /// **'{n} di {total}'**
  String shownCount(int n, int total);

  /// No description provided for @fitAll.
  ///
  /// In it, this message translates to:
  /// **'Inquadra quelli filtrati'**
  String get fitAll;

  /// No description provided for @noMatch.
  ///
  /// In it, this message translates to:
  /// **'Nessun dispositivo con questi filtri'**
  String get noMatch;

  /// No description provided for @resetFilters.
  ///
  /// In it, this message translates to:
  /// **'Azzera i filtri'**
  String get resetFilters;

  /// No description provided for @filters.
  ///
  /// In it, this message translates to:
  /// **'Filtri'**
  String get filters;

  /// No description provided for @kindBatteryHealth.
  ///
  /// In it, this message translates to:
  /// **'Batteria dell\'auto da controllare'**
  String get kindBatteryHealth;

  /// No description provided for @notificationBodyBatteryHealth.
  ///
  /// In it, this message translates to:
  /// **'{device}: tensione a riposo media {v} V'**
  String notificationBodyBatteryHealth(String device, String v);

  /// No description provided for @kindMaintenance.
  ///
  /// In it, this message translates to:
  /// **'Scadenze dell\'auto'**
  String get kindMaintenance;

  /// No description provided for @maintenanceDueTitle.
  ///
  /// In it, this message translates to:
  /// **'Scadenza: {name}'**
  String maintenanceDueTitle(String name);

  /// No description provided for @maintenanceSoonTitle.
  ///
  /// In it, this message translates to:
  /// **'Scadenza vicina: {name}'**
  String maintenanceSoonTitle(String name);

  /// No description provided for @inDays.
  ///
  /// In it, this message translates to:
  /// **'tra {n, plural, =1{1 giorno} other{{n} giorni}}'**
  String inDays(int n);

  /// No description provided for @today.
  ///
  /// In it, this message translates to:
  /// **'oggi'**
  String get today;

  /// No description provided for @overdueDays.
  ///
  /// In it, this message translates to:
  /// **'scaduta da {n, plural, =1{1 giorno} other{{n} giorni}}'**
  String overdueDays(int n);

  /// No description provided for @inKm.
  ///
  /// In it, this message translates to:
  /// **'tra {km} km'**
  String inKm(String km);

  /// No description provided for @kmOver.
  ///
  /// In it, this message translates to:
  /// **'superata di {km} km'**
  String kmOver(String km);

  /// No description provided for @orJoin.
  ///
  /// In it, this message translates to:
  /// **' o '**
  String get orJoin;

  /// No description provided for @mkService.
  ///
  /// In it, this message translates to:
  /// **'Tagliando'**
  String get mkService;

  /// No description provided for @mkInspection.
  ///
  /// In it, this message translates to:
  /// **'Revisione'**
  String get mkInspection;

  /// No description provided for @mkInsurance.
  ///
  /// In it, this message translates to:
  /// **'Assicurazione'**
  String get mkInsurance;

  /// No description provided for @mkTax.
  ///
  /// In it, this message translates to:
  /// **'Bollo'**
  String get mkTax;

  /// No description provided for @mkTyres.
  ///
  /// In it, this message translates to:
  /// **'Cambio gomme'**
  String get mkTyres;

  /// No description provided for @mkOther.
  ///
  /// In it, this message translates to:
  /// **'Personalizzata'**
  String get mkOther;

  /// No description provided for @maintenance.
  ///
  /// In it, this message translates to:
  /// **'Scadenze e manutenzione'**
  String get maintenance;

  /// No description provided for @maintenanceHint.
  ///
  /// In it, this message translates to:
  /// **'Tagliando a km, revisione, assicurazione e bollo a data, o scadenze personalizzate: ti avvisa prima della scadenza.'**
  String get maintenanceHint;

  /// No description provided for @odometer.
  ///
  /// In it, this message translates to:
  /// **'Contachilometri'**
  String get odometer;

  /// No description provided for @odometerUnset.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la lettura del contachilometri per le scadenze a km'**
  String get odometerUnset;

  /// No description provided for @odometerValue.
  ///
  /// In it, this message translates to:
  /// **'{km} km'**
  String odometerValue(String km);

  /// No description provided for @odometerHint.
  ///
  /// In it, this message translates to:
  /// **'Lettura attuale del cruscotto: poi si aggiorna da sola con i km dei viaggi. Puoi correggerla quando vuoi, ad esempio se il tracker è rimasto spento.'**
  String get odometerHint;

  /// No description provided for @addDeadline.
  ///
  /// In it, this message translates to:
  /// **'Nuova scadenza'**
  String get addDeadline;

  /// No description provided for @editDeadline.
  ///
  /// In it, this message translates to:
  /// **'Modifica scadenza'**
  String get editDeadline;

  /// No description provided for @deadlineKind.
  ///
  /// In it, this message translates to:
  /// **'Tipo'**
  String get deadlineKind;

  /// No description provided for @deadlineTitle.
  ///
  /// In it, this message translates to:
  /// **'Descrizione (facoltativa)'**
  String get deadlineTitle;

  /// No description provided for @deadlineTitleRequired.
  ///
  /// In it, this message translates to:
  /// **'Descrizione (es. bollino blu, estintore)'**
  String get deadlineTitleRequired;

  /// No description provided for @deadlineNeedsTitle.
  ///
  /// In it, this message translates to:
  /// **'Scrivi una descrizione per la scadenza personalizzata'**
  String get deadlineNeedsTitle;

  /// No description provided for @deadlineDate.
  ///
  /// In it, this message translates to:
  /// **'Data di scadenza'**
  String get deadlineDate;

  /// No description provided for @deadlineNoDate.
  ///
  /// In it, this message translates to:
  /// **'Nessuna data'**
  String get deadlineNoDate;

  /// No description provided for @deadlineKm.
  ///
  /// In it, this message translates to:
  /// **'Scadenza a km'**
  String get deadlineKm;

  /// No description provided for @deadlineEveryMonths.
  ///
  /// In it, this message translates to:
  /// **'Si ripete ogni (mesi)'**
  String get deadlineEveryMonths;

  /// No description provided for @deadlineEveryKm.
  ///
  /// In it, this message translates to:
  /// **'Si ripete ogni (km)'**
  String get deadlineEveryKm;

  /// No description provided for @deadlineRemindDays.
  ///
  /// In it, this message translates to:
  /// **'Avvisa giorni prima'**
  String get deadlineRemindDays;

  /// No description provided for @deadlineRemindKm.
  ///
  /// In it, this message translates to:
  /// **'Avvisa km prima'**
  String get deadlineRemindKm;

  /// No description provided for @deadlineNote.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get deadlineNote;

  /// No description provided for @deadlineNeedsDue.
  ///
  /// In it, this message translates to:
  /// **'Indica una data o i km'**
  String get deadlineNeedsDue;

  /// No description provided for @deadlineDone.
  ///
  /// In it, this message translates to:
  /// **'Fatto'**
  String get deadlineDone;

  /// No description provided for @deadlineDoneTitle.
  ///
  /// In it, this message translates to:
  /// **'Segna come fatto: {name}'**
  String deadlineDoneTitle(String name);

  /// No description provided for @deadlineDoneKm.
  ///
  /// In it, this message translates to:
  /// **'Km al momento'**
  String get deadlineDoneKm;

  /// No description provided for @deadlineDoneHint.
  ///
  /// In it, this message translates to:
  /// **'Le scadenze ricorrenti si spostano in avanti, le altre si chiudono.'**
  String get deadlineDoneHint;

  /// No description provided for @deadlineEvery.
  ///
  /// In it, this message translates to:
  /// **'ogni {text}'**
  String deadlineEvery(String text);

  /// No description provided for @monthsShort.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 mese} other{{n} mesi}}'**
  String monthsShort(int n);

  /// No description provided for @noDeadlines.
  ///
  /// In it, this message translates to:
  /// **'Nessuna scadenza'**
  String get noDeadlines;

  /// No description provided for @maintenanceLog.
  ///
  /// In it, this message translates to:
  /// **'Fatti'**
  String get maintenanceLog;

  /// No description provided for @deleteDeadline.
  ///
  /// In it, this message translates to:
  /// **'Eliminare la scadenza?'**
  String get deleteDeadline;

  /// No description provided for @invalidNumber.
  ///
  /// In it, this message translates to:
  /// **'Numero non valido'**
  String get invalidNumber;

  /// No description provided for @trends.
  ///
  /// In it, this message translates to:
  /// **'Statistiche nel tempo'**
  String get trends;

  /// No description provided for @trendsMonths.
  ///
  /// In it, this message translates to:
  /// **'12 mesi'**
  String get trendsMonths;

  /// No description provided for @trendsWeeks.
  ///
  /// In it, this message translates to:
  /// **'26 settimane'**
  String get trendsWeeks;

  /// No description provided for @trendsKm.
  ///
  /// In it, this message translates to:
  /// **'Km percorsi'**
  String get trendsKm;

  /// No description provided for @trendsKmSplit.
  ///
  /// In it, this message translates to:
  /// **'Lavoro {work} km · personali {own} km nel periodo'**
  String trendsKmSplit(String work, String own);

  /// No description provided for @trendsDriving.
  ///
  /// In it, this message translates to:
  /// **'Ore di guida'**
  String get trendsDriving;

  /// No description provided for @trendsTrips.
  ///
  /// In it, this message translates to:
  /// **'Viaggi'**
  String get trendsTrips;

  /// No description provided for @trendsVoltage.
  ///
  /// In it, this message translates to:
  /// **'Tensione a riposo della batteria'**
  String get trendsVoltage;

  /// No description provided for @trendsVoltageSub.
  ///
  /// In it, this message translates to:
  /// **'Media dei giorni, a motore spento da almeno 2 ore'**
  String get trendsVoltageSub;

  /// No description provided for @trendsSim.
  ///
  /// In it, this message translates to:
  /// **'Dati sulla SIM'**
  String get trendsSim;

  /// No description provided for @trendsAlarms.
  ///
  /// In it, this message translates to:
  /// **'Allarmi'**
  String get trendsAlarms;

  /// No description provided for @batteryHealth.
  ///
  /// In it, this message translates to:
  /// **'Salute della batteria dell\'auto'**
  String get batteryHealth;

  /// No description provided for @batteryGood.
  ///
  /// In it, this message translates to:
  /// **'Buona: {v} V a riposo'**
  String batteryGood(String v);

  /// No description provided for @batteryFair.
  ///
  /// In it, this message translates to:
  /// **'Da tenere d\'occhio: {v} V a riposo'**
  String batteryFair(String v);

  /// No description provided for @batteryLow.
  ///
  /// In it, this message translates to:
  /// **'Debole: {v} V a riposo, falla controllare'**
  String batteryLow(String v);

  /// No description provided for @batteryUnknown.
  ///
  /// In it, this message translates to:
  /// **'Servono alcuni giorni di soste per valutarla'**
  String get batteryUnknown;

  /// No description provided for @batteryTrend.
  ///
  /// In it, this message translates to:
  /// **'Andamento: {v} V al mese'**
  String batteryTrend(String v);

  /// No description provided for @tripPurpose.
  ///
  /// In it, this message translates to:
  /// **'Tipo di viaggio'**
  String get tripPurpose;

  /// No description provided for @purposeBusiness.
  ///
  /// In it, this message translates to:
  /// **'Lavoro'**
  String get purposeBusiness;

  /// No description provided for @purposePersonal.
  ///
  /// In it, this message translates to:
  /// **'Personale'**
  String get purposePersonal;

  /// No description provided for @purposeNone.
  ///
  /// In it, this message translates to:
  /// **'Non indicato'**
  String get purposeNone;

  /// No description provided for @tripNote.
  ///
  /// In it, this message translates to:
  /// **'Nota'**
  String get tripNote;

  /// No description provided for @logbook.
  ///
  /// In it, this message translates to:
  /// **'Registro viaggi del mese'**
  String get logbook;

  /// No description provided for @logbookHint.
  ///
  /// In it, this message translates to:
  /// **'CSV con viaggi, tipo, note e costi, totali lavoro e personali'**
  String get logbookHint;

  /// No description provided for @walkTo.
  ///
  /// In it, this message translates to:
  /// **'Raggiungi a piedi'**
  String get walkTo;

  /// No description provided for @openFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il collegamento'**
  String get openFailed;

  /// No description provided for @tripCosts.
  ///
  /// In it, this message translates to:
  /// **'Costi dei viaggi'**
  String get tripCosts;

  /// No description provided for @costsIntro.
  ///
  /// In it, this message translates to:
  /// **'Con consumo, prezzo del carburante e usura ogni viaggio mostra quanto è costato e il registro viaggi del mese aggiunge le colonne dei costi.'**
  String get costsIntro;

  /// No description provided for @fuelType.
  ///
  /// In it, this message translates to:
  /// **'Carburante'**
  String get fuelType;

  /// No description provided for @fuelPetrol.
  ///
  /// In it, this message translates to:
  /// **'Benzina'**
  String get fuelPetrol;

  /// No description provided for @fuelDiesel.
  ///
  /// In it, this message translates to:
  /// **'Gasolio'**
  String get fuelDiesel;

  /// No description provided for @fuelLpg.
  ///
  /// In it, this message translates to:
  /// **'GPL'**
  String get fuelLpg;

  /// No description provided for @fuelOther.
  ///
  /// In it, this message translates to:
  /// **'Altro / non indicato'**
  String get fuelOther;

  /// No description provided for @fuelPriceAuto.
  ///
  /// In it, this message translates to:
  /// **'Prezzo dalla media nazionale'**
  String get fuelPriceAuto;

  /// No description provided for @fuelPriceAutoHint.
  ///
  /// In it, this message translates to:
  /// **'Ogni settimana il prezzo medio rilevato dal Ministero dell\'Ambiente (MASE) viene aggiunto allo storico'**
  String get fuelPriceAutoHint;

  /// No description provided for @fuelPriceAutoNeedsType.
  ///
  /// In it, this message translates to:
  /// **'Scegli il carburante per usare la media nazionale'**
  String get fuelPriceAutoNeedsType;

  /// No description provided for @nationalAverage.
  ///
  /// In it, this message translates to:
  /// **'Media nazionale {fuel}: {price}/l'**
  String nationalAverage(String fuel, String price);

  /// No description provided for @nationalAverageWeek.
  ///
  /// In it, this message translates to:
  /// **'Rilevazione MASE della settimana del {date}'**
  String nationalAverageWeek(String date);

  /// No description provided for @useAverage.
  ///
  /// In it, this message translates to:
  /// **'Usa'**
  String get useAverage;

  /// No description provided for @ratesHint.
  ///
  /// In it, this message translates to:
  /// **'Prezzo, consumo e usura possono cambiare nel tempo: ogni valore vale dalla sua data fino al successivo e ogni viaggio usa i valori del giorno in cui è stato fatto.'**
  String get ratesHint;

  /// No description provided for @addValue.
  ///
  /// In it, this message translates to:
  /// **'Nuovo valore'**
  String get addValue;

  /// No description provided for @rateNow.
  ///
  /// In it, this message translates to:
  /// **'Attuale: {value}'**
  String rateNow(String value);

  /// No description provided for @rateUnset.
  ///
  /// In it, this message translates to:
  /// **'Nessun valore inserito'**
  String get rateUnset;

  /// No description provided for @rateTrend.
  ///
  /// In it, this message translates to:
  /// **'Andamento'**
  String get rateTrend;

  /// No description provided for @errTooManyRates.
  ///
  /// In it, this message translates to:
  /// **'Troppi valori nello storico: eliminane qualcuno'**
  String get errTooManyRates;

  /// No description provided for @vehicleModel.
  ///
  /// In it, this message translates to:
  /// **'Modello del veicolo'**
  String get vehicleModel;

  /// No description provided for @vehicleModelHint.
  ///
  /// In it, this message translates to:
  /// **'es. Fiat Panda 1.2 benzina'**
  String get vehicleModelHint;

  /// No description provided for @consumption.
  ///
  /// In it, this message translates to:
  /// **'Consumo'**
  String get consumption;

  /// No description provided for @consumptionUnit.
  ///
  /// In it, this message translates to:
  /// **'Unità del consumo'**
  String get consumptionUnit;

  /// No description provided for @fuelPrices.
  ///
  /// In it, this message translates to:
  /// **'Prezzo del carburante'**
  String get fuelPrices;

  /// No description provided for @validFrom.
  ///
  /// In it, this message translates to:
  /// **'dal {date}'**
  String validFrom(String date);

  /// No description provided for @priceDate.
  ///
  /// In it, this message translates to:
  /// **'Cambia data'**
  String get priceDate;

  /// No description provided for @wearPerKm.
  ///
  /// In it, this message translates to:
  /// **'Usura del veicolo'**
  String get wearPerKm;

  /// No description provided for @wearHint.
  ///
  /// In it, this message translates to:
  /// **'Pneumatici, manutenzione e svalutazione per km, senza il carburante: dalle tabelle ACI del modello o una tua stima'**
  String get wearHint;

  /// No description provided for @extraData.
  ///
  /// In it, this message translates to:
  /// **'Dati aggiuntivi'**
  String get extraData;

  /// No description provided for @extraIntro.
  ///
  /// In it, this message translates to:
  /// **'Dati letti dal tracker da un\'altra scheda del veicolo, mostrati così come arrivano.'**
  String get extraIntro;

  /// No description provided for @extraEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato aggiuntivo ricevuto'**
  String get extraEmpty;

  /// No description provided for @extraLatest.
  ///
  /// In it, this message translates to:
  /// **'Valori più recenti'**
  String get extraLatest;

  /// No description provided for @extraReadings.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 lettura} other{{n} letture}}'**
  String extraReadings(int n);

  /// No description provided for @extraFields.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 campo} other{{n} campi}}'**
  String extraFields(int n);

  /// No description provided for @autoUpdate.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti automatici'**
  String get autoUpdate;

  /// No description provided for @autoUpdateNever.
  ///
  /// In it, this message translates to:
  /// **'Questo firmware non controlla gli aggiornamenti: i firmware personalizzati li hanno disattivati (AUTO_UPDATE 0)'**
  String get autoUpdateNever;

  /// No description provided for @autoUpdateChecked.
  ///
  /// In it, this message translates to:
  /// **'Il tracker controlla ogni giorno e installa le versioni ufficiali (circa 1,3 MB di SIM ciascuna) · ultimo controllo {time}'**
  String autoUpdateChecked(String time);

  /// No description provided for @firmwareAutomatic.
  ///
  /// In it, this message translates to:
  /// **'automatico'**
  String get firmwareAutomatic;

  /// No description provided for @kindFirmware.
  ///
  /// In it, this message translates to:
  /// **'Nuovo firmware'**
  String get kindFirmware;

  /// No description provided for @firmwareNewTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo firmware {version}'**
  String firmwareNewTitle(String version);

  /// No description provided for @firmwareNewAutomatic.
  ///
  /// In it, this message translates to:
  /// **'{device} lo installerà da solo entro un giorno'**
  String firmwareNewAutomatic(String device);

  /// No description provided for @firmwareNewManual.
  ///
  /// In it, this message translates to:
  /// **'Installalo su {device} dalla pagina del dispositivo'**
  String firmwareNewManual(String device);

  /// No description provided for @appUpdateAvailable.
  ///
  /// In it, this message translates to:
  /// **'È disponibile la versione {version} dell\'app'**
  String appUpdateAvailable(String version);

  /// No description provided for @download.
  ///
  /// In it, this message translates to:
  /// **'Scarica'**
  String get download;

  /// No description provided for @searchAci.
  ///
  /// In it, this message translates to:
  /// **'Cerca il costo chilometrico ACI'**
  String get searchAci;

  /// No description provided for @costPerKm.
  ///
  /// In it, this message translates to:
  /// **'Costo stimato: {cost}/km'**
  String costPerKm(String cost);

  /// No description provided for @costPerKmUnset.
  ///
  /// In it, this message translates to:
  /// **'Inserisci consumo e prezzo o l\'usura per calcolare i costi'**
  String get costPerKmUnset;

  /// No description provided for @costsSaved.
  ///
  /// In it, this message translates to:
  /// **'Costi salvati'**
  String get costsSaved;

  /// No description provided for @valueRange.
  ///
  /// In it, this message translates to:
  /// **'Valore tra {min} e {max}'**
  String valueRange(String min, String max);

  /// No description provided for @costFuel.
  ///
  /// In it, this message translates to:
  /// **'carburante {cost}'**
  String costFuel(String cost);

  /// No description provided for @costWear.
  ///
  /// In it, this message translates to:
  /// **'usura {cost}'**
  String costWear(String cost);

  /// No description provided for @kpiCost.
  ///
  /// In it, this message translates to:
  /// **'Costo stimato'**
  String get kpiCost;

  /// No description provided for @kpiFuel.
  ///
  /// In it, this message translates to:
  /// **'Carburante'**
  String get kpiFuel;

  /// No description provided for @backups.
  ///
  /// In it, this message translates to:
  /// **'Backup del database'**
  String get backups;

  /// No description provided for @backupLast.
  ///
  /// In it, this message translates to:
  /// **'Ultimo: {time} · {size}'**
  String backupLast(String time, String size);

  /// No description provided for @backupFiles.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 copia} other{{n} copie}}, {size} in totale'**
  String backupFiles(int n, String size);

  /// No description provided for @backupOffsite.
  ///
  /// In it, this message translates to:
  /// **'Copia fuori dal server: {time}'**
  String backupOffsite(String time);

  /// No description provided for @backupNoOffsite.
  ///
  /// In it, this message translates to:
  /// **'Nessuna copia fuori dal server'**
  String get backupNoOffsite;

  /// No description provided for @backupStale.
  ///
  /// In it, this message translates to:
  /// **'Nessun backup riuscito nelle ultime 26 ore'**
  String get backupStale;

  /// No description provided for @navDashboards.
  ///
  /// In it, this message translates to:
  /// **'Dashboard'**
  String get navDashboards;

  /// No description provided for @errTooManyDashboards.
  ///
  /// In it, this message translates to:
  /// **'Hai già il numero massimo di dashboard (20)'**
  String get errTooManyDashboards;

  /// No description provided for @dashboardNew.
  ///
  /// In it, this message translates to:
  /// **'Nuova dashboard'**
  String get dashboardNew;

  /// No description provided for @dashboardName.
  ///
  /// In it, this message translates to:
  /// **'Nome della dashboard'**
  String get dashboardName;

  /// No description provided for @dashboardEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessuna dashboard. Creane una vuota o parti da un modello: potrai cambiare ogni widget.'**
  String get dashboardEmpty;

  /// No description provided for @dashboardNoWidgets.
  ///
  /// In it, this message translates to:
  /// **'Dashboard vuota: aggiungi un widget con Modifica.'**
  String get dashboardNoWidgets;

  /// No description provided for @templateBlank.
  ///
  /// In it, this message translates to:
  /// **'Vuota'**
  String get templateBlank;

  /// No description provided for @templateOverview.
  ///
  /// In it, this message translates to:
  /// **'Panoramica dei veicoli'**
  String get templateOverview;

  /// No description provided for @templateDiagnostics.
  ///
  /// In it, this message translates to:
  /// **'Diagnostica dei tracker'**
  String get templateDiagnostics;

  /// No description provided for @dashboardEdit.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get dashboardEdit;

  /// No description provided for @dashboardRename.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get dashboardRename;

  /// No description provided for @dashboardDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina dashboard'**
  String get dashboardDelete;

  /// No description provided for @dashboardDeleteBody.
  ///
  /// In it, this message translates to:
  /// **'Eliminare la dashboard «{name}»? I dati dei veicoli restano.'**
  String dashboardDeleteBody(String name);

  /// No description provided for @dashboardSaved.
  ///
  /// In it, this message translates to:
  /// **'Dashboard salvata'**
  String get dashboardSaved;

  /// No description provided for @dashboardDiscard.
  ///
  /// In it, this message translates to:
  /// **'Uscire senza salvare le modifiche?'**
  String get dashboardDiscard;

  /// No description provided for @discard.
  ///
  /// In it, this message translates to:
  /// **'Esci senza salvare'**
  String get discard;

  /// No description provided for @dashboardPeriod.
  ///
  /// In it, this message translates to:
  /// **'Periodo'**
  String get dashboardPeriod;

  /// No description provided for @widgetAdd.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi widget'**
  String get widgetAdd;

  /// No description provided for @widgetEdit.
  ///
  /// In it, this message translates to:
  /// **'Modifica widget'**
  String get widgetEdit;

  /// No description provided for @widgetDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Duplica'**
  String get widgetDuplicate;

  /// No description provided for @widgetRemove.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get widgetRemove;

  /// No description provided for @widgetMetric.
  ///
  /// In it, this message translates to:
  /// **'Dato'**
  String get widgetMetric;

  /// No description provided for @widgetExtraKey.
  ///
  /// In it, this message translates to:
  /// **'Campo dei dati aggiuntivi'**
  String get widgetExtraKey;

  /// No description provided for @widgetExtraKeyHint.
  ///
  /// In it, this message translates to:
  /// **'Il nome come appare in Dati aggiuntivi, es. rpm'**
  String get widgetExtraKeyHint;

  /// No description provided for @widgetView.
  ///
  /// In it, this message translates to:
  /// **'Visualizzazione'**
  String get widgetView;

  /// No description provided for @widgetDevices.
  ///
  /// In it, this message translates to:
  /// **'Veicoli'**
  String get widgetDevices;

  /// No description provided for @widgetAllDevices.
  ///
  /// In it, this message translates to:
  /// **'Tutti i miei veicoli attivi'**
  String get widgetAllDevices;

  /// No description provided for @widgetAllDevicesSub.
  ///
  /// In it, this message translates to:
  /// **'Anche quelli aggiunti in futuro, non gli archiviati'**
  String get widgetAllDevicesSub;

  /// No description provided for @widgetDevicesNeeded.
  ///
  /// In it, this message translates to:
  /// **'Scegli almeno un veicolo'**
  String get widgetDevicesNeeded;

  /// No description provided for @widgetKeyNeeded.
  ///
  /// In it, this message translates to:
  /// **'Scrivi il nome del campo'**
  String get widgetKeyNeeded;

  /// No description provided for @widgetPeriod.
  ///
  /// In it, this message translates to:
  /// **'Periodo'**
  String get widgetPeriod;

  /// No description provided for @widgetPeriodDashboard.
  ///
  /// In it, this message translates to:
  /// **'Come la dashboard'**
  String get widgetPeriodDashboard;

  /// No description provided for @widgetAgg.
  ///
  /// In it, this message translates to:
  /// **'Valore'**
  String get widgetAgg;

  /// No description provided for @widgetBucket.
  ///
  /// In it, this message translates to:
  /// **'Raggruppamento'**
  String get widgetBucket;

  /// No description provided for @widgetTitle.
  ///
  /// In it, this message translates to:
  /// **'Titolo (facoltativo)'**
  String get widgetTitle;

  /// No description provided for @widgetWidth.
  ///
  /// In it, this message translates to:
  /// **'Larghezza'**
  String get widgetWidth;

  /// No description provided for @widgetHeight.
  ///
  /// In it, this message translates to:
  /// **'Altezza'**
  String get widgetHeight;

  /// No description provided for @widgetPreview.
  ///
  /// In it, this message translates to:
  /// **'Anteprima'**
  String get widgetPreview;

  /// No description provided for @widgetUnavailable.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 veicolo non più disponibile} other{{n} veicoli non più disponibili}}'**
  String widgetUnavailable(int n);

  /// No description provided for @widgetNoDevices.
  ///
  /// In it, this message translates to:
  /// **'Nessun veicolo disponibile per questo dato'**
  String get widgetNoDevices;

  /// No description provided for @widgetPeriodTooLong.
  ///
  /// In it, this message translates to:
  /// **'Periodo troppo lungo per questo dato'**
  String get widgetPeriodTooLong;

  /// No description provided for @widgetVehicles.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 veicolo} other{{n} veicoli}}'**
  String widgetVehicles(int n);

  /// No description provided for @widgetNoDeadlines.
  ///
  /// In it, this message translates to:
  /// **'Nessuna scadenza'**
  String get widgetNoDeadlines;

  /// No description provided for @widgetSize.
  ///
  /// In it, this message translates to:
  /// **'{w} × {h}'**
  String widgetSize(int w, int h);

  /// No description provided for @groupTrips.
  ///
  /// In it, this message translates to:
  /// **'Viaggi'**
  String get groupTrips;

  /// No description provided for @groupCosts.
  ///
  /// In it, this message translates to:
  /// **'Costi'**
  String get groupCosts;

  /// No description provided for @groupTracker.
  ///
  /// In it, this message translates to:
  /// **'Dati del tracker'**
  String get groupTracker;

  /// No description provided for @groupState.
  ///
  /// In it, this message translates to:
  /// **'Stato attuale'**
  String get groupState;

  /// No description provided for @mDistance.
  ///
  /// In it, this message translates to:
  /// **'Km percorsi'**
  String get mDistance;

  /// No description provided for @mBusinessKm.
  ///
  /// In it, this message translates to:
  /// **'Km di lavoro'**
  String get mBusinessKm;

  /// No description provided for @mPersonalKm.
  ///
  /// In it, this message translates to:
  /// **'Km personali'**
  String get mPersonalKm;

  /// No description provided for @mDriving.
  ///
  /// In it, this message translates to:
  /// **'Tempo di guida'**
  String get mDriving;

  /// No description provided for @mTrips.
  ///
  /// In it, this message translates to:
  /// **'Numero di viaggi'**
  String get mTrips;

  /// No description provided for @mMaxSpeed.
  ///
  /// In it, this message translates to:
  /// **'Velocità massima'**
  String get mMaxSpeed;

  /// No description provided for @mAlarms.
  ///
  /// In it, this message translates to:
  /// **'Allarmi'**
  String get mAlarms;

  /// No description provided for @mTraffic.
  ///
  /// In it, this message translates to:
  /// **'Dati sulla SIM'**
  String get mTraffic;

  /// No description provided for @mRestVoltage.
  ///
  /// In it, this message translates to:
  /// **'Batteria a riposo'**
  String get mRestVoltage;

  /// No description provided for @mCost.
  ///
  /// In it, this message translates to:
  /// **'Costo stimato'**
  String get mCost;

  /// No description provided for @mFuelCost.
  ///
  /// In it, this message translates to:
  /// **'Spesa carburante'**
  String get mFuelCost;

  /// No description provided for @mWearCost.
  ///
  /// In it, this message translates to:
  /// **'Usura'**
  String get mWearCost;

  /// No description provided for @mFuel.
  ///
  /// In it, this message translates to:
  /// **'Litri di carburante'**
  String get mFuel;

  /// No description provided for @mSpeed.
  ///
  /// In it, this message translates to:
  /// **'Velocità in movimento'**
  String get mSpeed;

  /// No description provided for @mAltitude.
  ///
  /// In it, this message translates to:
  /// **'Altitudine'**
  String get mAltitude;

  /// No description provided for @mSignal.
  ///
  /// In it, this message translates to:
  /// **'Segnale LTE'**
  String get mSignal;

  /// No description provided for @mSatellites.
  ///
  /// In it, this message translates to:
  /// **'Satelliti'**
  String get mSatellites;

  /// No description provided for @mVoltage.
  ///
  /// In it, this message translates to:
  /// **'Tensione'**
  String get mVoltage;

  /// No description provided for @mTemperature.
  ///
  /// In it, this message translates to:
  /// **'Temperatura'**
  String get mTemperature;

  /// No description provided for @mPressure.
  ///
  /// In it, this message translates to:
  /// **'Pressione'**
  String get mPressure;

  /// No description provided for @mExtra.
  ///
  /// In it, this message translates to:
  /// **'Dato aggiuntivo'**
  String get mExtra;

  /// No description provided for @mOdometer.
  ///
  /// In it, this message translates to:
  /// **'Contachilometri'**
  String get mOdometer;

  /// No description provided for @mDeadlines.
  ///
  /// In it, this message translates to:
  /// **'Scadenze'**
  String get mDeadlines;

  /// No description provided for @mStatus.
  ///
  /// In it, this message translates to:
  /// **'Posizione e stato'**
  String get mStatus;

  /// No description provided for @viewNumber.
  ///
  /// In it, this message translates to:
  /// **'Numero'**
  String get viewNumber;

  /// No description provided for @viewLine.
  ///
  /// In it, this message translates to:
  /// **'Linea nel tempo'**
  String get viewLine;

  /// No description provided for @viewBars.
  ///
  /// In it, this message translates to:
  /// **'Barre nel tempo'**
  String get viewBars;

  /// No description provided for @viewVehicles.
  ///
  /// In it, this message translates to:
  /// **'Barre per veicolo'**
  String get viewVehicles;

  /// No description provided for @viewTable.
  ///
  /// In it, this message translates to:
  /// **'Tabella per veicolo'**
  String get viewTable;

  /// No description provided for @viewList.
  ///
  /// In it, this message translates to:
  /// **'Elenco'**
  String get viewList;

  /// No description provided for @viewMap.
  ///
  /// In it, this message translates to:
  /// **'Mappa'**
  String get viewMap;

  /// No description provided for @aggAvg.
  ///
  /// In it, this message translates to:
  /// **'Media'**
  String get aggAvg;

  /// No description provided for @aggMin.
  ///
  /// In it, this message translates to:
  /// **'Minimo'**
  String get aggMin;

  /// No description provided for @aggMax.
  ///
  /// In it, this message translates to:
  /// **'Massimo'**
  String get aggMax;

  /// No description provided for @aggLast.
  ///
  /// In it, this message translates to:
  /// **'Ultimo valore'**
  String get aggLast;

  /// No description provided for @groupAuto.
  ///
  /// In it, this message translates to:
  /// **'Automatico'**
  String get groupAuto;

  /// No description provided for @groupHour.
  ///
  /// In it, this message translates to:
  /// **'Ore'**
  String get groupHour;

  /// No description provided for @groupDay.
  ///
  /// In it, this message translates to:
  /// **'Giorni'**
  String get groupDay;

  /// No description provided for @groupWeek.
  ///
  /// In it, this message translates to:
  /// **'Settimane'**
  String get groupWeek;

  /// No description provided for @groupMonth.
  ///
  /// In it, this message translates to:
  /// **'Mesi'**
  String get groupMonth;

  /// No description provided for @periodToday.
  ///
  /// In it, this message translates to:
  /// **'Oggi'**
  String get periodToday;

  /// No description provided for @period12m.
  ///
  /// In it, this message translates to:
  /// **'Ultimi 12 mesi'**
  String get period12m;

  /// No description provided for @periodYtd.
  ///
  /// In it, this message translates to:
  /// **'Da inizio anno'**
  String get periodYtd;

  /// No description provided for @dashboardSetCurrent.
  ///
  /// In it, this message translates to:
  /// **'Imposta come corrente'**
  String get dashboardSetCurrent;

  /// No description provided for @dashboardUnsetCurrent.
  ///
  /// In it, this message translates to:
  /// **'Non più corrente'**
  String get dashboardUnsetCurrent;

  /// No description provided for @dashboardCurrent.
  ///
  /// In it, this message translates to:
  /// **'Dashboard corrente'**
  String get dashboardCurrent;

  /// No description provided for @dashboardCurrentSet.
  ///
  /// In it, this message translates to:
  /// **'«{name}» è la dashboard corrente: la vedi nell\'analisi di ogni veicolo'**
  String dashboardCurrentSet(String name);

  /// No description provided for @dashboardCurrentUnset.
  ///
  /// In it, this message translates to:
  /// **'Nell\'analisi dei veicoli torna quella standard'**
  String get dashboardCurrentUnset;

  /// No description provided for @analysisStandard.
  ///
  /// In it, this message translates to:
  /// **'Analisi standard'**
  String get analysisStandard;

  /// No description provided for @analysisOpenDashboard.
  ///
  /// In it, this message translates to:
  /// **'Apri nelle dashboard'**
  String get analysisOpenDashboard;

  /// No description provided for @analysisNoWidgets.
  ///
  /// In it, this message translates to:
  /// **'Nessun widget della dashboard corrente vale per questo veicolo'**
  String get analysisNoWidgets;

  /// No description provided for @dashboardShare.
  ///
  /// In it, this message translates to:
  /// **'Condividi con un amico'**
  String get dashboardShare;

  /// No description provided for @dashboardShareHint.
  ///
  /// In it, this message translates to:
  /// **'L\'amico riceve solo i widget: non i tuoi veicoli né i loro dati. Li userà con i suoi veicoli.'**
  String get dashboardShareHint;

  /// No description provided for @dashboardShareNoFriends.
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora amici: aggiungili da Account › Amici'**
  String get dashboardShareNoFriends;

  /// No description provided for @dashboardShared.
  ///
  /// In it, this message translates to:
  /// **'Dashboard inviata a {name}'**
  String dashboardShared(String name);

  /// No description provided for @dashboardReceived.
  ///
  /// In it, this message translates to:
  /// **'{name} ti ha condiviso la dashboard «{dashboard}»'**
  String dashboardReceived(String name, String dashboard);

  /// No description provided for @dashboardReceivedWidgets.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 widget} other{{n} widget}} · scegli i tuoi veicoli'**
  String dashboardReceivedWidgets(int n);

  /// No description provided for @dashboardUse.
  ///
  /// In it, this message translates to:
  /// **'Usa'**
  String get dashboardUse;

  /// No description provided for @dashboardDecline.
  ///
  /// In it, this message translates to:
  /// **'Rifiuta'**
  String get dashboardDecline;

  /// No description provided for @dashboardUseHint.
  ///
  /// In it, this message translates to:
  /// **'Su quali dei tuoi veicoli mostrare i widget? Quelli che non valgono per un veicolo (es. dati del tracker su un\'auto senza tracker) usano gli altri scelti.'**
  String get dashboardUseHint;

  /// No description provided for @dashboardUseNoVehicles.
  ///
  /// In it, this message translates to:
  /// **'Scegli almeno un veicolo'**
  String get dashboardUseNoVehicles;

  /// No description provided for @dashboardAdded.
  ///
  /// In it, this message translates to:
  /// **'Dashboard «{name}» aggiunta'**
  String dashboardAdded(String name);

  /// No description provided for @errTooManyDashboardShares.
  ///
  /// In it, this message translates to:
  /// **'Il tuo amico ha già troppe dashboard da guardare: riprova più tardi'**
  String get errTooManyDashboardShares;

  /// No description provided for @platformLog.
  ///
  /// In it, this message translates to:
  /// **'Log della piattaforma'**
  String get platformLog;

  /// No description provided for @platformLogSub.
  ///
  /// In it, this message translates to:
  /// **'Errori, avvisi, richieste e query lente, per migliorare la piattaforma'**
  String get platformLogSub;

  /// No description provided for @logErrors.
  ///
  /// In it, this message translates to:
  /// **'Errori'**
  String get logErrors;

  /// No description provided for @logWarnings.
  ///
  /// In it, this message translates to:
  /// **'Avvisi'**
  String get logWarnings;

  /// No description provided for @logSlowRequests.
  ///
  /// In it, this message translates to:
  /// **'Richieste lente'**
  String get logSlowRequests;

  /// No description provided for @logSlowQueries.
  ///
  /// In it, this message translates to:
  /// **'Query lente'**
  String get logSlowQueries;

  /// No description provided for @logEmpty.
  ///
  /// In it, this message translates to:
  /// **'Niente da segnalare nel periodo'**
  String get logEmpty;

  /// No description provided for @logTimes.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 volta} other{{n} volte}}'**
  String logTimes(int n);

  /// No description provided for @logLast.
  ///
  /// In it, this message translates to:
  /// **'ultima {ago}'**
  String logLast(String ago);

  /// No description provided for @logDurations.
  ///
  /// In it, this message translates to:
  /// **'media {avg} · max {max}'**
  String logDurations(String avg, String max);

  /// No description provided for @logCalls.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 esecuzione} other{{n} esecuzioni}}'**
  String logCalls(int n);

  /// No description provided for @logFirst.
  ///
  /// In it, this message translates to:
  /// **'Prima volta: {time}'**
  String logFirst(String time);

  /// No description provided for @logRequestsHint.
  ///
  /// In it, this message translates to:
  /// **'Richieste oltre {ms} ms, per percorso. Conservati {n} giorni.'**
  String logRequestsHint(int ms, int n);

  /// No description provided for @logQueriesHint.
  ///
  /// In it, this message translates to:
  /// **'Query con durata media oltre {ms} ms (o massima 10 volte tanto), rilevate ogni ora. Conservati {n} giorni.'**
  String logQueriesHint(int ms, int n);

  /// No description provided for @logErrorsHint.
  ///
  /// In it, this message translates to:
  /// **'Errori e avvisi del backend, uguali raggruppati. Conservati {n} giorni.'**
  String logErrorsHint(int n);

  /// No description provided for @logQueriesOff.
  ///
  /// In it, this message translates to:
  /// **'Le query lente non vengono raccolte: il database deve caricare pg_stat_statements (vedi la documentazione del server).'**
  String get logQueriesOff;

  /// No description provided for @logCopied.
  ///
  /// In it, this message translates to:
  /// **'Dettagli copiati'**
  String get logCopied;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
