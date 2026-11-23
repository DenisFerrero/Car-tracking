// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Car Tracking';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get done => 'Done';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get continueLabel => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get open => 'Open';

  @override
  String get verify => 'Verify';

  @override
  String get noData => 'No data in the period';

  @override
  String get operationCancelled => 'Operation cancelled';

  @override
  String get you => 'you';

  @override
  String get nameLabel => 'Name';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get notAvailable => 'n/a';

  @override
  String get navMap => 'Map';

  @override
  String get navDevices => 'Devices';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navAccount => 'Account';

  @override
  String get never => 'never';

  @override
  String get now => 'now';

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String daysAgo(int n) {
    return '$n d ago';
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
  String get qualityExcellent => 'Excellent';

  @override
  String get qualityGood => 'Good';

  @override
  String get qualityPoor => 'Poor';

  @override
  String get qualityBad => 'Bad';

  @override
  String get qualityWeak => 'Weak';

  @override
  String get qualityNone => 'None';

  @override
  String get statusMoving => 'Moving';

  @override
  String get statusEngineOff => 'Engine off';

  @override
  String get statusParked => 'Parked';

  @override
  String get statusAlarm => 'Alarm';

  @override
  String get eventMotion => 'Motion';

  @override
  String get eventTilt => 'Tilt';

  @override
  String get eventPowerLost => 'Power disconnected';

  @override
  String get eventLowBattery => 'Low battery';

  @override
  String get kindMotion => 'Motion while parked';

  @override
  String get kindTilt => 'Car lifted or tilted';

  @override
  String get kindPowerLost => 'Power disconnected';

  @override
  String get kindLowBattery => 'Car battery low';

  @override
  String get kindOffline => 'Tracker unreachable';

  @override
  String get kindOnline => 'Tracker reachable again';

  @override
  String kindGeofenceEnter(String device) {
    return '$device has arrived';
  }

  @override
  String kindGeofenceExit(String device) {
    return '$device has left';
  }

  @override
  String notificationBodyAt(String device, String time) {
    return '$device, at $time';
  }

  @override
  String notificationBodyEnter(String area, String time) {
    return 'Entered $area at $time';
  }

  @override
  String notificationBodyExit(String area, String time) {
    return 'Left $area at $time';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get errNetwork => 'Server unreachable';

  @override
  String get errInvalidCredentials => 'Wrong email or password';

  @override
  String get errLocked => 'Too many attempts: account temporarily locked';

  @override
  String get errInvalidCode => 'Invalid code';

  @override
  String get errEnrollExpired => 'Setup expired: start again';

  @override
  String get errStepUp => 'The authenticator code is required';

  @override
  String get errInvalidPassword => 'Wrong current password';

  @override
  String get errEmailTaken => 'An account with this email already exists';

  @override
  String get errSelf => 'You can\'t do this on your own account';

  @override
  String get errInvalidPairing => 'Wrong IMEI or pairing code';

  @override
  String get errAlreadyClaimed => 'The tracker belongs to another account';

  @override
  String get errOwnerOnly => 'Only the owner can do this';

  @override
  String get errShareSelf => 'You already own this device';

  @override
  String get errTooManyShares => 'Too many shares for this device';

  @override
  String get errOwnerCannotLeave => 'The owner removes the tracker instead';

  @override
  String get errTooManyAreas => 'At most 20 areas per device';

  @override
  String get errTooManyPhones => 'At most 5 phones per account';

  @override
  String get errTooManyVehicles => 'At most 10 vehicles per account';

  @override
  String get errNotATracker => 'Only for trackers';

  @override
  String get errFriendSelf => 'This is your own code';

  @override
  String get errTooManyFriends => 'At most 200 friends';

  @override
  String get errLiveTooLong => 'Live tracking lasts 2 hours at most';

  @override
  String get errPeriodTooLong => 'Period of 93 days at most';

  @override
  String get errRateLimited => 'Too many requests: retry shortly';

  @override
  String get errNotFound => 'Not found';

  @override
  String get errValidation => 'Invalid data';

  @override
  String get errInvalidPasskey => 'Invalid passkey';

  @override
  String get errChallengeExpired => 'Request expired: try again';

  @override
  String get errUnauthorized => 'Session expired: log in again';

  @override
  String get errForbidden => 'Operation not allowed';

  @override
  String errGeneric(int status) {
    return 'Error $status';
  }

  @override
  String get serverAddress => 'Address of your platform';

  @override
  String get serverLabel => 'Server';

  @override
  String get serverUnreachable => 'Server unreachable or not compatible';

  @override
  String get loginPasskey => 'Log in with a passkey';

  @override
  String get loginPassword => 'Log in with password';

  @override
  String get or => 'or';

  @override
  String get passkeyNotCompleted => 'Passkey login not completed';

  @override
  String serverChange(String host) {
    return 'Server: $host · change';
  }

  @override
  String get mfaTitle => 'Two-step verification';

  @override
  String get mfaTotpHint => 'Enter the 6-digit code of the authenticator app';

  @override
  String get mfaRecoveryHint => 'Enter one of your saved recovery codes';

  @override
  String get useAuthenticator => 'Use the authenticator app';

  @override
  String get useRecoveryCode => 'Use a recovery code';

  @override
  String recoveryCodesLeft(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n recovery codes left',
      one: '1 recovery code left',
    );
    return '$_temp0: generate new ones from your account';
  }

  @override
  String get inviteInvalid => 'Invalid invite';

  @override
  String get goToLogin => 'Go to login';

  @override
  String get resetTitle => 'Access reset';

  @override
  String welcome(String name) {
    return 'Welcome, $name';
  }

  @override
  String inviteHint(String email) {
    return '$email\nChoose a password of at least 12 characters, then you\'ll set up the authenticator app.';
  }

  @override
  String get newPassword => 'New password';

  @override
  String get repeatPassword => 'Repeat password';

  @override
  String get passwordTooShort => 'The password needs at least 12 characters';

  @override
  String get passwordsDiffer => 'The passwords don\'t match';

  @override
  String get sessionExpired => 'Session expired';

  @override
  String get loginAgain => 'Log in again';

  @override
  String get enrollTitle => 'Set up two-step verification';

  @override
  String get enrollHint =>
      'Mandatory. Scan the code with an authenticator app (Aegis, Google Authenticator, 2FAS...) and enter the generated code.';

  @override
  String get keyCopied => 'Key copied';

  @override
  String get copyKey => 'Copy the key';

  @override
  String get activate => 'Activate';

  @override
  String get recoveryTitle => 'Recovery codes';

  @override
  String get recoveryHint =>
      'Keep them somewhere safe: each one allows a login if you lose your phone. They won\'t be shown again.';

  @override
  String get codesCopied => 'Codes copied';

  @override
  String get codesSaved => 'I saved the codes';

  @override
  String get createPasskey => 'Create a passkey (fingerprint)';

  @override
  String get later => 'Later';

  @override
  String get passkeyCreated =>
      'Passkey created: you can log in with your fingerprint';

  @override
  String get passkeyNotCreated => 'Passkey not created';

  @override
  String get defaultPasskeyBrowser => 'Browser';

  @override
  String get defaultPasskeyPhone => 'Phone';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get add => 'Add';

  @override
  String get noDevices =>
      'No devices. Add your tracker with the code on its label.';

  @override
  String get noDevicesShort => 'No devices';

  @override
  String get addYourTracker => 'Add your tracker';

  @override
  String get waitingFirstContact => 'Waiting for the first connection';

  @override
  String get noPosition => 'No position';

  @override
  String sharedBy(String name) {
    return 'shared by $name';
  }

  @override
  String signalTooltip(String quality) {
    return 'Signal $quality';
  }

  @override
  String satellitesTooltip(String quality) {
    return 'Satellites $quality';
  }

  @override
  String get fromCell => 'position from the cell';

  @override
  String get lastKnown => 'last known position';

  @override
  String get device => 'Device';

  @override
  String get tabLive => 'Live';

  @override
  String get tabHistory => 'History';

  @override
  String get tabAnalysis => 'Analysis';

  @override
  String get tabAreas => 'Areas';

  @override
  String get tabSettings => 'Settings';

  @override
  String get last24h => '24 hours';

  @override
  String get periodLast24h => 'Last 24 hours';

  @override
  String get periodLast7d => 'Last 7 days';

  @override
  String get periodLast30d => 'Last 30 days';

  @override
  String get periodLast90d => 'Last 90 days';

  @override
  String get periodCustom => 'Custom range';

  @override
  String accessRevoked(String device) {
    return 'The share of $device has ended';
  }

  @override
  String get leaveShare => 'Stop receiving';

  @override
  String leaveShareTitle(String device) {
    return 'Stop receiving $device?';
  }

  @override
  String get leaveShareBody =>
      'You won\'t see it anymore and your areas on this device are deleted.';

  @override
  String get followOn => 'Follow the vehicle (on)';

  @override
  String get followOff => 'Follow the vehicle';

  @override
  String liveUntil(String time) {
    return 'Live until $time';
  }

  @override
  String get connected => 'Connected';

  @override
  String notConnected(String ago) {
    return 'Not connected · last contact $ago';
  }

  @override
  String get noPositionReceived => 'No position received';

  @override
  String cellEstimate(String meters) {
    return 'estimated from the cell (±$meters m)';
  }

  @override
  String get noFix => 'no GPS fix';

  @override
  String get commandSent => 'Command sent';

  @override
  String get commandQueued =>
      'Command queued: the tracker receives it at the next connection';

  @override
  String get live30 => 'Live 30 min';

  @override
  String get stopLive => 'Stop live';

  @override
  String get locate => 'Locate';

  @override
  String resumeAntitheft(String time) {
    return 'Resume anti-theft (paused until $time)';
  }

  @override
  String get pauseAntitheftTooltip =>
      'Pause the anti-theft (garage, car wash...)';

  @override
  String get pause1h => 'Pause 1 hour';

  @override
  String get pause24h => 'Pause 24 hours';

  @override
  String get pause7d => 'Pause 7 days';

  @override
  String get pauseAntitheft => 'Pause anti-theft';

  @override
  String viewerNotice(String owner, String until) {
    return 'Shared by $owner, view only$until';
  }

  @override
  String viewerUntil(String date) {
    return ' until $date';
  }

  @override
  String get noPositions => 'No positions in the period';

  @override
  String get truncated =>
      'Too many points: first 50,000 shown, shorten the period';

  @override
  String pointsRange(int n, String from, String to) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n points',
      one: '1 point',
    );
    return '$_temp0 from $from to $to';
  }

  @override
  String get noFixShort => 'no fix';

  @override
  String get coloringPlain => 'Track';

  @override
  String get coloringSpeed => 'Speed';

  @override
  String get coloringSignal => 'Signal';

  @override
  String get coloringSatellites => 'Satellites';

  @override
  String get legendNoFix => '4 sat / no fix';

  @override
  String get kpiDistance => 'Distance';

  @override
  String get kpiDriving => 'Driving';

  @override
  String get kpiMaxSpeed => 'Max speed';

  @override
  String get kpiTrips => 'Trips';

  @override
  String get kmPerDay => 'Km per day';

  @override
  String get drivingPerDay => 'Driving time per day';

  @override
  String tripsList(int n) {
    return 'Trips ($n)';
  }

  @override
  String tripDetail(String km, String duration, String avg, String max) {
    return '$km km · $duration · avg $avg km/h · max $max km/h';
  }

  @override
  String get bucket2m => '2 minutes';

  @override
  String get bucket10m => '10 minutes';

  @override
  String get bucket1h => 'hour';

  @override
  String get bucket6h => '6 hours';

  @override
  String get bucket1d => 'day';

  @override
  String get chartSpeed => 'Speed';

  @override
  String chartSpeedSub(String bucket) {
    return 'average and maximum every $bucket';
  }

  @override
  String get seriesMax => 'Maximum';

  @override
  String get seriesAvgMoving => 'Average while moving';

  @override
  String get chartSignal => 'LTE signal';

  @override
  String get chartSignalSub => 'below -105 dBm the connection becomes unstable';

  @override
  String get seriesAvg => 'Average';

  @override
  String get seriesMin => 'Minimum';

  @override
  String get thresholdPoor => 'poor';

  @override
  String get chartSatellites => 'Satellites in use';

  @override
  String get chartSatellitesSub => 'below 6 the position is imprecise';

  @override
  String get thresholdWeakFix => 'weak fix';

  @override
  String get chartAltitude => 'Altitude';

  @override
  String get chartBattery => 'Car battery';

  @override
  String get chartBatterySub =>
      'minimum and average voltage: below 11.8 V with the engine off the battery is low';

  @override
  String get chartTemperature => 'Cabin temperature';

  @override
  String get chartPressure => 'Atmospheric pressure';

  @override
  String get chartPoints => 'Points received';

  @override
  String get chartPointsSub => 'in red those without GPS fix';

  @override
  String get seriesPoints => 'Points';

  @override
  String get seriesNoFix => 'No fix';

  @override
  String get chartFixQuality => 'Position quality';

  @override
  String get fixGood => 'Good fix';

  @override
  String get fixWeak => 'Weak fix (<6 sat)';

  @override
  String get chartSignalDistribution => 'Signal distribution';

  @override
  String weakSignalShare(int p) {
    return '$p% of the points below -105 dBm';
  }

  @override
  String get chartSatelliteDistribution => 'Satellite distribution';

  @override
  String get chartSpeedDistribution => 'Speed distribution';

  @override
  String get chartSpeedDistributionSub => 'moving points per 10 km/h band';

  @override
  String get chartCoverage => 'Network coverage';

  @override
  String get chartCoverageSub =>
      'average signal per zone: red where the tracker loses the network';

  @override
  String get simMonth => 'SIM data this month';

  @override
  String simUsed(String used, String budget, String projected, int p) {
    return 'Used $used of $budget · end of month estimate $projected ($p%)';
  }

  @override
  String get simEstimate =>
      'Estimate: encrypted frames + TLS/WebSocket headers + connections';

  @override
  String get dataPerDay => 'Data per day';

  @override
  String get dataPerDaySub => 'the line is the daily usage within the plan';

  @override
  String get budget => 'budget';

  @override
  String get deviceName => 'Device name';

  @override
  String get tapToRename => 'Tap to rename';

  @override
  String get imei => 'IMEI';

  @override
  String get modemFirmware => 'Modem and firmware';

  @override
  String firmwareVersion(String v) {
    return 'firmware $v';
  }

  @override
  String get neverConnected => 'never connected';

  @override
  String connectedSince(String date) {
    return 'connected since $date';
  }

  @override
  String get alarmNotifications => 'Alarm notifications';

  @override
  String get sharing => 'Sharing';

  @override
  String get sharingHint =>
      'Recipients see only position, speed and state, without changing anything.';

  @override
  String get shareWith => 'Share with a friend';

  @override
  String get shareTitle => 'Share view only';

  @override
  String get shareFriend => 'Friend';

  @override
  String get noFriendsToShare =>
      'You can share only with friends: add one with their code.';

  @override
  String get goToFriends => 'Go to friends';

  @override
  String get shareDuration => 'Duration';

  @override
  String get permanent => 'Permanent';

  @override
  String hoursShort(int n) {
    return '$n h';
  }

  @override
  String daysShort(int n) {
    return '$n d';
  }

  @override
  String get customEnd => 'Date and time';

  @override
  String endsAt(String date) {
    return 'Until $date';
  }

  @override
  String get share => 'Share';

  @override
  String get shared => 'Device shared';

  @override
  String get noShares => 'Not shared with anyone';

  @override
  String get sharePermanent => 'Permanent';

  @override
  String shareUntil(String date) {
    return 'Until $date';
  }

  @override
  String get changeEnd => 'Change end';

  @override
  String get revoke => 'Revoke';

  @override
  String revokeTitle(String name) {
    return 'Revoke the share of $name?';
  }

  @override
  String get revokeBody =>
      'They won\'t see the device anymore and their areas are deleted.';

  @override
  String get shareRevoked => 'Share revoked';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get removeTracker => 'Delete the vehicle';

  @override
  String get removeTrackerSub => 'With its history; the tracker becomes free';

  @override
  String get removeTrackerTitle => 'Delete the vehicle?';

  @override
  String get removeTrackerBody =>
      'History, km, deadlines, costs, areas, shares and notifications are deleted. The tracker becomes free and can be paired again with the code on the label. To keep the history use «Remove the tracker from the vehicle».';

  @override
  String get errVehicleHasTracker => 'The vehicle has a tracker already';

  @override
  String get pairInHint =>
      'Which vehicle do you install it in? In a vehicle you already have, its history, km and deadlines stay.';

  @override
  String get pairNewVehicle => 'New vehicle';

  @override
  String get trackerSection => 'Tracker';

  @override
  String get moveTracker => 'Move to another vehicle';

  @override
  String get moveTrackerSub => 'This vehicle keeps its history';

  @override
  String get moveTrackerTitle => 'Move the tracker?';

  @override
  String get moveTarget => 'Target vehicle';

  @override
  String get archivePrevious => 'Archive this vehicle';

  @override
  String get move => 'Move';

  @override
  String trackerMoved(String name) {
    return 'Tracker moved to $name';
  }

  @override
  String get detachTracker => 'Remove the tracker from the vehicle';

  @override
  String get detachTrackerSub =>
      'The vehicle stays, the tracker can be paired again';

  @override
  String get detachTrackerTitle => 'Remove the tracker?';

  @override
  String get detachTrackerBody =>
      'The vehicle stays with history, km, deadlines and shares, without a tracker. The tracker can be paired again with the code on the label.';

  @override
  String get trackerDetached => 'Tracker removed';

  @override
  String get archived => 'Archived';

  @override
  String get archiveSub => 'Hidden from the map; history and deadlines stay';

  @override
  String get installations => 'Installed trackers';

  @override
  String installedRange(String from, String to) {
    return 'from $from to $to';
  }

  @override
  String installedSince(String from) {
    return 'since $from';
  }

  @override
  String get areasHint =>
      'Get a notification when the device enters (or leaves) an area: for example when it\'s about to arrive.';

  @override
  String get noAreas => 'No areas';

  @override
  String get addArea => 'Add an area';

  @override
  String get editArea => 'Edit area';

  @override
  String get areaName => 'Area name';

  @override
  String get areaDefaultName => 'Destination';

  @override
  String radius(String distance) {
    return 'Radius: $distance';
  }

  @override
  String get notifyEnter => 'Notify on arrival';

  @override
  String get notifyExit => 'Notify on departure';

  @override
  String get tapMapToPlace => 'Tap the map to move the center';

  @override
  String get areaInside => 'inside';

  @override
  String get areaOutside => 'outside';

  @override
  String areaSummary(String radius, String state) {
    return '$radius · $state';
  }

  @override
  String areaPolygonSummary(int n, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vertices',
      one: '1 vertex',
    );
    return '$_temp0 · $state';
  }

  @override
  String get areaCircle => 'Circle';

  @override
  String get areaPolygon => 'Polygon';

  @override
  String get tapMapToDraw => 'Tap the map to add the vertices of the polygon';

  @override
  String areaVertices(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vertices',
      one: '1 vertex',
      zero: 'No vertices',
    );
    return '$_temp0';
  }

  @override
  String get undoVertex => 'Undo the last one';

  @override
  String get clearVertices => 'Start over';

  @override
  String get areaPolygonTooFew => 'At least 3 vertices are needed';

  @override
  String get errPolygonInvalid =>
      'The sides of the area cross each other or the area is too small';

  @override
  String get errPolygonTooLarge => 'The area is larger than 50 km';

  @override
  String get errTooManyRefuels => 'Too many refuels for this vehicle';

  @override
  String get errRefuelFuture => 'A refuel can\'t be in the future';

  @override
  String deleteAreaTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get areaSaved => 'Area saved';

  @override
  String get addTracker => 'Add tracker';

  @override
  String get scanTitle => 'Scan the QR code of the label';

  @override
  String get stepLabel => 'Tracker label';

  @override
  String get stepLabelSub => 'QR code or IMEI and pairing code';

  @override
  String get stepName => 'Vehicle';

  @override
  String get stepPower => 'Power on';

  @override
  String get stepPowerSub => 'First connection of the tracker';

  @override
  String get stepDone => 'Done';

  @override
  String get labelHint =>
      'On the tracker (or its box) there\'s a label with a QR code, the IMEI and the pairing code. The code proves you hold the tracker: keep it private.';

  @override
  String get scanQr => 'Scan the QR code';

  @override
  String get manualEntry => 'or enter the data by hand';

  @override
  String get imeiLabel => 'IMEI (15 digits)';

  @override
  String get pairingCode => 'Pairing code';

  @override
  String get imeiInvalid => 'The IMEI has 15 digits';

  @override
  String get alreadyMine => 'This tracker is already in your account';

  @override
  String get ownedByOther =>
      'The tracker belongs to another account: ask the owner to share it';

  @override
  String get defaultDeviceName => 'My car';

  @override
  String get mapColor => 'Color on the map';

  @override
  String get addToAccount => 'Add to my account';

  @override
  String get insertSim => 'Insert the SIM in the tracker';

  @override
  String get connectPower => 'Connect it to the car power';

  @override
  String get parkOutside => 'Leave the car outdoors';

  @override
  String get firstFixHint => 'The first GPS fix can take a few minutes';

  @override
  String get waitingTracker =>
      'Waiting for the first connection of the tracker...';

  @override
  String get continueLater => 'Continue later';

  @override
  String get trackerConnected =>
      'The tracker is connected. The first position arrives as soon as the car moves or at the next periodic check.';

  @override
  String get openDevice => 'Open the device';

  @override
  String get accountTitle => 'Account';

  @override
  String get editName => 'Edit name';

  @override
  String get language => 'Language';

  @override
  String get administration => 'Administration';

  @override
  String get administrationSub => 'Users, invites, access resets';

  @override
  String get passkeys => 'Passkeys';

  @override
  String passkeyCreatedAgo(String ago) {
    return 'Created $ago';
  }

  @override
  String passkeyUsedAgo(String ago) {
    return ' · used $ago';
  }

  @override
  String get passkeySynced => ' · synced';

  @override
  String get passkeyRemoved => 'Passkey removed';

  @override
  String get addPasskey => 'Add a passkey';

  @override
  String get addPasskeySub => 'Login with fingerprint or screen lock';

  @override
  String get passkeyName => 'Passkey name';

  @override
  String get passkeyAdded => 'Passkey added';

  @override
  String get security => 'Security';

  @override
  String get changePassword => 'Change password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get passwordMin => 'At least 12 characters';

  @override
  String get change => 'Change';

  @override
  String get passwordChanged =>
      'Password changed: the other sessions were closed';

  @override
  String get changeAuthenticator => 'Change authenticator app';

  @override
  String get newPhone => 'New phone';

  @override
  String get newAuthenticator => 'New authenticator app';

  @override
  String get newAppCode => 'Code of the new app';

  @override
  String get authenticatorUpdated => 'Authenticator app updated';

  @override
  String get authenticatorCode => 'Authenticator app code';

  @override
  String get confirmWithCode => 'Confirm with the code';

  @override
  String recoveryLeft(int n) {
    return '$n left · generate new codes';
  }

  @override
  String get newRecoveryCodes => 'New recovery codes';

  @override
  String get newRecoveryHint =>
      'The previous codes are no longer valid. Keep them somewhere safe.';

  @override
  String get activeSessions => 'Active sessions';

  @override
  String get thisSession => ' (this one)';

  @override
  String sessionActive(String ip, String ago) {
    return '$ip · active $ago';
  }

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectOthers => 'Disconnect the other sessions';

  @override
  String get sessionsClosed => 'Sessions closed';

  @override
  String get app => 'App';

  @override
  String get pushTitle => 'Push notifications';

  @override
  String get pushOn => 'On';

  @override
  String get pushOff =>
      'Not configured: notifications arrive only with the app open';

  @override
  String get logout => 'Log out';

  @override
  String get unknownAgent => 'Unknown';

  @override
  String get androidApp => 'Android app';

  @override
  String get invite => 'Invite';

  @override
  String get users => 'Users';

  @override
  String userSummary(String email, int devices, int passkeys) {
    String _temp0 = intl.Intl.pluralLogic(
      devices,
      locale: localeName,
      other: '$devices devices',
      one: '1 device',
    );
    String _temp1 = intl.Intl.pluralLogic(
      passkeys,
      locale: localeName,
      other: '$passkeys passkeys',
      one: '1 passkey',
    );
    return '$email · $_temp0 · $_temp1';
  }

  @override
  String get twoFactorPending => ' · 2FA to set up';

  @override
  String lastLogin(String ago) {
    return ' · login $ago';
  }

  @override
  String get resetAccess => 'Reset access (new password and 2FA)';

  @override
  String get resetLink => 'Reset link';

  @override
  String get enable => 'Enable';

  @override
  String get disable => 'Disable';

  @override
  String get removeAdmin => 'Remove administrator';

  @override
  String get makeAdmin => 'Make administrator';

  @override
  String deleteUserTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteUserBody =>
      'Their devices remain without owner and their shares end.';

  @override
  String get pendingInvites => 'Pending invites';

  @override
  String get none => 'None';

  @override
  String expires(String date) {
    return 'Expires $date';
  }

  @override
  String get cancelInvite => 'Cancel invite';

  @override
  String get inviteUser => 'Invite a user';

  @override
  String get administrator => 'Administrator';

  @override
  String get createInvite => 'Create invite';

  @override
  String get inviteCreated => 'Invite created';

  @override
  String get linkHint =>
      'Send this link to the person: it\'s valid for 72 hours and can be used once.';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get addChooseTitle => 'What do you want to add?';

  @override
  String get addTrackerOption => 'GPS tracker';

  @override
  String get addTrackerOptionSub => 'With the code on its label';

  @override
  String get phoneOption => 'This phone';

  @override
  String get phoneOptionSub =>
      'Share the position of the phone, without hardware';

  @override
  String get vehicleOption => 'Vehicle without a tracker';

  @override
  String get vehicleOptionSub =>
      'The position comes from your phone while you\'re on board';

  @override
  String get addVehicleTitle => 'New vehicle';

  @override
  String get addVehicle => 'Add vehicle';

  @override
  String get vehicleIntro =>
      'When you share from the vehicle, the phone records the trips of the car: costs, kilometers, deadlines and areas like with a tracker, without commands or alarms.';

  @override
  String get vehicleName => 'Name of the vehicle';

  @override
  String get vehicleKind => 'Vehicle, position from the phone';

  @override
  String get vehicleDriving => 'Driving with the phone';

  @override
  String get shareAs => 'Share as';

  @override
  String get shareAsPerson => 'Myself';

  @override
  String get shareAsPersonSub => 'Your position, seen by your friends';

  @override
  String get shareAsVehicleSub =>
      'Trips and costs of the vehicle; your personal position stays still';

  @override
  String shareAsChanged(String name) {
    return 'Now sharing as $name';
  }

  @override
  String get phoneTitle => 'Phone position';

  @override
  String get phoneIntro =>
      'Without a tracker you can share the position of this phone with your friends. The data is less complete than a tracker\'s: no satellites, signal or car battery, and the accuracy depends on the GPS, Wi-Fi and network of the phone.';

  @override
  String get phoneAndroidHint =>
      'Sharing goes on in the background with a fixed notification, also with the app closed. It stops with Stop, by deleting the phone or by logging out.';

  @override
  String get phoneOnlyAndroid =>
      'The position is shared from the Android app: a browser can\'t send it in the background.';

  @override
  String get phoneBackgroundHint =>
      'To resume by itself after a restart of the phone, sharing needs the position allowed \"All the time\".';

  @override
  String get phoneBackgroundAllow => 'Allow all the time';

  @override
  String get phoneChannel => 'Position sharing';

  @override
  String get phoneName => 'Phone name';

  @override
  String phoneDefaultName(String name) {
    return '$name\'s phone';
  }

  @override
  String get phoneStart => 'Start sharing';

  @override
  String get phoneStop => 'Stop';

  @override
  String kindPhoneBattery(String device, int n) {
    return '$device: battery at $n%';
  }

  @override
  String notificationBodyPhoneBattery(String time) {
    return 'Location sharing may stop soon, at $time';
  }

  @override
  String kindLongStop(String device, int h) {
    String _temp0 = intl.Intl.pluralLogic(
      h,
      locale: localeName,
      other: '$h hours',
      one: 'an hour',
    );
    return '$device has been stopped for over $_temp0';
  }

  @override
  String notificationBodyLongStop(String time) {
    return 'Stopped since $time, outside your areas';
  }

  @override
  String get stopAlert => 'Long stop';

  @override
  String get stopAlertHint =>
      'Notifies you if the device stays still for longer than this outside your areas (home, work...). Everyone chooses their own, people it\'s shared with too.';

  @override
  String get stopAlertOff => 'Notification off';

  @override
  String get batteryAlert => 'Low battery';

  @override
  String batteryAlertAt(int n) {
    return 'Notify at $n%';
  }

  @override
  String stopAlertAfter(int h) {
    String _temp0 = intl.Intl.pluralLogic(
      h,
      locale: localeName,
      other: '$h hours',
      one: '1 hour',
    );
    return 'Notify after $_temp0';
  }

  @override
  String get stopAlertAfterOne => 'Notify after an hour';

  @override
  String get areaSchedule => 'Only at certain times';

  @override
  String get areaScheduleHint =>
      'Notifies only on the chosen days and hours; an end before the start goes past midnight.';

  @override
  String areaFrom(String time) {
    return 'From $time';
  }

  @override
  String areaTo(String time) {
    return 'To $time';
  }

  @override
  String get areaAllDay => 'all day';

  @override
  String firmwareAvailable(String version) {
    return 'Firmware $version available';
  }

  @override
  String get firmwareInstall => 'Install';

  @override
  String firmwareInstallTitle(String version) {
    return 'Install firmware $version?';
  }

  @override
  String firmwareInstallBody(String mb) {
    return 'The tracker downloads the update at the next connection ($mb MB of SIM data), verifies it and reboots. If the new firmware can\'t reach the server it goes back to the current one by itself.';
  }

  @override
  String firmwareWaiting(String version) {
    return 'Firmware $version: waiting for the next connection of the tracker';
  }

  @override
  String firmwareDownloading(String version) {
    return 'Downloading firmware $version';
  }

  @override
  String firmwareRebooting(String version) {
    return 'Firmware $version installed, the tracker is rebooting';
  }

  @override
  String firmwareDone(String version) {
    return 'Updated to firmware $version';
  }

  @override
  String firmwareNotApplied(String version) {
    return 'Firmware $version didn\'t start: the tracker went back to the previous version';
  }

  @override
  String firmwareFailed(String version) {
    return 'Update to firmware $version failed: try again';
  }

  @override
  String firmwareUpToDate(String version) {
    return 'Firmware $version, up to date';
  }

  @override
  String get firmwareImages => 'Firmware for the updates';

  @override
  String get firmwareImagesHint =>
      'Uploaded on the server with npm run firmware; the owners install them from the settings of the tracker.';

  @override
  String firmwarePending(int n) {
    return '$n in progress';
  }

  @override
  String get errFirmware => 'This firmware doesn\'t fit the tracker';

  @override
  String get yourData => 'Your data';

  @override
  String get exportData => 'Export my data';

  @override
  String get exportDataSub =>
      'Profile, sign-ins, friends, devices with their positions, areas and notifications in a JSON file';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountSub => 'Deletes the account and the data forever';

  @override
  String get deleteAccountTitle => 'Delete the account?';

  @override
  String get deleteAccountBody =>
      'Deleted forever: the phones and the positions of all your devices, the shares, the friends, the areas and the notifications. The trackers become free and can be paired again with the code of the label. You can export your data first.';

  @override
  String deleteAccountEmail(String email) {
    return 'Type $email to confirm';
  }

  @override
  String get errEmailMismatch => 'The email doesn\'t match';

  @override
  String get errLastAdmin =>
      'You\'re the only administrator: make another user administrator first';

  @override
  String get exportPeriod => 'Export the period';

  @override
  String get exportHint => 'GPX: a track per trip. CSV: every point.';

  @override
  String get phonePauseHour => 'Pause 1 hour';

  @override
  String get phoneResume => 'Resume';

  @override
  String phonePausedUntil(String time) {
    return 'Paused until $time';
  }

  @override
  String battery(int n) {
    return 'Battery $n%';
  }

  @override
  String get phoneSharing => 'You\'re sharing the position of this phone';

  @override
  String phoneLastFix(String time, String meters) {
    return 'Last position $time · ±$meters m';
  }

  @override
  String get phoneWaitingFix => 'Waiting for the first position…';

  @override
  String phoneQueued(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n positions to send',
      one: '1 position to send',
    );
    return '$_temp0';
  }

  @override
  String get phoneOpenDevice => 'Sharing with friends and areas';

  @override
  String get phoneLocationOff => 'Turn on the location of the phone';

  @override
  String get phoneDenied => 'Location permission denied';

  @override
  String get phoneDeniedForever =>
      'Location permission denied: enable it in the settings of the phone';

  @override
  String get phoneNotificationTitle => 'Position shared';

  @override
  String get phoneNotificationText =>
      'The app is sending the position of this phone';

  @override
  String get phoneGone => 'The phone was deleted: sharing stopped';

  @override
  String accuracyMeters(String meters) {
    return '±$meters m';
  }

  @override
  String get sharingActive => 'Sharing on';

  @override
  String get removePhone => 'Delete the phone';

  @override
  String get removePhoneSub => 'Stops sharing the position';

  @override
  String get removePhoneTitle => 'Delete the phone?';

  @override
  String get removePhoneBody =>
      'History, areas, shares and notifications are deleted.';

  @override
  String get removeVehicle => 'Delete the vehicle';

  @override
  String get removeVehicleSub => 'With trips, costs and deadlines';

  @override
  String get removeVehicleTitle => 'Delete the vehicle?';

  @override
  String get removeVehicleBody =>
      'History, costs, deadlines, areas and shares are deleted.';

  @override
  String get friends => 'Friends';

  @override
  String get friendsSub => 'Your code and the people to share with';

  @override
  String get friendsHint =>
      'Users don\'t see each other: one of you types or scans the code of the other, who receives a friend request to accept. You can share devices only with friends.';

  @override
  String friendRequested(String name) {
    return 'Request sent to $name: you become friends when they accept it';
  }

  @override
  String friendRequestReceived(String name) {
    return '$name sent you a friend request';
  }

  @override
  String get requestsReceived => 'Requests received';

  @override
  String get requestsSent => 'Requests sent';

  @override
  String requestedOn(String date) {
    return 'Request of $date';
  }

  @override
  String get requestWaiting => 'Waiting for an answer';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get withdraw => 'Withdraw';

  @override
  String get errTooManyRequests =>
      'You already have 20 pending requests: wait for an answer or withdraw some';

  @override
  String get yourCode => 'Your code';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get newCode => 'New code';

  @override
  String get newCodeTitle => 'Generate a new code?';

  @override
  String get newCodeBody =>
      'The current code stops working. Your friends stay.';

  @override
  String get addFriend => 'Add a friend';

  @override
  String get friendCode => 'Code of the friend';

  @override
  String get scanFriend => 'Scan the QR code of the friend';

  @override
  String get friendCodeUnknown => 'No user with this code';

  @override
  String friendAdded(String name) {
    return '$name is now your friend';
  }

  @override
  String friendAddedYou(String name) {
    return '$name accepted your friend request';
  }

  @override
  String get noFriends => 'No friends yet';

  @override
  String friendsSince(String date) {
    return 'Friends since $date';
  }

  @override
  String get removeFriend => 'Remove';

  @override
  String removeFriendTitle(String name) {
    return 'Remove $name from your friends?';
  }

  @override
  String get removeFriendBody =>
      'The shares between the two of you end, in both directions.';

  @override
  String get friendRemoved => 'Friend removed';

  @override
  String get filterMine => 'Mine';

  @override
  String get filterShared => 'Shared with me';

  @override
  String get filterMoving => 'Moving';

  @override
  String get filterParked => 'Stopped';

  @override
  String get filterOffline => 'Unreachable';

  @override
  String get filterTrackers => 'Vehicles';

  @override
  String get filterPhones => 'Phones';

  @override
  String get filterAllOwners => 'All owners';

  @override
  String filterOwner(String name) {
    return '$name\'s';
  }

  @override
  String get searchDevices => 'Search by name';

  @override
  String shownCount(int n, int total) {
    return '$n of $total';
  }

  @override
  String get fitAll => 'Frame the filtered ones';

  @override
  String get noMatch => 'No device matches the filters';

  @override
  String get resetFilters => 'Reset the filters';

  @override
  String get filters => 'Filters';

  @override
  String get kindBatteryHealth => 'Car battery needs a check';

  @override
  String notificationBodyBatteryHealth(String device, String v) {
    return '$device: mean resting voltage $v V';
  }

  @override
  String get kindMaintenance => 'Car deadlines';

  @override
  String maintenanceDueTitle(String name) {
    return 'Due: $name';
  }

  @override
  String maintenanceSoonTitle(String name) {
    return 'Coming up: $name';
  }

  @override
  String inDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '1 day',
    );
    return 'in $_temp0';
  }

  @override
  String get today => 'today';

  @override
  String overdueDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '1 day',
    );
    return 'overdue by $_temp0';
  }

  @override
  String inKm(String km) {
    return 'in $km km';
  }

  @override
  String kmOver(String km) {
    return '$km km over';
  }

  @override
  String get orJoin => ' or ';

  @override
  String get mkService => 'Service';

  @override
  String get mkInspection => 'Inspection';

  @override
  String get mkInsurance => 'Insurance';

  @override
  String get mkTax => 'Road tax';

  @override
  String get mkTyres => 'Tyre change';

  @override
  String get mkOther => 'Custom';

  @override
  String get maintenance => 'Deadlines and maintenance';

  @override
  String get maintenanceHint =>
      'Service by km, inspection, insurance and tax by date, or custom deadlines: notifies you before they are due.';

  @override
  String get odometer => 'Odometer';

  @override
  String get odometerUnset =>
      'Enter the odometer reading for the deadlines by km';

  @override
  String odometerValue(String km) {
    return '$km km';
  }

  @override
  String get odometerHint =>
      'Current reading on the dashboard: then it follows the km of the trips by itself. You can correct it at any time, e.g. if the tracker was off.';

  @override
  String get addDeadline => 'New deadline';

  @override
  String get editDeadline => 'Edit deadline';

  @override
  String get deadlineKind => 'Kind';

  @override
  String get deadlineTitle => 'Description (optional)';

  @override
  String get deadlineTitleRequired =>
      'Description (e.g. emissions test, fire extinguisher)';

  @override
  String get deadlineNeedsTitle =>
      'Enter a description for the custom deadline';

  @override
  String get deadlineDate => 'Due date';

  @override
  String get deadlineNoDate => 'No date';

  @override
  String get deadlineKm => 'Due at km';

  @override
  String get deadlineEveryMonths => 'Repeats every (months)';

  @override
  String get deadlineEveryKm => 'Repeats every (km)';

  @override
  String get deadlineRemindDays => 'Notify days before';

  @override
  String get deadlineRemindKm => 'Notify km before';

  @override
  String get deadlineNote => 'Notes';

  @override
  String get deadlineNeedsDue => 'Enter a date or the km';

  @override
  String get deadlineDone => 'Done';

  @override
  String deadlineDoneTitle(String name) {
    return 'Mark as done: $name';
  }

  @override
  String get deadlineDoneKm => 'Km at the time';

  @override
  String get deadlineDoneHint =>
      'Recurring deadlines move forward, the others are closed.';

  @override
  String deadlineEvery(String text) {
    return 'every $text';
  }

  @override
  String monthsShort(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String get noDeadlines => 'No deadlines';

  @override
  String get maintenanceLog => 'Done';

  @override
  String get deleteDeadline => 'Delete the deadline?';

  @override
  String get invalidNumber => 'Invalid number';

  @override
  String get trends => 'Statistics over time';

  @override
  String get trendsMonths => '12 months';

  @override
  String get trendsWeeks => '26 weeks';

  @override
  String get trendsKm => 'Km driven';

  @override
  String trendsKmSplit(String work, String own) {
    return 'Business $work km · personal $own km in the period';
  }

  @override
  String get trendsDriving => 'Driving hours';

  @override
  String get trendsTrips => 'Trips';

  @override
  String get trendsVoltage => 'Resting voltage of the battery';

  @override
  String get trendsVoltageSub =>
      'Mean of the days, engine off for at least 2 hours';

  @override
  String get trendsSim => 'Data on the SIM';

  @override
  String get trendsAlarms => 'Alarms';

  @override
  String get batteryHealth => 'Health of the car battery';

  @override
  String batteryGood(String v) {
    return 'Good: $v V at rest';
  }

  @override
  String batteryFair(String v) {
    return 'Keep an eye on it: $v V at rest';
  }

  @override
  String batteryLow(String v) {
    return 'Weak: $v V at rest, have it checked';
  }

  @override
  String get batteryUnknown => 'A few days of stops are needed to assess it';

  @override
  String batteryTrend(String v) {
    return 'Trend: $v V per month';
  }

  @override
  String get tripPurpose => 'Kind of trip';

  @override
  String get purposeBusiness => 'Business';

  @override
  String get purposePersonal => 'Personal';

  @override
  String get purposeNone => 'Not marked';

  @override
  String get tripNote => 'Note';

  @override
  String get logbook => 'Trip log of the month';

  @override
  String get logbookHint =>
      'CSV with trips, kind, notes and costs, business and personal totals';

  @override
  String get walkTo => 'Walk there';

  @override
  String get openFailed => 'Could not open the link';

  @override
  String get tripCosts => 'Trip costs';

  @override
  String get refuels => 'Refuels';

  @override
  String get addRefuel => 'Add refuel';

  @override
  String get editRefuel => 'Edit refuel';

  @override
  String get refuelSaved => 'Refuels updated';

  @override
  String get noRefuels => 'No refuels: add the first full tank';

  @override
  String get refuelsHint =>
      'Between two full tanks the litres put in and the km driven give the real consumption; the amount gives the price per litre.';

  @override
  String realConsumption(String value) {
    return 'Real consumption: $value';
  }

  @override
  String get realConsumptionUnknown =>
      'Real consumption: two full tanks with the odometer are needed';

  @override
  String lastConsumption(String value) {
    return 'Last full tank: $value';
  }

  @override
  String refuelTotals(int n, String litres, String cost) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n refuels',
      one: '1 refuel',
    );
    return '$_temp0, $litres, $cost';
  }

  @override
  String measuredKm(String km) {
    return 'Measured over $km km';
  }

  @override
  String get refuelPartial => 'partial';

  @override
  String refuelMeasured(String value, String km) {
    return '$value over $km km';
  }

  @override
  String get refuelRatesOn => 'Prices and consumptions used for the trip costs';

  @override
  String get refuelRatesOff =>
      'Prices and consumptions not used for the trip costs';

  @override
  String get refuelLitres => 'Litres';

  @override
  String get refuelCost => 'Amount paid';

  @override
  String get refuelOdometer => 'Odometer';

  @override
  String get refuelOdometerHint => 'Reading of the dashboard at the refuel';

  @override
  String get refuelFull => 'Full tank';

  @override
  String get refuelFullHint => 'Tank filled up to the click';

  @override
  String get refuelNote => 'Note';

  @override
  String get refuelInvalid => 'Litres 0 to 500, amount 0 to 10,000 €';

  @override
  String get ratesFromRefuels => 'Price and consumption from the refuels';

  @override
  String get ratesFromRefuelsHint =>
      'Every refuel adds the price paid, every full tank the consumption measured';

  @override
  String get rateFromRefuel => 'from the refuels';

  @override
  String get rateFromAverage => 'national average';

  @override
  String get monthlySummary => 'Monthly summary';

  @override
  String get monthlySummarySub => 'Km, trips, costs and refuels of every month';

  @override
  String get monthlySummaryNotify => 'Notification at the start of the month';

  @override
  String get monthlySummaryNotifyHint =>
      'On the 1st of every month the summary of the month just ended';

  @override
  String summaryNotificationTitle(String month) {
    return 'Your $month';
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
      other: '$n trips',
      one: '1 trip',
    );
    return '$_temp0';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String comparedToBefore(String change) {
    return '$change on the month before';
  }

  @override
  String get summaryPartial => 'Current month: the data go up to today';

  @override
  String get summaryEmpty => 'No vehicles';

  @override
  String summaryDriven(String km, int n, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n trips',
      one: '1 trip',
    );
    return '$km km in $_temp0, $time driving';
  }

  @override
  String summaryBusiness(String km) {
    return '$km km for work';
  }

  @override
  String summaryCost(String cost) {
    return 'Costs: $cost';
  }

  @override
  String summaryRefuels(int n, String value) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n refuels',
      one: '1 refuel',
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
      other: '$n alarms',
      one: '1 alarm',
    );
    return '$_temp0';
  }

  @override
  String get kindMonthlySummary => 'Monthly summary';

  @override
  String get costsIntro =>
      'With consumption, fuel price and wear each trip shows what it cost and the trip log of the month adds the columns of the costs.';

  @override
  String get fuelType => 'Fuel';

  @override
  String get fuelPetrol => 'Petrol';

  @override
  String get fuelDiesel => 'Diesel';

  @override
  String get fuelLpg => 'LPG';

  @override
  String get fuelOther => 'Other / not set';

  @override
  String get fuelPriceAuto => 'Price from the national average';

  @override
  String get fuelPriceAutoHint =>
      'Every week the average price surveyed by the Italian Ministry of the Environment (MASE) is added to the history';

  @override
  String get fuelPriceAutoNeedsType =>
      'Choose the fuel to use the national average';

  @override
  String nationalAverage(String fuel, String price) {
    return 'National average $fuel: $price/l';
  }

  @override
  String nationalAverageWeek(String date) {
    return 'MASE survey of the week of $date';
  }

  @override
  String get useAverage => 'Use';

  @override
  String get ratesHint =>
      'Price, consumption and wear can change over time: each value applies from its date until the next one and each trip uses the values of the day it was made.';

  @override
  String get addValue => 'New value';

  @override
  String rateNow(String value) {
    return 'Current: $value';
  }

  @override
  String get rateUnset => 'No value entered';

  @override
  String get rateTrend => 'Trend';

  @override
  String get errTooManyRates => 'Too many values in the history: delete some';

  @override
  String get vehicleModel => 'Vehicle model';

  @override
  String get vehicleModelHint => 'e.g. Fiat Panda 1.2 petrol';

  @override
  String get consumption => 'Consumption';

  @override
  String get consumptionUnit => 'Unit of the consumption';

  @override
  String get fuelPrices => 'Fuel price';

  @override
  String validFrom(String date) {
    return 'from $date';
  }

  @override
  String get priceDate => 'Change date';

  @override
  String get wearPerKm => 'Vehicle wear';

  @override
  String get wearHint =>
      'Tyres, maintenance and depreciation per km, without fuel: from the ACI tables of the model or your own estimate';

  @override
  String get extraData => 'Extra data';

  @override
  String get extraIntro =>
      'Data read by the tracker from another board of the vehicle, shown as they arrive.';

  @override
  String get extraEmpty => 'No extra data received';

  @override
  String get extraLatest => 'Latest values';

  @override
  String extraReadings(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n readings',
      one: '1 reading',
    );
    return '$_temp0';
  }

  @override
  String extraFields(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n fields',
      one: '1 field',
    );
    return '$_temp0';
  }

  @override
  String get autoUpdate => 'Automatic updates';

  @override
  String get autoUpdateNever =>
      'This firmware doesn\'t check for updates: customized firmwares have them off (AUTO_UPDATE 0)';

  @override
  String autoUpdateChecked(String time) {
    return 'The tracker checks every day and installs the official versions (about 1.3 MB of SIM each) · last check $time';
  }

  @override
  String get firmwareAutomatic => 'automatic';

  @override
  String get kindFirmware => 'New firmware';

  @override
  String firmwareNewTitle(String version) {
    return 'New firmware $version';
  }

  @override
  String firmwareNewAutomatic(String device) {
    return '$device will install it by itself within a day';
  }

  @override
  String firmwareNewManual(String device) {
    return 'Install it on $device from the page of the device';
  }

  @override
  String appUpdateAvailable(String version) {
    return 'Version $version of the app is available';
  }

  @override
  String get download => 'Download';

  @override
  String get searchAci => 'Search the ACI cost per km';

  @override
  String costPerKm(String cost) {
    return 'Estimated cost: $cost/km';
  }

  @override
  String get costPerKmUnset =>
      'Enter consumption and price or the wear to compute the costs';

  @override
  String get costsSaved => 'Costs saved';

  @override
  String valueRange(String min, String max) {
    return 'Value between $min and $max';
  }

  @override
  String costFuel(String cost) {
    return 'fuel $cost';
  }

  @override
  String costWear(String cost) {
    return 'wear $cost';
  }

  @override
  String get kpiCost => 'Estimated cost';

  @override
  String get kpiFuel => 'Fuel';

  @override
  String get backups => 'Database backups';

  @override
  String backupLast(String time, String size) {
    return 'Last: $time · $size';
  }

  @override
  String backupFiles(int n, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n copies',
      one: '1 copy',
    );
    return '$_temp0, $size in total';
  }

  @override
  String backupOffsite(String time) {
    return 'Copy off the server: $time';
  }

  @override
  String get backupNoOffsite => 'No copy off the server';

  @override
  String get backupStale => 'No successful backup in the last 26 hours';

  @override
  String backupVerifyOk(String time) {
    return 'Restore test passed: $time';
  }

  @override
  String backupVerifyFailed(String time) {
    return 'Restore test FAILED: $time';
  }

  @override
  String get backupVerifyOld => 'No restore test in the last 9 days';

  @override
  String get backupNoVerify => 'No restore test yet';

  @override
  String get navDashboards => 'Dashboards';

  @override
  String get errTooManyDashboards =>
      'You already have the maximum number of dashboards (20)';

  @override
  String get dashboardNew => 'New dashboard';

  @override
  String get dashboardName => 'Dashboard name';

  @override
  String get dashboardEmpty =>
      'No dashboards yet. Create an empty one or start from a template: every widget can be changed.';

  @override
  String get dashboardNoWidgets => 'Empty dashboard: add a widget with Edit.';

  @override
  String get templateBlank => 'Blank';

  @override
  String get templateOverview => 'Vehicles overview';

  @override
  String get templateDiagnostics => 'Tracker diagnostics';

  @override
  String get dashboardEdit => 'Edit';

  @override
  String get dashboardRename => 'Rename';

  @override
  String get dashboardDelete => 'Delete dashboard';

  @override
  String dashboardDeleteBody(String name) {
    return 'Delete the dashboard «$name»? The data of the vehicles stay.';
  }

  @override
  String get dashboardSaved => 'Dashboard saved';

  @override
  String get dashboardDiscard => 'Leave without saving the changes?';

  @override
  String get discard => 'Discard';

  @override
  String get dashboardPeriod => 'Period';

  @override
  String get widgetAdd => 'Add widget';

  @override
  String get widgetEdit => 'Edit widget';

  @override
  String get widgetDuplicate => 'Duplicate';

  @override
  String get widgetRemove => 'Remove';

  @override
  String get widgetMetric => 'Value';

  @override
  String get widgetExtraKey => 'Extra data field';

  @override
  String get widgetExtraKeyHint => 'The name as shown in Extra data, e.g. rpm';

  @override
  String get widgetView => 'View';

  @override
  String get widgetDevices => 'Vehicles';

  @override
  String get widgetAllDevices => 'All my active vehicles';

  @override
  String get widgetAllDevicesSub =>
      'Also the ones added later, not the archived ones';

  @override
  String get widgetDevicesNeeded => 'Choose at least one vehicle';

  @override
  String get widgetKeyNeeded => 'Enter the name of the field';

  @override
  String get widgetPeriod => 'Period';

  @override
  String get widgetPeriodDashboard => 'Same as the dashboard';

  @override
  String get widgetAgg => 'Value';

  @override
  String get widgetBucket => 'Grouping';

  @override
  String get widgetTitle => 'Title (optional)';

  @override
  String get widgetWidth => 'Width';

  @override
  String get widgetHeight => 'Height';

  @override
  String get widgetPreview => 'Preview';

  @override
  String widgetUnavailable(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vehicles no longer available',
      one: '1 vehicle no longer available',
    );
    return '$_temp0';
  }

  @override
  String get widgetNoDevices => 'No vehicle available for this value';

  @override
  String get widgetPeriodTooLong => 'Period too long for this value';

  @override
  String widgetVehicles(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n vehicles',
      one: '1 vehicle',
    );
    return '$_temp0';
  }

  @override
  String get widgetNoDeadlines => 'No deadlines';

  @override
  String widgetSize(int w, int h) {
    return '$w × $h';
  }

  @override
  String get groupTrips => 'Trips';

  @override
  String get groupCosts => 'Costs';

  @override
  String get groupTracker => 'Tracker data';

  @override
  String get groupState => 'Current state';

  @override
  String get mDistance => 'Distance driven';

  @override
  String get mBusinessKm => 'Business km';

  @override
  String get mPersonalKm => 'Personal km';

  @override
  String get mDriving => 'Driving time';

  @override
  String get mTrips => 'Number of trips';

  @override
  String get mMaxSpeed => 'Top speed';

  @override
  String get mAlarms => 'Alarms';

  @override
  String get mTraffic => 'Data on the SIM';

  @override
  String get mRestVoltage => 'Battery at rest';

  @override
  String get mCost => 'Estimated cost';

  @override
  String get mFuelCost => 'Fuel cost';

  @override
  String get mWearCost => 'Wear';

  @override
  String get mFuel => 'Fuel litres';

  @override
  String get mRefuelCost => 'Spent on refuels';

  @override
  String get mRefuelLitres => 'Litres refuelled';

  @override
  String get mRefuelPrice => 'Price paid per litre';

  @override
  String get mRealConsumption => 'Real consumption';

  @override
  String get mSpeed => 'Moving speed';

  @override
  String get mAltitude => 'Altitude';

  @override
  String get mSignal => 'LTE signal';

  @override
  String get mSatellites => 'Satellites';

  @override
  String get mVoltage => 'Voltage';

  @override
  String get mTemperature => 'Temperature';

  @override
  String get mPressure => 'Pressure';

  @override
  String get mExtra => 'Extra data';

  @override
  String get mOdometer => 'Odometer';

  @override
  String get mDeadlines => 'Deadlines';

  @override
  String get mStatus => 'Position and state';

  @override
  String get viewNumber => 'Number';

  @override
  String get viewLine => 'Line over time';

  @override
  String get viewBars => 'Bars over time';

  @override
  String get viewVehicles => 'Bars per vehicle';

  @override
  String get viewTable => 'Table per vehicle';

  @override
  String get viewList => 'List';

  @override
  String get viewMap => 'Map';

  @override
  String get aggAvg => 'Average';

  @override
  String get aggMin => 'Minimum';

  @override
  String get aggMax => 'Maximum';

  @override
  String get aggLast => 'Latest value';

  @override
  String get groupAuto => 'Automatic';

  @override
  String get groupHour => 'Hours';

  @override
  String get groupDay => 'Days';

  @override
  String get groupWeek => 'Weeks';

  @override
  String get groupMonth => 'Months';

  @override
  String get periodToday => 'Today';

  @override
  String get period12m => 'Last 12 months';

  @override
  String get periodYtd => 'Year to date';

  @override
  String get dashboardSetCurrent => 'Set as current';

  @override
  String get dashboardUnsetCurrent => 'No longer current';

  @override
  String get dashboardCurrent => 'Current dashboard';

  @override
  String dashboardCurrentSet(String name) {
    return '«$name» is the current dashboard: you see it in the analysis of every vehicle';
  }

  @override
  String get dashboardCurrentUnset =>
      'The analysis of the vehicles is the standard one again';

  @override
  String get analysisStandard => 'Standard analysis';

  @override
  String get analysisOpenDashboard => 'Open in the dashboards';

  @override
  String get analysisNoWidgets =>
      'No widget of the current dashboard applies to this vehicle';

  @override
  String get dashboardShare => 'Share with a friend';

  @override
  String get dashboardShareHint =>
      'Your friend gets only the widgets: not your vehicles or their data. They will use them with their own vehicles.';

  @override
  String get dashboardShareNoFriends =>
      'You have no friends yet: add them from Account › Friends';

  @override
  String dashboardShared(String name) {
    return 'Dashboard sent to $name';
  }

  @override
  String dashboardReceived(String name, String dashboard) {
    return '$name shared the dashboard «$dashboard» with you';
  }

  @override
  String dashboardReceivedWidgets(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n widgets',
      one: '1 widget',
    );
    return '$_temp0 · choose your vehicles';
  }

  @override
  String get dashboardUse => 'Use';

  @override
  String get dashboardDecline => 'Decline';

  @override
  String get dashboardUseHint =>
      'Which of your vehicles should the widgets show? The ones that don\'t apply to a vehicle (e.g. tracker data on a car without a tracker) use the other ones chosen.';

  @override
  String get dashboardUseNoVehicles => 'Choose at least one vehicle';

  @override
  String dashboardAdded(String name) {
    return 'Dashboard «$name» added';
  }

  @override
  String get errTooManyDashboardShares =>
      'Your friend already has too many dashboards waiting: try again later';

  @override
  String get platformLog => 'Platform log';

  @override
  String get platformLogSub =>
      'Errors, warnings, slow requests and queries, to improve the platform';

  @override
  String get logErrors => 'Errors';

  @override
  String get logWarnings => 'Warnings';

  @override
  String get logSlowRequests => 'Slow requests';

  @override
  String get logSlowQueries => 'Slow queries';

  @override
  String get logEmpty => 'Nothing to report in the period';

  @override
  String logTimes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n times',
      one: 'one time',
    );
    return '$_temp0';
  }

  @override
  String logLast(String ago) {
    return 'last $ago';
  }

  @override
  String logDurations(String avg, String max) {
    return 'avg $avg · max $max';
  }

  @override
  String logCalls(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n runs',
      one: '1 run',
    );
    return '$_temp0';
  }

  @override
  String logFirst(String time) {
    return 'First time: $time';
  }

  @override
  String logRequestsHint(int ms, int n) {
    return 'Requests over $ms ms, by route. Kept $n days.';
  }

  @override
  String logQueriesHint(int ms, int n) {
    return 'Queries with a mean duration over $ms ms (or a maximum ten times as much), collected every hour. Kept $n days.';
  }

  @override
  String logErrorsHint(int n) {
    return 'Errors and warnings of the backend, equal ones grouped. Kept $n days.';
  }

  @override
  String get logQueriesOff =>
      'Slow queries aren\'t collected: the database must load pg_stat_statements (see the server documentation).';

  @override
  String get logCopied => 'Details copied';
}
