import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'phone_tracker.dart';
import 'phone_uploader.dart';

// Android foreground service of the phone sharing (flutter_foreground_task): it runs in
// its own isolate, so it keeps sending when the app is closed from the recent apps, and
// starts again after a reboot or an update of the app (with the position allowed "all
// the time"). Excluded from the coverage: it needs a real phone.

const _configKey = 'phone.config';
const _labelsKey = 'phone.labels';
const _serviceId = 4100;

/// Fixes of the fused provider: one every 15 s or every 20 m
Stream<Fix> _positions() => Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 15),
      ),
    )
        // Location turned off or permission revoked: the stream resumes with the next fix
        .handleError((Object _) {})
        .map((p) => (
              time: p.timestamp,
              lat: p.latitude,
              lon: p.longitude,
              accuracy: p.accuracy,
              // m/s, negative when unknown
              speed: p.speed >= 0 ? p.speed * 3.6 : null,
              altitude: p.altitude == 0 ? null : p.altitude,
            ));

@pragma('vm:entry-point')
void phoneTaskStart() {
  FlutterForegroundTask.setTaskHandler(_PhoneTaskHandler());
}

class _PhoneTaskHandler extends TaskHandler {
  PhoneUploader? _uploader;
  Map<String, String> _labels = {};
  DateTime? _shownPause;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final stored = await FlutterForegroundTask.getData<String>(key: _configKey);
    final config = stored == null ? null : PhoneConfig.fromJson(jsonDecode(stored));
    if (config == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    final labels = await FlutterForegroundTask.getData<String>(key: _labelsKey);
    if (labels != null) _labels = Map<String, String>.from(jsonDecode(labels) as Map);
    final battery = Battery();
    _uploader = PhoneUploader(config, _positions(), battery: () async {
      try {
        return await battery.batteryLevel;
      } on Exception {
        return null;
      }
    }, onStatus: (status) {
      FlutterForegroundTask.sendDataToMain(status.toJson());
      if (status.pausedUntil != _shownPause) _showPause(status.pausedUntil);
      if (status.gone) {
        FlutterForegroundTask.removeData(key: _configKey);
        FlutterForegroundTask.stopService();
      }
    })
      ..start();
  }

  /// Text and button of the notification: "Pause 1 hour" or "Resume"
  void _showPause(DateTime? until) {
    _shownPause = until;
    final time = until == null ? '' : '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
    FlutterForegroundTask.updateService(
      notificationText: until == null ? _labels['text'] : _labels['paused']?.replaceAll('{time}', time),
      notificationButtons: [
        until == null
            ? NotificationButton(id: 'pause', text: _labels['pause'] ?? 'Pause')
            : NotificationButton(id: 'resume', text: _labels['resume'] ?? 'Resume'),
      ],
    );
  }

  @override
  void onNotificationButtonPressed(String id) => _uploader?.pause(id == 'pause' ? phonePause : null);

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    final uploader = _uploader;
    if (uploader == null) return;
    if (data == 'status') FlutterForegroundTask.sendDataToMain(uploader.status.toJson());
    // From the app: {'pause': seconds or null}
    if (data is Map && data.containsKey('pause')) {
      final seconds = data['pause'];
      uploader.pause(seconds is int ? Duration(seconds: seconds) : null);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _uploader?.stop();
    await _uploader?.flush();
  }
}

class ForegroundPhoneService implements PhoneService {
  ForegroundPhoneService({required String channelName}) {
    if (!supported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is Map) _status.add(PhoneStatus.fromJson(data));
    });
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(channelId: 'phone_position', channelName: channelName, onlyAlertOnce: true),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  final _status = StreamController<PhoneStatus>.broadcast();

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String?> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'disabled';
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return 'denied';
    if (permission == LocationPermission.deniedForever) return 'deniedForever';
    // Optional: without them the notification is hidden (Android 13+) and the system may
    // stop the service sooner
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    return null;
  }

  @override
  Future<bool> backgroundAllowed() async => await Geolocator.checkPermission() == LocationPermission.always;

  @override
  Future<bool> requestBackground() async {
    // Android 11+: "all the time" is chosen in the settings of the app
    if (await Geolocator.requestPermission() != LocationPermission.always) await Geolocator.openAppSettings();
    return backgroundAllowed();
  }

  @override
  Future<bool> start(PhoneConfig config, {required Map<String, String> labels}) async {
    await FlutterForegroundTask.saveData(key: _configKey, value: jsonEncode(config.toJson()));
    await FlutterForegroundTask.saveData(key: _labelsKey, value: jsonEncode(labels));
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: labels['title'] ?? '',
      notificationText: labels['text'] ?? '',
      notificationButtons: [NotificationButton(id: 'pause', text: labels['pause'] ?? 'Pause')],
      callback: phoneTaskStart,
    );
    return result is ServiceRequestSuccess;
  }

  /// Stopped by the user or at the logout: the upload token is forgotten as well
  @override
  Future<void> stop() async {
    await FlutterForegroundTask.removeData(key: _configKey);
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> running() async => supported && await FlutterForegroundTask.isRunningService;

  @override
  Future<PhoneConfig?> config() async {
    if (!supported) return null;
    final stored = await FlutterForegroundTask.getData<String>(key: _configKey);
    return stored == null ? null : PhoneConfig.fromJson(jsonDecode(stored));
  }

  @override
  Stream<PhoneStatus> get status => _status.stream;

  @override
  void refresh() => FlutterForegroundTask.sendDataToTask('status');

  @override
  void pause(Duration? duration) => FlutterForegroundTask.sendDataToTask({'pause': duration?.inSeconds});
}
