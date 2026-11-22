import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'models.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

// Dates in the language of the app (Intl.defaultLocale, set by CarTrackingApp)
String formatTime(DateTime value) => DateFormat('HH:mm').format(value);
String formatDayTime(DateTime value) => DateFormat('d MMM HH:mm').format(value);
String formatDay(DateTime value) => DateFormat('EEE d MMM').format(value);
String formatFull(DateTime value) => DateFormat('d MMM yyyy HH:mm:ss').format(value);
String formatDate(DateTime value) => DateFormat('d MMM yyyy HH:mm').format(value);

/// "3 min ago", "2 h ago", or the date
String formatAgo(AppLocalizations l, DateTime? value, [DateTime? now]) {
  if (value == null) return l.never;
  final diff = (now ?? DateTime.now()).difference(value);
  if (diff.inSeconds < 60) return l.now;
  if (diff.inMinutes < 60) return l.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l.hoursAgo(diff.inHours);
  if (diff.inDays < 7) return l.daysAgo(diff.inDays);
  return formatDayTime(value);
}

String formatDuration(AppLocalizations l, int minutes) =>
    minutes < 60 ? l.durationMinutes(minutes) : l.durationHours(minutes ~/ 60, minutes % 60);

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${formatDecimal(bytes / 1024, 1)} KB';
  return '${formatDecimal(bytes / 1024 / 1024, 1)} MB';
}

String formatMeters(num meters) => meters < 1000 ? '${meters.round()} m' : '${formatDecimal(meters / 1000, meters < 10000 ? 1 : 0)} km';

/// Quality of the LTE signal (RSSI in dBm reported by the modem)
({String label, Color color}) signalQuality(AppLocalizations l, int? dbm) {
  if (dbm == null) return (label: l.notAvailable, color: Colors.grey);
  if (dbm >= -75) return (label: l.qualityExcellent, color: Colors.green);
  if (dbm >= -90) return (label: l.qualityGood, color: Colors.lightGreen);
  if (dbm >= -105) return (label: l.qualityPoor, color: Colors.orange);
  return (label: l.qualityBad, color: Colors.red);
}

/// Quality of the GNSS fix from the satellites in use
({String label, Color color}) satelliteQuality(AppLocalizations l, int? count) {
  if (count == null) return (label: l.notAvailable, color: Colors.grey);
  if (count >= 9) return (label: l.qualityExcellent, color: Colors.green);
  if (count >= 6) return (label: l.qualityGood, color: Colors.lightGreen);
  if (count >= 4) return (label: l.qualityWeak, color: Colors.orange);
  return (label: l.qualityNone, color: Colors.red);
}

/// Color scale green -> yellow -> red for a value in [good, bad]
Color scaleColor(double value, double good, double bad) {
  final t = ((value - good) / (bad - good)).clamp(0.0, 1.0);
  return t < 0.5
      ? Color.lerp(Colors.green, Colors.amber, t * 2)!
      : Color.lerp(Colors.amber, Colors.red, (t - 0.5) * 2)!;
}

String statusLabel(AppLocalizations l, TrackStatus status) => switch (status) {
      TrackStatus.moving => l.statusMoving,
      TrackStatus.engineOff => l.statusEngineOff,
      TrackStatus.heartbeat => l.statusParked,
      TrackStatus.alarm => l.statusAlarm,
    };

List<String> eventLabels(AppLocalizations l, int events) => [
      if (events & TrackEvents.motion != 0) l.eventMotion,
      if (events & TrackEvents.tilt != 0) l.eventTilt,
      if (events & TrackEvents.powerLost != 0) l.eventPowerLost,
      if (events & TrackEvents.lowBattery != 0) l.eventLowBattery,
    ];

String kindLabel(AppLocalizations l, String kind) => switch (kind) {
      'motion' => l.kindMotion,
      'tilt' => l.kindTilt,
      'power_lost' => l.kindPowerLost,
      'low_battery' => l.kindLowBattery,
      'offline' => l.kindOffline,
      'online' => l.kindOnline,
      'battery_health' => l.kindBatteryHealth,
      'maintenance' => l.kindMaintenance,
      'firmware' => l.kindFirmware,
      _ => kind,
    };

String maintenanceKindLabel(AppLocalizations l, String kind) => switch (kind) {
      'service' => l.mkService,
      'inspection' => l.mkInspection,
      'insurance' => l.mkInsurance,
      'tax' => l.mkTax,
      'tyres' => l.mkTyres,
      _ => l.mkOther,
    };

/// Days and km left of a deadline: "in 10 days or in 1,500 km"
String remainingText(AppLocalizations l, int? days, int? km) => [
      if (days != null) days > 0 ? l.inDays(days) : (days == 0 ? l.today : l.overdueDays(-days)),
      if (km != null) km > 0 ? l.inKm(formatInt(km)) : l.kmOver(formatInt(-km)),
    ].join(l.orJoin);

/// Integer with thousands separators of the language of the app
String formatInt(int value) => NumberFormat.decimalPattern(Intl.getCurrentLocale()).format(value);

/// Amount in euro in the language of the app: 2,34 € in Italian, €2.34 in English
String formatEuro(num value, {int digits = 2}) =>
    NumberFormat.currency(locale: Intl.getCurrentLocale(), name: 'EUR', symbol: '€', decimalDigits: digits).format(value);

