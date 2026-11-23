// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Car Tracking';

  @override
  String get cancel => 'Annulla';

  @override
  String get confirm => 'Conferma';

  @override
  String get save => 'Salva';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Chiudi';

  @override
  String get copy => 'Copia';

  @override
  String get done => 'Fatto';

  @override
  String get delete => 'Elimina';

  @override
  String get retry => 'Riprova';

  @override
  String get continueLabel => 'Continua';

  @override
  String get back => 'Indietro';

  @override
  String get open => 'Apri';

  @override
  String get verify => 'Verifica';

  @override
  String get noData => 'Nessun dato nel periodo';

  @override
  String get operationCancelled => 'Operazione annullata';

  @override
  String get you => 'tu';

  @override
  String get nameLabel => 'Nome';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get notAvailable => 'n/d';

  @override
  String get navMap => 'Mappa';

  @override
  String get navDevices => 'Dispositivi';

  @override
  String get navNotifications => 'Notifiche';

  @override
  String get navAccount => 'Account';

  @override
  String get never => 'mai';

  @override
  String get now => 'adesso';

  @override
  String minutesAgo(int n) {
    return '$n min fa';
  }

  @override
  String hoursAgo(int n) {
    return '$n h fa';
  }

  @override
  String daysAgo(int n) {
    return '$n g fa';
  }

  @override
  String durationMinutes(int m) {
    return '$m min';
  }

  @override
  String durationHours(int h, int m) {
    return '$h h $m min';
  }

  @override
  String get qualityExcellent => 'Ottimo';

  @override
  String get qualityGood => 'Buono';

  @override
  String get qualityPoor => 'Scarso';

  @override
  String get qualityBad => 'Pessimo';

  @override
  String get qualityWeak => 'Debole';

  @override
  String get qualityNone => 'Assente';

  @override
  String get statusMoving => 'In movimento';

  @override
  String get statusEngineOff => 'Motore spento';

  @override
  String get statusParked => 'Parcheggiata';

  @override
  String get statusAlarm => 'Allarme';

  @override
  String get eventMotion => 'Movimento';

  @override
  String get eventTilt => 'Inclinazione';

  @override
  String get eventPowerLost => 'Alimentazione scollegata';

  @override
  String get eventLowBattery => 'Batteria scarica';

  @override
  String get kindMotion => 'Movimento ad auto parcheggiata';

  @override
  String get kindTilt => 'Auto sollevata o inclinata';

  @override
  String get kindPowerLost => 'Alimentazione scollegata';

  @override
  String get kindLowBattery => 'Batteria dell\'auto scarica';

  @override
  String get kindOffline => 'Tracker non raggiungibile';

  @override
  String get kindOnline => 'Tracker di nuovo raggiungibile';

  @override
  String kindGeofenceEnter(String device) {
    return '$device è arrivato';
  }

  @override
  String kindGeofenceExit(String device) {
    return '$device è partito';
  }

  @override
  String notificationBodyAt(String device, String time) {
    return '$device, ore $time';
  }

  @override
  String notificationBodyEnter(String area, String time) {
    return 'Entrato in $area, ore $time';
  }

  @override
  String notificationBodyExit(String area, String time) {
    return 'Uscito da $area, ore $time';
  }

  @override
  String get notificationsTitle => 'Notifiche';

  @override
  String get markAllRead => 'Segna tutte come lette';

  @override
  String get noNotifications => 'Nessuna notifica';

  @override
  String get errNetwork => 'Server non raggiungibile';

  @override
  String get errInvalidCredentials => 'Email o password errate';

  @override
  String get errLocked => 'Troppi tentativi: account bloccato temporaneamente';

  @override
  String get errInvalidCode => 'Codice non valido';

  @override
  String get errEnrollExpired => 'Configurazione scaduta: ricomincia';

  @override
  String get errStepUp => 'Serve il codice dell\'app di autenticazione';

  @override
  String get errInvalidPassword => 'Password attuale errata';

  @override
  String get errEmailTaken => 'Esiste già un account con questa email';

  @override
  String get errSelf => 'Non puoi farlo sul tuo account';

  @override
  String get errInvalidPairing => 'IMEI o codice di abbinamento errati';

  @override
  String get errAlreadyClaimed => 'Il tracker appartiene a un altro account';

  @override
  String get errOwnerOnly => 'Solo il proprietario può farlo';

  @override
  String get errShareSelf => 'Il dispositivo è già tuo';

  @override
  String get errTooManyShares => 'Troppe condivisioni per questo dispositivo';

  @override
  String get errOwnerCannotLeave =>
      'Il proprietario rimuove il tracker invece di lasciarlo';

  @override
  String get errTooManyAreas => 'Massimo 20 aree per dispositivo';

  @override
  String get errTooManyPhones => 'Massimo 5 telefoni per account';

  @override
  String get errTooManyVehicles => 'Massimo 10 veicoli per account';

  @override
  String get errNotATracker => 'Disponibile solo per i tracker';

  @override
  String get errFriendSelf => 'È il tuo codice';

  @override
  String get errTooManyFriends => 'Massimo 200 amici';

  @override
  String get errLiveTooLong => 'Il live dura al massimo 2 ore';

  @override
  String get errPeriodTooLong => 'Periodo massimo 93 giorni';

  @override
  String get errRateLimited => 'Troppe richieste: riprova tra poco';

  @override
  String get errNotFound => 'Non trovato';

  @override
  String get errValidation => 'Dati non validi';

  @override
  String get errInvalidPasskey => 'Passkey non valida';

  @override
  String get errChallengeExpired => 'Richiesta scaduta: riprova';

  @override
  String get errUnauthorized => 'Sessione scaduta: accedi di nuovo';

  @override
  String get errForbidden => 'Operazione non consentita';

  @override
  String errGeneric(int status) {
    return 'Errore $status';
  }

  @override
  String get serverAddress => 'Indirizzo della tua piattaforma';

  @override
  String get serverLabel => 'Server';

  @override
  String get serverUnreachable => 'Server non raggiungibile o non compatibile';

  @override
  String get loginPasskey => 'Accedi con passkey';

  @override
  String get loginPassword => 'Accedi con password';

  @override
  String get or => 'oppure';

  @override
  String get passkeyNotCompleted => 'Accesso con passkey non completato';

  @override
  String serverChange(String host) {
    return 'Server: $host · cambia';
  }

  @override
  String get mfaTitle => 'Verifica in due passaggi';

  @override
  String get mfaTotpHint =>
      'Inserisci il codice a 6 cifre dell\'app di autenticazione';

  @override
  String get mfaRecoveryHint => 'Inserisci uno dei codici di recupero salvati';

  @override
  String get useAuthenticator => 'Usa l\'app di autenticazione';

  @override
  String get useRecoveryCode => 'Usa un codice di recupero';

  @override
  String recoveryCodesLeft(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Ti restano $n codici di recupero',
      one: 'Ti resta 1 codice di recupero',
    );
    return '$_temp0: generane di nuovi dal tuo account';
  }

  @override
  String get inviteInvalid => 'Invito non valido';

  @override
  String get goToLogin => 'Vai all\'accesso';

  @override
  String get resetTitle => 'Ripristino accesso';

  @override
  String welcome(String name) {
    return 'Benvenuto, $name';
  }

  @override
  String inviteHint(String email) {
    return '$email\nScegli una password di almeno 12 caratteri, poi configurerai l\'app di autenticazione.';
  }

  @override
  String get newPassword => 'Nuova password';

  @override
  String get repeatPassword => 'Ripeti password';

  @override
  String get passwordTooShort => 'La password deve avere almeno 12 caratteri';

  @override
  String get passwordsDiffer => 'Le password non coincidono';

  @override
  String get sessionExpired => 'Sessione scaduta';

  @override
  String get loginAgain => 'Accedi di nuovo';

  @override
  String get enrollTitle => 'Configura la verifica in due passaggi';

  @override
  String get enrollHint =>
      'Obbligatoria. Inquadra il codice con un\'app di autenticazione (Aegis, Google Authenticator, 2FAS...) e inserisci il codice generato.';

  @override
  String get keyCopied => 'Chiave copiata';

  @override
  String get copyKey => 'Copia la chiave';

  @override
  String get activate => 'Attiva';

  @override
  String get recoveryTitle => 'Codici di recupero';

  @override
  String get recoveryHint =>
      'Conservali in un posto sicuro: ognuno permette un accesso se perdi il telefono. Non verranno mostrati di nuovo.';

  @override
  String get codesCopied => 'Codici copiati';

  @override
  String get codesSaved => 'Ho salvato i codici';

  @override
  String get createPasskey => 'Crea una passkey (impronta)';

  @override
  String get later => 'Più tardi';

  @override
  String get passkeyCreated =>
      'Passkey creata: potrai accedere con l\'impronta';

  @override
  String get passkeyNotCreated => 'Passkey non creata';

  @override
  String get defaultPasskeyBrowser => 'Browser';

  @override
  String get defaultPasskeyPhone => 'Telefono';

  @override
  String get devicesTitle => 'Dispositivi';

  @override
  String get add => 'Aggiungi';

  @override
  String get noDevices =>
      'Nessun dispositivo. Aggiungi il tuo tracker con il codice sull\'etichetta.';

  @override
  String get noDevicesShort => 'Nessun dispositivo';

  @override
  String get addYourTracker => 'Aggiungi il tuo tracker';

  @override
  String get waitingFirstContact => 'In attesa del primo collegamento';

  @override
  String get noPosition => 'Nessuna posizione';

  @override
  String sharedBy(String name) {
    return 'condiviso da $name';
  }

  @override
  String signalTooltip(String quality) {
    return 'Segnale $quality';
  }

  @override
  String satellitesTooltip(String quality) {
    return 'Satelliti $quality';
  }

  @override
  String get fromCell => 'posizione dalla cella';

  @override
  String get lastKnown => 'ultima posizione nota';

  @override
  String get device => 'Dispositivo';

  @override
  String get tabLive => 'Live';

  @override
  String get tabHistory => 'Storico';

  @override
  String get tabAnalysis => 'Analisi';

  @override
  String get tabAreas => 'Aree';

  @override
  String get tabSettings => 'Impostazioni';

  @override
  String get last24h => '24 ore';

  @override
  String get periodLast24h => 'Ultime 24 ore';

  @override
  String get periodLast7d => 'Ultimi 7 giorni';

  @override
  String get periodLast30d => 'Ultimi 30 giorni';

  @override
  String get periodLast90d => 'Ultimi 90 giorni';

  @override
  String get periodCustom => 'Intervallo personalizzato';

  @override
  String accessRevoked(String device) {
    return 'La condivisione di $device è terminata';
  }

  @override
  String get leaveShare => 'Smetti di ricevere';

  @override
  String leaveShareTitle(String device) {
    return 'Smettere di ricevere $device?';
  }

  @override
  String get leaveShareBody =>
      'Non lo vedrai più e le tue aree su questo dispositivo vengono cancellate.';

  @override
  String get followOn => 'Segui il veicolo (attivo)';

  @override
  String get followOff => 'Segui il veicolo';

  @override
  String liveUntil(String time) {
    return 'Live fino alle $time';
  }

  @override
  String get connected => 'Collegato';

  @override
  String notConnected(String ago) {
    return 'Non collegato · ultimo contatto $ago';
  }

  @override
  String get noPositionReceived => 'Nessuna posizione ricevuta';

  @override
  String cellEstimate(String meters) {
    return 'stimata dalla cella (±$meters m)';
  }

  @override
  String get noFix => 'senza fix GPS';

  @override
  String get commandSent => 'Comando inviato';

  @override
  String get commandQueued =>
      'Comando in coda: il tracker lo riceverà al prossimo collegamento';

  @override
  String get live30 => 'Live 30 min';

  @override
  String get stopLive => 'Ferma live';

  @override
  String get locate => 'Localizza';

  @override
  String resumeAntitheft(String time) {
    return 'Riattiva antifurto (in pausa fino alle $time)';
  }

  @override
  String get pauseAntitheftTooltip =>
      'Metti in pausa l\'antifurto (officina, lavaggio...)';

  @override
  String get pause1h => 'Pausa 1 ora';

  @override
  String get pause24h => 'Pausa 24 ore';

  @override
  String get pause7d => 'Pausa 7 giorni';

  @override
  String get pauseAntitheft => 'Pausa antifurto';

  @override
  String viewerNotice(String owner, String until) {
    return 'Condiviso da $owner in sola visione$until';
  }

  @override
  String viewerUntil(String date) {
    return ' fino al $date';
  }

  @override
  String get noPositions => 'Nessuna posizione nel periodo';

  @override
  String get truncated =>
      'Troppi punti: mostrati i primi 50.000, riduci il periodo';

  @override
  String pointsRange(int n, String from, String to) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n punti',
      one: '1 punto',
    );
    return '$_temp0 dal $from al $to';
  }

  @override
  String get noFixShort => 'senza fix';

  @override
  String get coloringPlain => 'Percorso';

  @override
  String get coloringSpeed => 'Velocità';

  @override
  String get coloringSignal => 'Segnale';

  @override
  String get coloringSatellites => 'Satelliti';

  @override
  String get legendNoFix => '4 sat / senza fix';

  @override
  String get kpiDistance => 'Distanza';

  @override
  String get kpiDriving => 'Alla guida';

  @override
  String get kpiMaxSpeed => 'Velocità max';

  @override
  String get kpiTrips => 'Viaggi';

  @override
  String get kmPerDay => 'Km per giorno';

  @override
  String get drivingPerDay => 'Tempo di guida per giorno';

  @override
  String tripsList(int n) {
    return 'Viaggi ($n)';
  }

  @override
  String tripDetail(String km, String duration, String avg, String max) {
    return '$km km · $duration · media $avg km/h · max $max km/h';
  }

  @override
  String get bucket2m => '2 minuti';

  @override
  String get bucket10m => '10 minuti';

  @override
  String get bucket1h => 'ora';

  @override
  String get bucket6h => '6 ore';

  @override
  String get bucket1d => 'giorno';

  @override
  String get chartSpeed => 'Velocità';

  @override
  String chartSpeedSub(String bucket) {
    return 'media e massima ogni $bucket';
  }

  @override
  String get seriesMax => 'Massima';

  @override
  String get seriesAvgMoving => 'Media in movimento';

  @override
  String get chartSignal => 'Segnale LTE';

  @override
  String get chartSignalSub =>
      'sotto -105 dBm il collegamento diventa instabile';

  @override
  String get seriesAvg => 'Medio';

  @override
  String get seriesMin => 'Minimo';

  @override
  String get thresholdPoor => 'scarso';

  @override
  String get chartSatellites => 'Satelliti in uso';

  @override
  String get chartSatellitesSub => 'sotto 6 la posizione è poco precisa';

  @override
  String get thresholdWeakFix => 'fix debole';

  @override
  String get chartAltitude => 'Altitudine';

  @override
  String get chartBattery => 'Batteria dell\'auto';

  @override
  String get chartBatterySub =>
      'tensione minima e media: sotto 11,8 V a motore spento la batteria è scarica';

  @override
  String get chartTemperature => 'Temperatura nell\'abitacolo';

  @override
  String get chartPressure => 'Pressione atmosferica';

  @override
  String get chartPoints => 'Punti ricevuti';

  @override
  String get chartPointsSub => 'in rosso quelli senza fix GPS';

  @override
  String get seriesPoints => 'Punti';

  @override
  String get seriesNoFix => 'Senza fix';

  @override
  String get chartFixQuality => 'Qualità della posizione';

  @override
  String get fixGood => 'Fix buono';

  @override
  String get fixWeak => 'Fix debole (<6 sat)';

  @override
  String get chartSignalDistribution => 'Distribuzione del segnale';

  @override
  String weakSignalShare(int p) {
    return '$p% dei punti sotto -105 dBm';
  }

  @override
  String get chartSatelliteDistribution => 'Distribuzione dei satelliti';

  @override
  String get chartSpeedDistribution => 'Distribuzione della velocità';

  @override
  String get chartSpeedDistributionSub =>
      'punti in movimento per fascia di 10 km/h';

  @override
  String get chartCoverage => 'Copertura della rete';

  @override
  String get chartCoverageSub =>
      'segnale medio per zona: in rosso dove il tracker perde la rete';

  @override
  String get simMonth => 'Dati SIM del mese';

  @override
  String simUsed(String used, String budget, String projected, int p) {
    return 'Usati $used di $budget · stima a fine mese $projected ($p%)';
  }

  @override
  String get simEstimate =>
      'Stima: frame cifrati + intestazioni TLS/WebSocket + connessioni';

  @override
  String get dataPerDay => 'Dati per giorno';

  @override
  String get dataPerDaySub =>
      'la linea è il consumo giornaliero che rispetta il piano';

  @override
  String get budget => 'budget';

  @override
  String get deviceName => 'Nome del dispositivo';

  @override
  String get tapToRename => 'Tocca per rinominare';

  @override
  String get imei => 'IMEI';

  @override
  String get modemFirmware => 'Modem e firmware';

  @override
  String firmwareVersion(String v) {
    return 'firmware $v';
  }

  @override
  String get neverConnected => 'mai collegato';

  @override
  String connectedSince(String date) {
    return 'collegato dal $date';
  }

  @override
  String get alarmNotifications => 'Notifiche di allarme';

  @override
  String get sharing => 'Condivisione';

  @override
  String get sharingHint =>
      'Chi riceve la condivisione vede solo posizione, velocità e stato, senza poter cambiare nulla.';

  @override
  String get shareWith => 'Condividi con un amico';

  @override
  String get shareTitle => 'Condividi in sola visione';

  @override
  String get shareFriend => 'Amico';

  @override
  String get noFriendsToShare =>
      'Puoi condividere solo con gli amici: aggiungine uno con il suo codice.';

  @override
  String get goToFriends => 'Vai agli amici';

  @override
  String get shareDuration => 'Durata';

  @override
  String get permanent => 'Permanente';

  @override
  String hoursShort(int n) {
    return '$n h';
  }

  @override
  String daysShort(int n) {
    return '$n g';
  }

  @override
  String get customEnd => 'Data e ora';

  @override
  String endsAt(String date) {
    return 'Fino al $date';
  }

  @override
  String get share => 'Condividi';

  @override
  String get shared => 'Dispositivo condiviso';

  @override
  String get noShares => 'Non condiviso con nessuno';

  @override
  String get sharePermanent => 'Permanente';

  @override
  String shareUntil(String date) {
    return 'Fino al $date';
  }

  @override
  String get changeEnd => 'Cambia scadenza';

  @override
  String get revoke => 'Revoca';

  @override
  String revokeTitle(String name) {
    return 'Revocare la condivisione a $name?';
  }

  @override
  String get revokeBody =>
      'Non vedrà più il dispositivo e le sue aree vengono cancellate.';

  @override
  String get shareRevoked => 'Condivisione revocata';

  @override
  String get dangerZone => 'Zona pericolosa';

  @override
  String get removeTracker => 'Elimina il veicolo';

  @override
  String get removeTrackerSub => 'Con il suo storico; il tracker torna libero';

  @override
  String get removeTrackerTitle => 'Eliminare il veicolo?';

  @override
  String get removeTrackerBody =>
      'Storico, km, scadenze, costi, aree, condivisioni e notifiche vengono cancellati. Il tracker torna libero e si potrà abbinare di nuovo con il codice dell\'etichetta. Per tenere lo storico usa «Rimuovi il tracker dal veicolo».';

  @override
  String get errVehicleHasTracker => 'Il veicolo ha già un tracker';

  @override
  String get pairInHint =>
      'In quale veicolo lo installi? In un veicolo che hai già restano il suo storico, i km e le scadenze.';

  @override
  String get pairNewVehicle => 'Nuovo veicolo';

  @override
  String get trackerSection => 'Tracker';

  @override
  String get moveTracker => 'Sposta su un altro veicolo';

  @override
  String get moveTrackerSub => 'Questo veicolo resta con il suo storico';

  @override
  String get moveTrackerTitle => 'Spostare il tracker?';

  @override
  String get moveTarget => 'Veicolo di destinazione';

  @override
  String get archivePrevious => 'Archivia questo veicolo';

  @override
  String get move => 'Sposta';

  @override
  String trackerMoved(String name) {
    return 'Tracker spostato su $name';
  }

  @override
  String get detachTracker => 'Rimuovi il tracker dal veicolo';

  @override
  String get detachTrackerSub =>
      'Il veicolo resta, il tracker si può abbinare di nuovo';

  @override
  String get detachTrackerTitle => 'Rimuovere il tracker?';

  @override
  String get detachTrackerBody =>
      'Il veicolo resta con storico, km, scadenze e condivisioni, senza tracker. Il tracker si potrà abbinare di nuovo con il codice dell\'etichetta.';

  @override
  String get trackerDetached => 'Tracker rimosso';

  @override
  String get archived => 'Archiviato';

  @override
  String get archiveSub => 'Nascosto dalla mappa; storico e scadenze restano';

  @override
  String get installations => 'Tracker installati';

  @override
  String installedRange(String from, String to) {
    return 'dal $from al $to';
  }

  @override
  String installedSince(String from) {
    return 'dal $from';
  }

  @override
  String get areasHint =>
      'Ricevi una notifica quando il dispositivo entra (o esce) da un\'area: per esempio quando sta per arrivare a destinazione.';

  @override
  String get noAreas => 'Nessuna area';

  @override
  String get addArea => 'Aggiungi un\'area';

  @override
  String get editArea => 'Modifica area';

  @override
  String get areaName => 'Nome dell\'area';

  @override
  String get areaDefaultName => 'Destinazione';

  @override
  String radius(String distance) {
    return 'Raggio: $distance';
  }

  @override
  String get notifyEnter => 'Avvisa all\'arrivo';

  @override
  String get notifyExit => 'Avvisa alla partenza';

  @override
  String get tapMapToPlace => 'Tocca la mappa per spostare il centro';

  @override
  String get areaInside => 'dentro';

  @override
  String get areaOutside => 'fuori';

  @override
  String areaSummary(String radius, String state) {
    return '$radius · $state';
  }

  @override
  String areaPolygonSummary(int n, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vertici',
      one: '1 vertice',
    );
    return '$_temp0 · $state';
  }

  @override
  String get areaCircle => 'Cerchio';

  @override
  String get areaPolygon => 'Poligono';

  @override
  String get tapMapToDraw =>
      'Tocca la mappa per aggiungere i vertici del poligono';

  @override
  String areaVertices(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vertici',
      one: '1 vertice',
      zero: 'Nessun vertice',
    );
    return '$_temp0';
  }

  @override
  String get undoVertex => 'Annulla l\'ultimo';

  @override
  String get clearVertices => 'Ricomincia';

  @override
  String get areaPolygonTooFew => 'Servono almeno 3 vertici';

  @override
  String get errPolygonInvalid =>
      'I lati dell\'area si incrociano o l\'area è troppo piccola';

  @override
  String get errPolygonTooLarge => 'L\'area supera i 50 km';

  @override
  String get errTooManyRefuels => 'Troppi rifornimenti per questo veicolo';

  @override
  String get errRefuelFuture => 'Un rifornimento non può essere nel futuro';

  @override
  String deleteAreaTitle(String name) {
    return 'Eliminare $name?';
  }

  @override
  String get areaSaved => 'Area salvata';

  @override
  String get addTracker => 'Aggiungi tracker';

  @override
  String get scanTitle => 'Inquadra il QR dell\'etichetta';

  @override
  String get stepLabel => 'Etichetta del tracker';

  @override
  String get stepLabelSub => 'QR code o IMEI e codice di abbinamento';

  @override
  String get stepName => 'Veicolo';

  @override
  String get stepPower => 'Accensione';

  @override
  String get stepPowerSub => 'Primo collegamento del tracker';

  @override
  String get stepDone => 'Fatto';

  @override
  String get labelHint =>
      'Sul tracker (o sulla sua scatola) c\'è un\'etichetta con un QR code, l\'IMEI e il codice di abbinamento. Il codice dimostra che hai il tracker in mano: tienilo riservato.';

  @override
  String get scanQr => 'Scansiona il QR code';

  @override
  String get manualEntry => 'oppure inserisci i dati a mano';

  @override
  String get imeiLabel => 'IMEI (15 cifre)';

  @override
  String get pairingCode => 'Codice di abbinamento';

  @override
  String get imeiInvalid => 'L\'IMEI ha 15 cifre';

  @override
  String get alreadyMine => 'Questo tracker è già nel tuo account';

  @override
  String get ownedByOther =>
      'Il tracker appartiene a un altro account: chiedi al proprietario di condividerlo';

  @override
  String get defaultDeviceName => 'La mia auto';

  @override
  String get mapColor => 'Colore sulla mappa';

  @override
  String get addToAccount => 'Aggiungi al mio account';

  @override
  String get insertSim => 'Inserisci la SIM nel tracker';

  @override
  String get connectPower => 'Collegalo all\'alimentazione dell\'auto';

  @override
  String get parkOutside => 'Lascia l\'auto all\'aperto';

  @override
  String get firstFixHint => 'Il primo fix GPS può richiedere qualche minuto';

  @override
  String get waitingTracker =>
      'In attesa del primo collegamento del tracker...';

  @override
  String get continueLater => 'Continua in seguito';

  @override
  String get trackerConnected =>
      'Il tracker è collegato. La prima posizione arriva appena l\'auto si muove o al prossimo controllo periodico.';

  @override
  String get openDevice => 'Apri il dispositivo';

  @override
  String get accountTitle => 'Account';

  @override
  String get editName => 'Modifica nome';

  @override
  String get language => 'Lingua';

  @override
  String get administration => 'Amministrazione';

  @override
  String get administrationSub => 'Utenti, inviti, ripristino accessi';

  @override
  String get passkeys => 'Passkey';

  @override
  String passkeyCreatedAgo(String ago) {
    return 'Creata $ago';
  }

  @override
  String passkeyUsedAgo(String ago) {
    return ' · usata $ago';
  }

  @override
  String get passkeySynced => ' · sincronizzata';

  @override
  String get passkeyRemoved => 'Passkey rimossa';

  @override
  String get addPasskey => 'Aggiungi una passkey';

  @override
  String get addPasskeySub => 'Accesso con impronta o blocco schermo';

  @override
  String get passkeyName => 'Nome della passkey';

  @override
  String get passkeyAdded => 'Passkey aggiunta';

  @override
  String get security => 'Sicurezza';

  @override
  String get changePassword => 'Cambia password';

  @override
  String get currentPassword => 'Password attuale';

  @override
  String get passwordMin => 'Almeno 12 caratteri';

  @override
  String get change => 'Cambia';

  @override
  String get passwordChanged =>
      'Password cambiata: le altre sessioni sono state chiuse';

  @override
  String get changeAuthenticator => 'Cambia app di autenticazione';

  @override
  String get newPhone => 'Nuovo telefono';

  @override
  String get newAuthenticator => 'Nuova app di autenticazione';

  @override
  String get newAppCode => 'Codice della nuova app';

  @override
  String get authenticatorUpdated => 'App di autenticazione aggiornata';

  @override
  String get authenticatorCode => 'Codice dell\'app di autenticazione';

  @override
  String get confirmWithCode => 'Conferma con il codice';

  @override
  String recoveryLeft(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n rimasti',
      one: '1 rimasto',
    );
    return '$_temp0 · genera nuovi codici';
  }

  @override
  String get newRecoveryCodes => 'Nuovi codici di recupero';

  @override
  String get newRecoveryHint =>
      'I codici precedenti non sono più validi. Conservali in un posto sicuro.';

  @override
  String get activeSessions => 'Sessioni attive';

  @override
  String get thisSession => ' (questa)';

  @override
  String sessionActive(String ip, String ago) {
    return '$ip · attiva $ago';
  }

  @override
  String get disconnect => 'Disconnetti';

  @override
  String get disconnectOthers => 'Disconnetti le altre sessioni';

  @override
  String get sessionsClosed => 'Sessioni chiuse';

  @override
  String get app => 'App';

  @override
  String get pushTitle => 'Notifiche push';

  @override
  String get pushOn => 'Attive';

  @override
  String get pushOff =>
      'Non configurate: le notifiche arrivano solo con l\'app aperta';

  @override
  String get logout => 'Esci';

  @override
  String get unknownAgent => 'Sconosciuto';

  @override
  String get androidApp => 'App Android';

  @override
  String get invite => 'Invita';

  @override
  String get users => 'Utenti';

  @override
  String userSummary(String email, int devices, int passkeys) {
    String _temp0 = intl.Intl.pluralLogic(
      devices,
      locale: localeName,
      other: '$devices dispositivi',
      one: '1 dispositivo',
    );
    return '$email · $_temp0 · $passkeys passkey';
  }

  @override
  String get twoFactorPending => ' · 2FA da configurare';

  @override
  String lastLogin(String ago) {
    return ' · accesso $ago';
  }

  @override
  String get resetAccess => 'Ripristina accesso (nuova password e 2FA)';

  @override
  String get resetLink => 'Link di ripristino';

  @override
  String get enable => 'Riattiva';

  @override
  String get disable => 'Disattiva';

  @override
  String get removeAdmin => 'Togli amministratore';

  @override
  String get makeAdmin => 'Rendi amministratore';

  @override
  String deleteUserTitle(String name) {
    return 'Eliminare $name?';
  }

  @override
  String get deleteUserBody =>
      'I suoi dispositivi restano senza proprietario e le sue condivisioni terminano.';

  @override
  String get pendingInvites => 'Inviti in attesa';

  @override
  String get none => 'Nessuno';

  @override
  String expires(String date) {
    return 'Scade $date';
  }

  @override
  String get cancelInvite => 'Annulla invito';

  @override
  String get inviteUser => 'Invita un utente';

  @override
  String get administrator => 'Amministratore';

  @override
  String get createInvite => 'Crea invito';

  @override
  String get inviteCreated => 'Invito creato';

  @override
  String get linkHint =>
      'Invia questo link alla persona: vale 72 ore e si può usare una sola volta.';

  @override
  String get linkCopied => 'Link copiato';

  @override
  String get addChooseTitle => 'Cosa vuoi aggiungere?';

  @override
  String get addTrackerOption => 'Tracker GPS';

  @override
  String get addTrackerOptionSub => 'Con il codice sull\'etichetta';

  @override
  String get phoneOption => 'Questo telefono';

  @override
  String get phoneOptionSub =>
      'Condividi la posizione del telefono, senza hardware';

  @override
  String get vehicleOption => 'Veicolo senza tracker';

  @override
  String get vehicleOptionSub =>
      'La posizione arriva dal tuo telefono quando sei a bordo';

  @override
  String get addVehicleTitle => 'Nuovo veicolo';

  @override
  String get addVehicle => 'Aggiungi veicolo';

  @override
  String get vehicleIntro =>
      'Quando condividi dal veicolo, il telefono registra i viaggi dell\'auto: costi, chilometri, scadenze e aree come con un tracker, senza comandi né allarmi.';

  @override
  String get vehicleName => 'Nome del veicolo';

  @override
  String get vehicleKind => 'Veicolo, posizione dal telefono';

  @override
  String get vehicleDriving => 'In viaggio con il telefono';

  @override
  String get shareAs => 'Condividi come';

  @override
  String get shareAsPerson => 'Me stesso';

  @override
  String get shareAsPersonSub => 'La tua posizione, vista dagli amici';

  @override
  String get shareAsVehicleSub =>
      'Viaggi e costi del veicolo; la tua posizione personale resta ferma';

  @override
  String shareAsChanged(String name) {
    return 'Ora condividi come $name';
  }

  @override
  String get phoneTitle => 'Posizione del telefono';

  @override
  String get phoneIntro =>
      'Senza un tracker puoi condividere la posizione di questo telefono con i tuoi amici. I dati sono meno completi di quelli di un tracker: niente satelliti, segnale o batteria dell\'auto, e la precisione dipende da GPS, Wi-Fi e rete del telefono.';

  @override
  String get phoneAndroidHint =>
      'La condivisione continua in background con una notifica fissa, anche con l\'app chiusa. Si ferma con Interrompi, eliminando il telefono o uscendo dall\'account.';

  @override
  String get phoneOnlyAndroid =>
      'La posizione si condivide dall\'app Android: il browser non può inviarla in background.';

  @override
  String get phoneBackgroundHint =>
      'Per riprendere da sola dopo un riavvio del telefono, la condivisione ha bisogno della posizione consentita «Sempre».';

  @override
  String get phoneBackgroundAllow => 'Consenti sempre';

  @override
  String get phoneChannel => 'Condivisione della posizione';

  @override
  String get phoneName => 'Nome del telefono';

  @override
  String phoneDefaultName(String name) {
    return 'Telefono di $name';
  }

  @override
  String get phoneStart => 'Inizia a condividere';

  @override
  String get phoneStop => 'Interrompi';

  @override
  String kindPhoneBattery(String device, int n) {
    return '$device: batteria al $n%';
  }

  @override
  String notificationBodyPhoneBattery(String time) {
    return 'La posizione potrebbe interrompersi presto, ore $time';
  }

  @override
  String kindLongStop(String device, int h) {
    String _temp0 = intl.Intl.pluralLogic(
      h,
      locale: localeName,
      other: '$h ore',
      one: 'un\'ora',
    );
    return '$device è fermo da più di $_temp0';
  }

  @override
  String notificationBodyLongStop(String time) {
    return 'Fermo dalle $time, fuori dalle tue aree';
  }

  @override
  String get stopAlert => 'Sosta prolungata';

  @override
  String get stopAlertHint =>
      'Ti avvisa se il dispositivo resta fermo più a lungo di così fuori dalle tue aree (casa, lavoro...). Ognuno sceglie il proprio avviso, anche chi riceve la condivisione.';

  @override
  String get stopAlertOff => 'Avviso disattivato';

  @override
  String get batteryAlert => 'Batteria bassa';

  @override
  String batteryAlertAt(int n) {
    return 'Avvisa al $n%';
  }

  @override
  String stopAlertAfter(int h) {
    String _temp0 = intl.Intl.pluralLogic(
      h,
      locale: localeName,
      other: '$h ore',
      one: '1 ora',
    );
    return 'Avvisa dopo $_temp0';
  }

  @override
  String get stopAlertAfterOne => 'Avvisa dopo un\'ora';

  @override
  String get areaSchedule => 'Solo in certi orari';

  @override
  String get areaScheduleHint =>
      'Avvisa solo nei giorni e nelle ore scelti; se la fine è prima dell\'inizio, la fascia passa la mezzanotte.';

  @override
  String areaFrom(String time) {
    return 'Dalle $time';
  }

  @override
  String areaTo(String time) {
    return 'Alle $time';
  }

  @override
  String get areaAllDay => 'tutto il giorno';

  @override
  String firmwareAvailable(String version) {
    return 'Disponibile il firmware $version';
  }

  @override
  String get firmwareInstall => 'Installa';

  @override
  String firmwareInstallTitle(String version) {
    return 'Installare il firmware $version?';
  }

  @override
  String firmwareInstallBody(String mb) {
    return 'Il tracker scarica l\'aggiornamento alla prossima connessione ($mb MB di dati della SIM), lo verifica e si riavvia. Se il nuovo firmware non riesce a collegarsi al server torna da solo a quello attuale.';
  }

  @override
  String firmwareWaiting(String version) {
    return 'Firmware $version: in attesa della prossima connessione del tracker';
  }

  @override
  String firmwareDownloading(String version) {
    return 'Download del firmware $version in corso';
  }

  @override
  String firmwareRebooting(String version) {
    return 'Firmware $version installato, riavvio del tracker';
  }

  @override
  String firmwareDone(String version) {
    return 'Aggiornato al firmware $version';
  }

  @override
  String firmwareNotApplied(String version) {
    return 'Il firmware $version non si è avviato: il tracker è tornato alla versione precedente';
  }

  @override
  String firmwareFailed(String version) {
    return 'Aggiornamento al firmware $version non riuscito: riprova';
  }

  @override
  String firmwareUpToDate(String version) {
    return 'Firmware $version, aggiornato';
  }

  @override
  String get firmwareImages => 'Firmware per gli aggiornamenti';

  @override
  String get firmwareImagesHint =>
      'Si caricano dal server con npm run firmware; i proprietari li installano dalle impostazioni del tracker.';

  @override
  String firmwarePending(int n) {
    return '$n in corso';
  }

  @override
  String get errFirmware => 'Questo firmware non è adatto al tracker';

  @override
  String get yourData => 'I tuoi dati';

  @override
  String get exportData => 'Esporta i miei dati';

  @override
  String get exportDataSub =>
      'Profilo, accessi, amici, dispositivi con le loro posizioni, aree e notifiche in un file JSON';

  @override
  String get deleteAccount => 'Elimina account';

  @override
  String get deleteAccountSub => 'Elimina per sempre l\'account e i dati';

  @override
  String get deleteAccountTitle => 'Eliminare l\'account?';

  @override
  String get deleteAccountBody =>
      'Vengono eliminati per sempre: i telefoni e le posizioni di tutti i tuoi dispositivi, le condivisioni, gli amici, le aree e le notifiche. I tracker tornano liberi e si possono abbinare di nuovo con il codice dell\'etichetta. Prima puoi esportare i tuoi dati.';

  @override
  String deleteAccountEmail(String email) {
    return 'Scrivi $email per confermare';
  }

  @override
  String get errEmailMismatch => 'L\'email non corrisponde';

  @override
  String get errLastAdmin =>
      'Sei l\'unico amministratore: nomina prima un altro amministratore';

  @override
  String get exportPeriod => 'Esporta il periodo';

  @override
  String get exportHint => 'GPX: un tracciato per viaggio. CSV: tutti i punti.';

  @override
  String get phonePauseHour => 'Pausa 1 ora';

  @override
  String get phoneResume => 'Riprendi';

  @override
  String phonePausedUntil(String time) {
    return 'In pausa fino alle $time';
  }

  @override
  String battery(int n) {
    return 'Batteria $n%';
  }

  @override
  String get phoneSharing =>
      'Stai condividendo la posizione di questo telefono';

  @override
  String phoneLastFix(String time, String meters) {
    return 'Ultima posizione $time · ±$meters m';
  }

  @override
  String get phoneWaitingFix => 'In attesa della prima posizione…';

  @override
  String phoneQueued(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n posizioni da inviare',
      one: '1 posizione da inviare',
    );
    return '$_temp0';
  }

  @override
  String get phoneOpenDevice => 'Condivisione con gli amici e aree';

  @override
  String get phoneLocationOff => 'Attiva la localizzazione del telefono';

  @override
  String get phoneDenied => 'Permesso di posizione negato';

  @override
  String get phoneDeniedForever =>
      'Permesso di posizione negato: abilitalo dalle impostazioni del telefono';

  @override
  String get phoneNotificationTitle => 'Posizione condivisa';

  @override
  String get phoneNotificationText =>
      'L\'app sta inviando la posizione di questo telefono';

  @override
  String get phoneGone =>
      'Il telefono è stato eliminato: condivisione interrotta';

  @override
  String accuracyMeters(String meters) {
    return '±$meters m';
  }

  @override
  String get sharingActive => 'Condivisione attiva';

  @override
  String get removePhone => 'Elimina il telefono';

  @override
  String get removePhoneSub => 'Smette di condividere la posizione';

  @override
  String get removePhoneTitle => 'Eliminare il telefono?';

  @override
  String get removePhoneBody =>
      'Storico, aree, condivisioni e notifiche vengono cancellati.';

  @override
  String get removeVehicle => 'Elimina il veicolo';

  @override
  String get removeVehicleSub => 'Con viaggi, costi e scadenze';

  @override
  String get removeVehicleTitle => 'Eliminare il veicolo?';

  @override
  String get removeVehicleBody =>
      'Storico, costi, scadenze, aree e condivisioni vengono cancellati.';

  @override
  String get friends => 'Amici';

  @override
  String get friendsSub => 'Il tuo codice e le persone con cui condividere';

  @override
  String get friendsHint =>
      'Gli utenti non si vedono tra loro: uno dei due inserisce o inquadra il codice dell\'altro, che riceve una richiesta di amicizia da accettare. Puoi condividere i dispositivi solo con gli amici.';

  @override
  String friendRequested(String name) {
    return 'Richiesta inviata a $name: diventerete amici quando la accetta';
  }

  @override
  String friendRequestReceived(String name) {
    return '$name ti ha inviato una richiesta di amicizia';
  }

  @override
  String get requestsReceived => 'Richieste ricevute';

  @override
  String get requestsSent => 'Richieste inviate';

  @override
  String requestedOn(String date) {
    return 'Richiesta del $date';
  }

  @override
  String get requestWaiting => 'In attesa di risposta';

  @override
  String get accept => 'Accetta';

  @override
  String get decline => 'Rifiuta';

  @override
  String get withdraw => 'Ritira';

  @override
  String get errTooManyRequests =>
      'Hai già 20 richieste in attesa: aspetta una risposta o ritirane qualcuna';

  @override
  String get yourCode => 'Il tuo codice';

  @override
  String get codeCopied => 'Codice copiato';

  @override
  String get newCode => 'Nuovo codice';

  @override
  String get newCodeTitle => 'Generare un nuovo codice?';

  @override
  String get newCodeBody =>
      'Il codice attuale smette di funzionare. Gli amici che hai restano.';

  @override
  String get addFriend => 'Aggiungi un amico';

  @override
  String get friendCode => 'Codice dell\'amico';

  @override
  String get scanFriend => 'Inquadra il QR dell\'amico';

  @override
  String get friendCodeUnknown => 'Nessun utente con questo codice';

  @override
  String friendAdded(String name) {
    return '$name è ora tuo amico';
  }

  @override
  String friendAddedYou(String name) {
    return '$name ha accettato la tua richiesta di amicizia';
  }

  @override
  String get noFriends => 'Nessun amico ancora';

  @override
  String friendsSince(String date) {
    return 'Amici dal $date';
  }

  @override
  String get removeFriend => 'Rimuovi';

  @override
  String removeFriendTitle(String name) {
    return 'Rimuovere $name dagli amici?';
  }

  @override
  String get removeFriendBody =>
      'Le condivisioni tra voi due terminano, in entrambe le direzioni.';

  @override
  String get friendRemoved => 'Amico rimosso';

  @override
  String get filterMine => 'Miei';

  @override
  String get filterShared => 'Condivisi con me';

  @override
  String get filterMoving => 'In movimento';

  @override
  String get filterParked => 'Fermi';

  @override
  String get filterOffline => 'Non raggiungibili';

  @override
  String get filterTrackers => 'Veicoli';

  @override
  String get filterPhones => 'Telefoni';

  @override
  String get filterAllOwners => 'Tutti i proprietari';

  @override
  String filterOwner(String name) {
    return 'Di $name';
  }

  @override
  String get searchDevices => 'Cerca per nome';

  @override
  String shownCount(int n, int total) {
    return '$n di $total';
  }

  @override
  String get fitAll => 'Inquadra quelli filtrati';

  @override
  String get noMatch => 'Nessun dispositivo con questi filtri';

  @override
  String get resetFilters => 'Azzera i filtri';

  @override
  String get filters => 'Filtri';

  @override
  String get kindBatteryHealth => 'Batteria dell\'auto da controllare';

  @override
  String notificationBodyBatteryHealth(String device, String v) {
    return '$device: tensione a riposo media $v V';
  }

  @override
  String get kindMaintenance => 'Scadenze dell\'auto';

  @override
  String maintenanceDueTitle(String name) {
    return 'Scadenza: $name';
  }

  @override
  String maintenanceSoonTitle(String name) {
    return 'Scadenza vicina: $name';
  }

  @override
  String inDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n giorni',
      one: '1 giorno',
    );
    return 'tra $_temp0';
  }

  @override
  String get today => 'oggi';

  @override
  String overdueDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n giorni',
      one: '1 giorno',
    );
    return 'scaduta da $_temp0';
  }

  @override
  String inKm(String km) {
    return 'tra $km km';
  }

  @override
  String kmOver(String km) {
    return 'superata di $km km';
  }

  @override
  String get orJoin => ' o ';

  @override
  String get mkService => 'Tagliando';

  @override
  String get mkInspection => 'Revisione';

  @override
  String get mkInsurance => 'Assicurazione';

  @override
  String get mkTax => 'Bollo';

  @override
  String get mkTyres => 'Cambio gomme';

  @override
  String get mkOther => 'Personalizzata';

  @override
  String get maintenance => 'Scadenze e manutenzione';

  @override
  String get maintenanceHint =>
      'Tagliando a km, revisione, assicurazione e bollo a data, o scadenze personalizzate: ti avvisa prima della scadenza.';

  @override
  String get odometer => 'Contachilometri';

  @override
  String get odometerUnset =>
      'Inserisci la lettura del contachilometri per le scadenze a km';

  @override
  String odometerValue(String km) {
    return '$km km';
  }

  @override
  String get odometerHint =>
      'Lettura attuale del cruscotto: poi si aggiorna da sola con i km dei viaggi. Puoi correggerla quando vuoi, ad esempio se il tracker è rimasto spento.';

  @override
  String get addDeadline => 'Nuova scadenza';

  @override
  String get editDeadline => 'Modifica scadenza';

  @override
  String get deadlineKind => 'Tipo';

  @override
  String get deadlineTitle => 'Descrizione (facoltativa)';

  @override
  String get deadlineTitleRequired =>
      'Descrizione (es. bollino blu, estintore)';

  @override
  String get deadlineNeedsTitle =>
      'Scrivi una descrizione per la scadenza personalizzata';

  @override
  String get deadlineDate => 'Data di scadenza';

  @override
  String get deadlineNoDate => 'Nessuna data';

  @override
  String get deadlineKm => 'Scadenza a km';

  @override
  String get deadlineEveryMonths => 'Si ripete ogni (mesi)';

  @override
  String get deadlineEveryKm => 'Si ripete ogni (km)';

  @override
  String get deadlineRemindDays => 'Avvisa giorni prima';

  @override
  String get deadlineRemindKm => 'Avvisa km prima';

  @override
  String get deadlineNote => 'Note';

  @override
  String get deadlineNeedsDue => 'Indica una data o i km';

  @override
  String get deadlineDone => 'Fatto';

  @override
  String deadlineDoneTitle(String name) {
    return 'Segna come fatto: $name';
  }

  @override
  String get deadlineDoneKm => 'Km al momento';

  @override
  String get deadlineDoneHint =>
      'Le scadenze ricorrenti si spostano in avanti, le altre si chiudono.';

  @override
  String deadlineEvery(String text) {
    return 'ogni $text';
  }

  @override
  String monthsShort(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n mesi',
      one: '1 mese',
    );
    return '$_temp0';
  }

  @override
  String get noDeadlines => 'Nessuna scadenza';

  @override
  String get maintenanceLog => 'Fatti';

  @override
  String get deleteDeadline => 'Eliminare la scadenza?';

  @override
  String get invalidNumber => 'Numero non valido';

  @override
  String get trends => 'Statistiche nel tempo';

  @override
  String get trendsMonths => '12 mesi';

  @override
  String get trendsWeeks => '26 settimane';

  @override
  String get trendsKm => 'Km percorsi';

  @override
  String trendsKmSplit(String work, String own) {
    return 'Lavoro $work km · personali $own km nel periodo';
  }

  @override
  String get trendsDriving => 'Ore di guida';

  @override
  String get trendsTrips => 'Viaggi';

  @override
  String get trendsVoltage => 'Tensione a riposo della batteria';

  @override
  String get trendsVoltageSub =>
      'Media dei giorni, a motore spento da almeno 2 ore';

  @override
  String get trendsSim => 'Dati sulla SIM';

  @override
  String get trendsAlarms => 'Allarmi';

  @override
  String get batteryHealth => 'Salute della batteria dell\'auto';

  @override
  String batteryGood(String v) {
    return 'Buona: $v V a riposo';
  }

  @override
  String batteryFair(String v) {
    return 'Da tenere d\'occhio: $v V a riposo';
  }

  @override
  String batteryLow(String v) {
    return 'Debole: $v V a riposo, falla controllare';
  }

  @override
  String get batteryUnknown => 'Servono alcuni giorni di soste per valutarla';

  @override
  String batteryTrend(String v) {
    return 'Andamento: $v V al mese';
  }

  @override
  String get tripPurpose => 'Tipo di viaggio';

  @override
  String get purposeBusiness => 'Lavoro';

  @override
  String get purposePersonal => 'Personale';

  @override
  String get purposeNone => 'Non indicato';

  @override
  String get tripNote => 'Nota';

  @override
  String get logbook => 'Registro viaggi del mese';

  @override
  String get logbookHint =>
      'CSV con viaggi, tipo, note e costi, totali lavoro e personali';

  @override
  String get walkTo => 'Raggiungi a piedi';

  @override
  String get openFailed => 'Impossibile aprire il collegamento';

  @override
  String get tripCosts => 'Costi dei viaggi';

  @override
  String get refuels => 'Rifornimenti';

  @override
  String get addRefuel => 'Aggiungi rifornimento';

  @override
  String get editRefuel => 'Modifica rifornimento';

  @override
  String get refuelSaved => 'Rifornimenti aggiornati';

  @override
  String get noRefuels => 'Nessun rifornimento: aggiungi il primo pieno';

  @override
  String get refuelsHint =>
      'Tra due pieni i litri messi e i km percorsi danno il consumo reale; l\'importo dà il prezzo al litro.';

  @override
  String realConsumption(String value) {
    return 'Consumo reale: $value';
  }

  @override
  String get realConsumptionUnknown =>
      'Consumo reale: servono due pieni con il contachilometri';

  @override
  String lastConsumption(String value) {
    return 'Ultimo pieno: $value';
  }

  @override
  String refuelTotals(int n, String litres, String cost) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n rifornimenti',
      one: '1 rifornimento',
    );
    return '$_temp0, $litres, $cost';
  }

  @override
  String measuredKm(String km) {
    return 'Misurato su $km km';
  }

  @override
  String get refuelPartial => 'parziale';

  @override
  String refuelMeasured(String value, String km) {
    return '$value in $km km';
  }

  @override
  String get refuelRatesOn => 'Prezzi e consumi usati per i costi dei viaggi';

  @override
  String get refuelRatesOff =>
      'Prezzi e consumi non usati per i costi dei viaggi';

  @override
  String get refuelLitres => 'Litri';

  @override
  String get refuelCost => 'Importo pagato';

  @override
  String get refuelOdometer => 'Contachilometri';

  @override
  String get refuelOdometerHint => 'Lettura del cruscotto al momento del pieno';

  @override
  String get refuelFull => 'Pieno';

  @override
  String get refuelFullHint => 'Serbatoio riempito fino allo scatto';

  @override
  String get refuelNote => 'Nota';

  @override
  String get refuelInvalid => 'Litri da 0 a 500, importo da 0 a 10.000 €';

  @override
  String get ratesFromRefuels => 'Prezzo e consumo dai rifornimenti';

  @override
  String get ratesFromRefuelsHint =>
      'Ogni rifornimento aggiunge il prezzo pagato, ogni pieno il consumo misurato';

  @override
  String get rateFromRefuel => 'dai rifornimenti';

  @override
  String get rateFromAverage => 'media nazionale';

  @override
  String get monthlySummary => 'Riepilogo del mese';

  @override
  String get monthlySummarySub =>
      'Km, viaggi, costi e rifornimenti di ogni mese';

  @override
  String get monthlySummaryNotify => 'Notifica a inizio mese';

  @override
  String get monthlySummaryNotifyHint =>
      'Il 1° di ogni mese il riepilogo del mese appena finito';

  @override
  String summaryNotificationTitle(String month) {
    return 'Il tuo mese di $month';
  }

  @override
  String summaryNotificationBody(String km, String trips) {
    return '$km km · $trips';
  }

  @override
  String summaryTrips(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n viaggi',
      one: '1 viaggio',
    );
    return '$_temp0';
  }

  @override
  String get previousMonth => 'Mese precedente';

  @override
  String get nextMonth => 'Mese successivo';

  @override
  String comparedToBefore(String change) {
    return '$change rispetto al mese prima';
  }

  @override
  String get summaryPartial => 'Mese in corso: i dati arrivano fino a oggi';

  @override
  String get summaryEmpty => 'Nessun veicolo';

  @override
  String summaryDriven(String km, int n, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n viaggi',
      one: '1 viaggio',
    );
    return '$km km in $_temp0, $time di guida';
  }

  @override
  String summaryBusiness(String km) {
    return '$km km di lavoro';
  }

  @override
  String summaryCost(String cost) {
    return 'Costi: $cost';
  }

  @override
  String summaryRefuels(int n, String value) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n rifornimenti',
      one: '1 rifornimento',
    );
    return '$_temp0: $value';
  }

  @override
  String summarySim(String size) {
    return 'SIM: $size';
  }

  @override
  String summaryAlarms(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n allarmi',
      one: '1 allarme',
    );
    return '$_temp0';
  }

  @override
  String get kindMonthlySummary => 'Riepilogo del mese';

  @override
  String get costsIntro =>
      'Con consumo, prezzo del carburante e usura ogni viaggio mostra quanto è costato e il registro viaggi del mese aggiunge le colonne dei costi.';

  @override
  String get fuelType => 'Carburante';

  @override
  String get fuelPetrol => 'Benzina';

  @override
  String get fuelDiesel => 'Gasolio';

  @override
  String get fuelLpg => 'GPL';

  @override
  String get fuelOther => 'Altro / non indicato';

  @override
  String get fuelPriceAuto => 'Prezzo dalla media nazionale';

  @override
  String get fuelPriceAutoHint =>
      'Ogni settimana il prezzo medio rilevato dal Ministero dell\'Ambiente (MASE) viene aggiunto allo storico';

  @override
  String get fuelPriceAutoNeedsType =>
      'Scegli il carburante per usare la media nazionale';

  @override
  String nationalAverage(String fuel, String price) {
    return 'Media nazionale $fuel: $price/l';
  }

  @override
  String nationalAverageWeek(String date) {
    return 'Rilevazione MASE della settimana del $date';
  }

  @override
  String get useAverage => 'Usa';

  @override
  String get ratesHint =>
      'Prezzo, consumo e usura possono cambiare nel tempo: ogni valore vale dalla sua data fino al successivo e ogni viaggio usa i valori del giorno in cui è stato fatto.';

  @override
  String get addValue => 'Nuovo valore';

  @override
  String rateNow(String value) {
    return 'Attuale: $value';
  }

  @override
  String get rateUnset => 'Nessun valore inserito';

  @override
  String get rateTrend => 'Andamento';

  @override
  String get errTooManyRates =>
      'Troppi valori nello storico: eliminane qualcuno';

  @override
  String get vehicleModel => 'Modello del veicolo';

  @override
  String get vehicleModelHint => 'es. Fiat Panda 1.2 benzina';

  @override
  String get consumption => 'Consumo';

  @override
  String get consumptionUnit => 'Unità del consumo';

  @override
  String get fuelPrices => 'Prezzo del carburante';

  @override
  String validFrom(String date) {
    return 'dal $date';
  }

  @override
  String get priceDate => 'Cambia data';

  @override
  String get wearPerKm => 'Usura del veicolo';

  @override
  String get wearHint =>
      'Pneumatici, manutenzione e svalutazione per km, senza il carburante: dalle tabelle ACI del modello o una tua stima';

  @override
  String get extraData => 'Dati aggiuntivi';

  @override
  String get extraIntro =>
      'Dati letti dal tracker da un\'altra scheda del veicolo, mostrati così come arrivano.';

  @override
  String get extraEmpty => 'Nessun dato aggiuntivo ricevuto';

  @override
  String get extraLatest => 'Valori più recenti';

  @override
  String extraReadings(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n letture',
      one: '1 lettura',
    );
    return '$_temp0';
  }

  @override
  String extraFields(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n campi',
      one: '1 campo',
    );
    return '$_temp0';
  }

  @override
  String get autoUpdate => 'Aggiornamenti automatici';

  @override
  String get autoUpdateNever =>
      'Questo firmware non controlla gli aggiornamenti: i firmware personalizzati li hanno disattivati (AUTO_UPDATE 0)';

  @override
  String autoUpdateChecked(String time) {
    return 'Il tracker controlla ogni giorno e installa le versioni ufficiali (circa 1,3 MB di SIM ciascuna) · ultimo controllo $time';
  }

  @override
  String get firmwareAutomatic => 'automatico';

  @override
  String get kindFirmware => 'Nuovo firmware';

  @override
  String firmwareNewTitle(String version) {
    return 'Nuovo firmware $version';
  }

  @override
  String firmwareNewAutomatic(String device) {
    return '$device lo installerà da solo entro un giorno';
  }

  @override
  String firmwareNewManual(String device) {
    return 'Installalo su $device dalla pagina del dispositivo';
  }

  @override
  String appUpdateAvailable(String version) {
    return 'È disponibile la versione $version dell\'app';
  }

  @override
  String get download => 'Scarica';

  @override
  String get searchAci => 'Cerca il costo chilometrico ACI';

  @override
  String costPerKm(String cost) {
    return 'Costo stimato: $cost/km';
  }

  @override
  String get costPerKmUnset =>
      'Inserisci consumo e prezzo o l\'usura per calcolare i costi';

  @override
  String get costsSaved => 'Costi salvati';

  @override
  String valueRange(String min, String max) {
    return 'Valore tra $min e $max';
  }

  @override
  String costFuel(String cost) {
    return 'carburante $cost';
  }

  @override
  String costWear(String cost) {
    return 'usura $cost';
  }

  @override
  String get kpiCost => 'Costo stimato';

  @override
  String get kpiFuel => 'Carburante';

  @override
  String get backups => 'Backup del database';

  @override
  String backupLast(String time, String size) {
    return 'Ultimo: $time · $size';
  }

  @override
  String backupFiles(int n, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n copie',
      one: '1 copia',
    );
    return '$_temp0, $size in totale';
  }

  @override
  String backupOffsite(String time) {
    return 'Copia fuori dal server: $time';
  }

  @override
  String get backupNoOffsite => 'Nessuna copia fuori dal server';

  @override
  String get backupStale => 'Nessun backup riuscito nelle ultime 26 ore';

  @override
  String backupVerifyOk(String time) {
    return 'Prova di ripristino riuscita: $time';
  }

  @override
  String backupVerifyFailed(String time) {
    return 'Prova di ripristino FALLITA: $time';
  }

  @override
  String get backupVerifyOld =>
      'Nessuna prova di ripristino negli ultimi 9 giorni';

  @override
  String get backupNoVerify => 'Nessuna prova di ripristino finora';

  @override
  String get navDashboards => 'Dashboard';

  @override
  String get errTooManyDashboards =>
      'Hai già il numero massimo di dashboard (20)';

  @override
  String get dashboardNew => 'Nuova dashboard';

  @override
  String get dashboardName => 'Nome della dashboard';

  @override
  String get dashboardEmpty =>
      'Nessuna dashboard. Creane una vuota o parti da un modello: potrai cambiare ogni widget.';

  @override
  String get dashboardNoWidgets =>
      'Dashboard vuota: aggiungi un widget con Modifica.';

  @override
  String get templateBlank => 'Vuota';

  @override
  String get templateOverview => 'Panoramica dei veicoli';

  @override
  String get templateDiagnostics => 'Diagnostica dei tracker';

  @override
  String get dashboardEdit => 'Modifica';

  @override
  String get dashboardRename => 'Rinomina';

  @override
  String get dashboardDelete => 'Elimina dashboard';

  @override
  String dashboardDeleteBody(String name) {
    return 'Eliminare la dashboard «$name»? I dati dei veicoli restano.';
  }

  @override
  String get dashboardSaved => 'Dashboard salvata';

  @override
  String get dashboardDiscard => 'Uscire senza salvare le modifiche?';

  @override
  String get discard => 'Esci senza salvare';

  @override
  String get dashboardPeriod => 'Periodo';

  @override
  String get widgetAdd => 'Aggiungi widget';

  @override
  String get widgetEdit => 'Modifica widget';

  @override
  String get widgetDuplicate => 'Duplica';

  @override
  String get widgetRemove => 'Rimuovi';

  @override
  String get widgetMetric => 'Dato';

  @override
  String get widgetExtraKey => 'Campo dei dati aggiuntivi';

  @override
  String get widgetExtraKeyHint =>
      'Il nome come appare in Dati aggiuntivi, es. rpm';

  @override
  String get widgetView => 'Visualizzazione';

  @override
  String get widgetDevices => 'Veicoli';

  @override
  String get widgetAllDevices => 'Tutti i miei veicoli attivi';

  @override
  String get widgetAllDevicesSub =>
      'Anche quelli aggiunti in futuro, non gli archiviati';

  @override
  String get widgetDevicesNeeded => 'Scegli almeno un veicolo';

  @override
  String get widgetKeyNeeded => 'Scrivi il nome del campo';

  @override
  String get widgetPeriod => 'Periodo';

  @override
  String get widgetPeriodDashboard => 'Come la dashboard';

  @override
  String get widgetAgg => 'Valore';

  @override
  String get widgetBucket => 'Raggruppamento';

  @override
  String get widgetTitle => 'Titolo (facoltativo)';

  @override
  String get widgetWidth => 'Larghezza';

  @override
  String get widgetHeight => 'Altezza';

  @override
  String get widgetPreview => 'Anteprima';

  @override
  String widgetUnavailable(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n veicoli non più disponibili',
      one: '1 veicolo non più disponibile',
    );
    return '$_temp0';
  }

  @override
  String get widgetNoDevices => 'Nessun veicolo disponibile per questo dato';

  @override
  String get widgetPeriodTooLong => 'Periodo troppo lungo per questo dato';

  @override
  String widgetVehicles(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n veicoli',
      one: '1 veicolo',
    );
    return '$_temp0';
  }

  @override
  String get widgetNoDeadlines => 'Nessuna scadenza';

  @override
  String widgetSize(int w, int h) {
    return '$w × $h';
  }

  @override
  String get groupTrips => 'Viaggi';

  @override
  String get groupCosts => 'Costi';

  @override
  String get groupTracker => 'Dati del tracker';

  @override
  String get groupState => 'Stato attuale';

  @override
  String get mDistance => 'Km percorsi';

  @override
  String get mBusinessKm => 'Km di lavoro';

  @override
  String get mPersonalKm => 'Km personali';

  @override
  String get mDriving => 'Tempo di guida';

  @override
  String get mTrips => 'Numero di viaggi';

  @override
  String get mMaxSpeed => 'Velocità massima';

  @override
  String get mAlarms => 'Allarmi';

  @override
  String get mTraffic => 'Dati sulla SIM';

  @override
  String get mRestVoltage => 'Batteria a riposo';

  @override
  String get mCost => 'Costo stimato';

  @override
  String get mFuelCost => 'Spesa carburante';

  @override
  String get mWearCost => 'Usura';

  @override
  String get mFuel => 'Litri di carburante';

  @override
  String get mRefuelCost => 'Spesa dei rifornimenti';

  @override
  String get mRefuelLitres => 'Litri riforniti';

  @override
  String get mRefuelPrice => 'Prezzo pagato al litro';

  @override
  String get mRealConsumption => 'Consumo reale';

  @override
  String get mSpeed => 'Velocità in movimento';

  @override
  String get mAltitude => 'Altitudine';

  @override
  String get mSignal => 'Segnale LTE';

  @override
  String get mSatellites => 'Satelliti';

  @override
  String get mVoltage => 'Tensione';

  @override
  String get mTemperature => 'Temperatura';

  @override
  String get mPressure => 'Pressione';

  @override
  String get mExtra => 'Dato aggiuntivo';

  @override
  String get mOdometer => 'Contachilometri';

  @override
  String get mDeadlines => 'Scadenze';

  @override
  String get mStatus => 'Posizione e stato';

  @override
  String get viewNumber => 'Numero';

  @override
  String get viewLine => 'Linea nel tempo';

  @override
  String get viewBars => 'Barre nel tempo';

  @override
  String get viewVehicles => 'Barre per veicolo';

  @override
  String get viewTable => 'Tabella per veicolo';

  @override
  String get viewList => 'Elenco';

  @override
  String get viewMap => 'Mappa';

  @override
  String get aggAvg => 'Media';

  @override
  String get aggMin => 'Minimo';

  @override
  String get aggMax => 'Massimo';

  @override
  String get aggLast => 'Ultimo valore';

  @override
  String get groupAuto => 'Automatico';

  @override
  String get groupHour => 'Ore';

  @override
  String get groupDay => 'Giorni';

  @override
  String get groupWeek => 'Settimane';

  @override
  String get groupMonth => 'Mesi';

  @override
  String get periodToday => 'Oggi';

  @override
  String get period12m => 'Ultimi 12 mesi';

  @override
  String get periodYtd => 'Da inizio anno';

  @override
  String get dashboardSetCurrent => 'Imposta come corrente';

  @override
  String get dashboardUnsetCurrent => 'Non più corrente';

  @override
  String get dashboardCurrent => 'Dashboard corrente';

  @override
  String dashboardCurrentSet(String name) {
    return '«$name» è la dashboard corrente: la vedi nell\'analisi di ogni veicolo';
  }

  @override
  String get dashboardCurrentUnset =>
      'Nell\'analisi dei veicoli torna quella standard';

  @override
  String get analysisStandard => 'Analisi standard';

  @override
  String get analysisOpenDashboard => 'Apri nelle dashboard';

  @override
  String get analysisNoWidgets =>
      'Nessun widget della dashboard corrente vale per questo veicolo';

  @override
  String get dashboardShare => 'Condividi con un amico';

  @override
  String get dashboardShareHint =>
      'L\'amico riceve solo i widget: non i tuoi veicoli né i loro dati. Li userà con i suoi veicoli.';

  @override
  String get dashboardShareNoFriends =>
      'Non hai ancora amici: aggiungili da Account › Amici';

  @override
  String dashboardShared(String name) {
    return 'Dashboard inviata a $name';
  }

  @override
  String dashboardReceived(String name, String dashboard) {
    return '$name ti ha condiviso la dashboard «$dashboard»';
  }

  @override
  String dashboardReceivedWidgets(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n widget',
      one: '1 widget',
    );
    return '$_temp0 · scegli i tuoi veicoli';
  }

  @override
  String get dashboardUse => 'Usa';

  @override
  String get dashboardDecline => 'Rifiuta';

  @override
  String get dashboardUseHint =>
      'Su quali dei tuoi veicoli mostrare i widget? Quelli che non valgono per un veicolo (es. dati del tracker su un\'auto senza tracker) usano gli altri scelti.';

  @override
  String get dashboardUseNoVehicles => 'Scegli almeno un veicolo';

  @override
  String dashboardAdded(String name) {
    return 'Dashboard «$name» aggiunta';
  }

  @override
  String get errTooManyDashboardShares =>
      'Il tuo amico ha già troppe dashboard da guardare: riprova più tardi';

  @override
  String get platformLog => 'Log della piattaforma';

  @override
  String get platformLogSub =>
      'Errori, avvisi, richieste e query lente, per migliorare la piattaforma';

  @override
  String get logErrors => 'Errori';

  @override
  String get logWarnings => 'Avvisi';

  @override
  String get logSlowRequests => 'Richieste lente';

  @override
  String get logSlowQueries => 'Query lente';

  @override
  String get logEmpty => 'Niente da segnalare nel periodo';

  @override
  String logTimes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n volte',
      one: '1 volta',
    );
    return '$_temp0';
  }

  @override
  String logLast(String ago) {
    return 'ultima $ago';
  }

  @override
  String logDurations(String avg, String max) {
    return 'media $avg · max $max';
  }

  @override
  String logCalls(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n esecuzioni',
      one: '1 esecuzione',
    );
    return '$_temp0';
  }

  @override
  String logFirst(String time) {
    return 'Prima volta: $time';
  }

  @override
  String logRequestsHint(int ms, int n) {
    return 'Richieste oltre $ms ms, per percorso. Conservati $n giorni.';
  }

  @override
  String logQueriesHint(int ms, int n) {
    return 'Query con durata media oltre $ms ms (o massima 10 volte tanto), rilevate ogni ora. Conservati $n giorni.';
  }

  @override
  String logErrorsHint(int n) {
    return 'Errori e avvisi del backend, uguali raggruppati. Conservati $n giorni.';
  }

  @override
  String get logQueriesOff =>
      'Le query lente non vengono raccolte: il database deve caricare pg_stat_statements (vedi la documentazione del server).';

  @override
  String get logCopied => 'Dettagli copiati';
}
