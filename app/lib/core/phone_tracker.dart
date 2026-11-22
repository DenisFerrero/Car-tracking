import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'api.dart';
import 'phone_uploader.dart';
import 'session.dart';

export 'phone_uploader.dart' show Fix, PhoneConfig, PhoneStatus;

/// Background service that reads the position and sends it (Android: a foreground
/// service with its notification, also with the app closed and after a reboot; a fake
/// in the tests)
abstract class PhoneService {
  /// Only the Android app: a browser can't share the position in the background
  bool get supported;

  /// null when the position can be read, otherwise 'disabled', 'denied' or 'deniedForever'.
  /// Also asks for the notifications and to ignore the battery optimizations.
  Future<String?> requestPermissions();

  /// Position allowed "all the time": the sharing restarts by itself after a reboot
  Future<bool> backgroundAllowed();
  Future<bool> requestBackground();

  /// [labels]: texts of the notification (title, text, pause, resume, paused with {time})
  Future<bool> start(PhoneConfig config, {required Map<String, String> labels});
  Future<void> stop();
  Future<bool> running();

  /// Configuration of the running (or last) service
  Future<PhoneConfig?> config();

  /// State sent by the service; [refresh] asks for the current one
  Stream<PhoneStatus> get status;
  void refresh();

  /// No positions for [duration], null: sharing again
  void pause(Duration? duration);
}

/// Pause chosen from the notification or from the app
const phonePause = Duration(hours: 1);

/// Shares the position of this phone, without a tracker. The phone is a device of the
/// user (POST /api/phones) with its own upload token: the background service sends the
/// positions with it, without the app (PhoneUploader).
///
/// The choice is kept per user on the phone: the logout stops the service, the login
/// starts it again.
class PhoneTracker extends ChangeNotifier {
  PhoneTracker(this._api, this._session, this._service) {
    _session.addListener(_onSession);
    _statusSubscription = _service.status.listen(_onStatus);
  }

  final ApiClient _api;
  final Session _session;
  final PhoneService _service;

  int? _userId;
  int? deviceId;
  bool sharing = false;
  PhoneStatus status = const PhoneStatus();
  bool background = false;

  /// The phone was deleted (or shared from another phone): sharing stopped
  bool gone = false;

  late final StreamSubscription<PhoneStatus> _statusSubscription;

  bool get supported => _service.supported;

  String get _deviceKey => 'phone.$_userId.device';
  String get _sharingKey => 'phone.$_userId.sharing';

  Future<void> _onSession() async {
    final user = _session.loggedIn ? _session.user?.id : null;
    if (user == _userId || !supported) return;
    _userId = user;
    deviceId = null;
    sharing = false;
    status = const PhoneStatus();
    final config = await _service.config();
    if (user == null) {
      // Logout: the service stops, the choice stays for the next login
      if (await _service.running()) await _service.stop();
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getInt(_deviceKey);
    if (await _service.running()) {
      if (config?.userId == user && config?.deviceId == deviceId) {
        sharing = true;
        _service.refresh();
      } else {
        // Started by another user of this phone
        await _service.stop();
      }
    }
    if (!sharing && deviceId != null && prefs.getBool(_sharingKey) == true && await _service.requestPermissions() == null) {
      try {
        await _start(config?.userId == user && config?.deviceId == deviceId ? config!.token : null);
      } on ApiException catch (error) {
        if (error.status == 404) await _gone();
      }
    }
    background = await _service.backgroundAllowed();
    notifyListeners();
  }

  void _onStatus(PhoneStatus next) {
    status = next;
    if (next.gone && deviceId != null) {
      _gone();
    } else {
      notifyListeners();
    }
  }

  Future<void> _gone() async {
    gone = true;
    await forget();
  }

  /// Starts the service, with a new upload token when [token] is null
  Future<void> _start(String? token) async {
    final id = deviceId!;
    token ??= (await _api.post('/api/phones/$id/token', {}) as Map<String, dynamic>)['uploadToken'] as String;
    final l = lookupAppLocalizations(Locale(_session.language));
    final config = PhoneConfig(server: _api.baseUrl, userId: _userId!, deviceId: id, token: token);
    sharing = await _service.start(config, labels: {
      'title': l.phoneNotificationTitle,
      'text': l.phoneNotificationText,
      'pause': l.phonePauseHour,
      'resume': l.phoneResume,
      'paused': l.phonePausedUntil('{time}'),
    });
  }

  bool get paused => status.pausedUntil?.isAfter(DateTime.now()) ?? false;

  /// One hour without positions (null: sharing again now)
  void pause(Duration? duration) => _service.pause(duration);

  /// Creates the phone at the first use, then starts the service. Returns the reason of
  /// a refused permission.
  Future<String?> enable({required String name, required String color}) async {
    final refused = await _service.requestPermissions();
    if (refused != null) return refused;
    final prefs = await SharedPreferences.getInstance();
    String? token;
    if (deviceId == null) {
      final created = await _api.post('/api/phones', {'name': name, 'color': color}) as Map<String, dynamic>;
      deviceId = created['id'] as int;
      token = created['uploadToken'] as String;
      await prefs.setInt(_deviceKey, deviceId!);
    }
    gone = false;
    try {
      await _start(token);
    } on ApiException catch (error) {
      // Deleted meanwhile from another device: a new phone at the next start
      if (error.status == 404) {
        await _gone();
        return null;
      }
      rethrow;
    }
    await prefs.setBool(_sharingKey, true);
    background = await _service.backgroundAllowed();
    notifyListeners();
    return null;
  }

  /// "Allow all the time": the sharing restarts after a reboot
  Future<void> allowBackground() async {
    background = await _service.requestBackground();
    notifyListeners();
  }

  /// Back from the settings of the system
  Future<void> checkBackground() async {
    if (!supported) return;
    background = await _service.backgroundAllowed();
    notifyListeners();
  }

  Future<void> disable() async {
    await _service.stop();
    sharing = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sharingKey, false);
    notifyListeners();
  }

  /// The phone was deleted: the next start creates a new one
  Future<void> forget() async {
    if (sharing || await _service.running()) await _service.stop();
    sharing = false;
    deviceId = null;
    status = const PhoneStatus();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceKey);
    await prefs.setBool(_sharingKey, false);
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSubscription.cancel();
    _session.removeListener(_onSession);
    super.dispose();
  }
}