/// Cost of a trip: total, fuel (or litres without the price) and wear
String costText(AppLocalizations l, Map<String, dynamic> cost) {
  final parts = [
    if (cost['fuelCost'] != null)
      l.costFuel(formatEuro(cost['fuelCost'] as num))
    else if (cost['fuelL'] != null)
      '${formatDecimal((cost['fuelL'] as num).toDouble(), 2)} l',
    if (cost['wearCost'] != null) l.costWear(formatEuro(cost['wearCost'] as num)),
  ];
  final total = cost['cost'] as num?;
  return total == null ? parts.join(' · ') : '≈ ${formatEuro(total)} (${parts.join(' · ')})';
}

/// Text of a notification: the backend sends kind and data, the app the words
({String title, String body}) notificationText(AppLocalizations l, String kind, NotificationData data) {
  final time = formatTime(data.time);
  return switch (kind) {
    'geofence_enter' => (title: l.kindGeofenceEnter(data.device), body: l.notificationBodyEnter(data.area ?? '', time)),
    'geofence_exit' => (title: l.kindGeofenceExit(data.device), body: l.notificationBodyExit(data.area ?? '', time)),
    'phone_battery' => (title: l.kindPhoneBattery(data.device, data.battery ?? 0), body: l.notificationBodyPhoneBattery(time)),
    'long_stop' => (title: l.kindLongStop(data.device, data.hours ?? 1), body: l.notificationBodyLongStop(time)),
    'firmware' => (
        title: l.firmwareNewTitle(data.version ?? ''),
        body: data.automatic == true ? l.firmwareNewAutomatic(data.device) : l.firmwareNewManual(data.device),
      ),
    'battery_health' => (
        title: l.kindBatteryHealth,
        body: l.notificationBodyBatteryHealth(data.device, formatDecimal(data.voltage ?? 0, 2)),
      ),
    'maintenance' => (
        title: (data.due == 'due' ? l.maintenanceDueTitle : l.maintenanceSoonTitle)(
            data.title?.isNotEmpty == true ? data.title! : maintenanceKindLabel(l, data.maintenance ?? 'other')),
        body: '${data.device}: ${remainingText(l, data.days, data.km)}',
      ),
    _ => (title: kindLabel(l, kind), body: l.notificationBodyAt(data.device, time)),
  };
}

/// Message of an error: API errors by code, in the language of the app
String errorText(AppLocalizations l, Object error) {
  if (error is! ApiException) return error.toString();
  return switch (error.code) {
    'network' => l.errNetwork,
    'invalid_credentials' => l.errInvalidCredentials,
    'locked' => l.errLocked,
    'invalid_code' => l.errInvalidCode,
    'enroll_expired' => l.errEnrollExpired,
    'step_up_required' => l.errStepUp,
    'invalid_password' => l.errInvalidPassword,
    'email_taken' => l.errEmailTaken,
    'self' => l.errSelf,
    'invalid_pairing' => l.errInvalidPairing,
    'already_claimed' => l.errAlreadyClaimed,
    'owner_only' => l.errOwnerOnly,
    'share_self' => l.errShareSelf,
    'too_many_shares' => l.errTooManyShares,
    'owner_cannot_leave' => l.errOwnerCannotLeave,
    'too_many_areas' => l.errTooManyAreas,
    'too_many_phones' => l.errTooManyPhones,
    'too_many_vehicles' => l.errTooManyVehicles,
    'vehicle_has_tracker' => l.errVehicleHasTracker,
    'not_a_tracker' => l.errNotATracker,
    'deadline_untitled' => l.deadlineNeedsTitle,
    'too_many_rates' => l.errTooManyRates,
    'friend_self' => l.errFriendSelf,
    'too_many_friends' => l.errTooManyFriends,
    'too_many_requests' => l.errTooManyRequests,
    'email_mismatch' => l.errEmailMismatch,
    'last_admin' => l.errLastAdmin,
    'wrong_variant' || 'not_newer' => l.errFirmware,
    'live_too_long' => l.errLiveTooLong,
    'period_too_long' => l.errPeriodTooLong,
    'rate_limited' => l.errRateLimited,
    'not_found' => l.errNotFound,
    'validation' || 'bad_request' => l.errValidation,
    'invalid_passkey' => l.errInvalidPasskey,
    'challenge_expired' => l.errChallengeExpired,
    'unauthorized' || 'stage_enroll' || 'stage_mfa_pending' => l.errUnauthorized,
    'forbidden' || 'bad_origin' => l.errForbidden,
    _ => l.errGeneric(error.status),
  };
}

void showError(BuildContext context, Object error) => showMessage(context, errorText(context.l10n, error));

/// The new message replaces the one on screen instead of waiting in the queue
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Decimal number in the language of the app: 12,40 in Italian
String formatDecimal(double value, int digits) =>
    NumberFormat.decimalPatternDigits(locale: Intl.getCurrentLocale(), decimalDigits: digits).format(value);

/// Lists on wide screens (browser on a desktop): side margins keep the rows readable
EdgeInsets readable(BuildContext context, [EdgeInsets base = EdgeInsets.zero]) {
  final width = MediaQuery.sizeOf(context).width;
  // From 840 px the navigation rail takes 80 px
  final side = ((width - (width >= 840 ? 80 : 0) - 880) / 2).clamp(0.0, double.infinity);
  return base + EdgeInsets.symmetric(horizontal: side);
}
