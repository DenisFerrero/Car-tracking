import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A fix of the phone: speed in km/h, accuracy in meters
typedef Fix = ({DateTime time, double lat, double lon, double accuracy, double? speed, double? altitude});

/// Where the background service sends the positions: the server, the phone (a device of
/// [userId]) and its upload token (POST /api/phones, /api/phones/:id/token)
class PhoneConfig {
  const PhoneConfig({required this.server, required this.userId, required this.deviceId, required this.token});

  final String server;
  final int userId;
  final int deviceId;
  final String token;

  Map<String, Object> toJson() => {'server': server, 'userId': userId, 'deviceId': deviceId, 'token': token};

  static PhoneConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final server = json['server'], userId = json['userId'], deviceId = json['deviceId'], token = json['token'];
    if (server is! String || userId is! int || deviceId is! int || token is! String) return null;
    return PhoneConfig(server: server, userId: userId, deviceId: deviceId, token: token);
  }
}

/// State of the sharing, sent by the background service to the app
class PhoneStatus {
  const PhoneStatus({this.lastFix, this.queued = 0, this.gone = false, this.pausedUntil});

  final Fix? lastFix;
  final int queued;

  /// The token was refused (phone deleted or sharing started on another phone): stopped
  final bool gone;

  /// Paused from the notification or the app: no positions until then
  final DateTime? pausedUntil;

  Map<String, Object?> toJson() => {
        'queued': queued,
        'gone': gone,
        if (pausedUntil case final until?) 'pausedUntil': until.millisecondsSinceEpoch,
        if (lastFix case final fix?) 'fix': {'time': fix.time.millisecondsSinceEpoch, 'lat': fix.lat, 'lon': fix.lon, 'accuracy': fix.accuracy},
      };

  factory PhoneStatus.fromJson(Map<dynamic, dynamic> json) {
    final fix = json['fix'];
    final paused = json['pausedUntil'];
    return PhoneStatus(
      queued: json['queued'] as int? ?? 0,
      gone: json['gone'] == true,
      pausedUntil: paused is int ? DateTime.fromMillisecondsSinceEpoch(paused) : null,
      lastFix: fix is Map
          ? (
              time: DateTime.fromMillisecondsSinceEpoch(fix['time'] as int),
              lat: (fix['lat'] as num).toDouble(),
              lon: (fix['lon'] as num).toDouble(),
              accuracy: (fix['accuracy'] as num).toDouble(),
              speed: null,
              altitude: null,
            )
          : null,
    );
  }
}

/// Sends the fixes of the phone in batches (POST /api/phones/positions with the upload
/// token), at most every [uploadEvery]; while the network is missing they stay queued.
/// When the phone stands still the last fix is sent again every [keepAlive]: the
/// friends see that the position is current. The battery level of the phone goes with the
/// positions when it changes. During a [pause] the fixes are dropped and the friends see
/// the end of the pause. Runs in the background service, without the app.
class PhoneUploader {
  PhoneUploader(
    this.config,
    this._fixes, {
    http.Client? client,
    this.uploadEvery = const Duration(seconds: 15),
    this.keepAlive = const Duration(minutes: 5),
    this.onStatus,
    this.battery,
  }) : _http = client ?? http.Client();

  static const maxQueue = 2000;
  static const _batch = 100;

  final PhoneConfig config;
  final Stream<Fix> _fixes;
  final http.Client _http;
  final Duration uploadEvery;
  final Duration? keepAlive;
  final void Function(PhoneStatus status)? onStatus;

  /// Battery level of the phone (%), null when unknown
  final Future<int?> Function()? battery;

  Fix? lastFix;
  DateTime? lastSent;
  bool gone = false;
  DateTime? pausedUntil;
  final queue = <Fix>[];

  StreamSubscription<Fix>? _subscription;
  Timer? _upload;
  Timer? _alive;
  Timer? _resume;
  bool _sending = false;
  // Changes of the pause, and the last one the server knows
  int _pauseVersion = 0;
  int _pauseSent = 0;
  int? _batterySent;

  PhoneStatus get status => PhoneStatus(lastFix: lastFix, queued: queue.length, gone: gone, pausedUntil: pausedUntil);

  bool get paused => pausedUntil != null && pausedUntil!.isAfter(DateTime.now());

  void start() {
    _subscription = _fixes.listen(_onFix);
    if (keepAlive != null) _alive = Timer.periodic(keepAlive!, (_) => _repeatLast());
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _upload?.cancel();
    _alive?.cancel();
    _resume?.cancel();
  }

  /// Stops the positions for [duration] (null: sharing again now)
  void pause(Duration? duration) {
    _resume?.cancel();
    pausedUntil = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) _resume = Timer(duration, () => pause(null));
    _pauseVersion++;
    onStatus?.call(status);
    flush();
  }

  void _onFix(Fix fix) {
    if (paused) return;
    lastFix = fix;
    queue.add(fix);
    if (queue.length > maxQueue) queue.removeRange(0, queue.length - maxQueue);
    final since = lastSent == null ? null : DateTime.now().difference(lastSent!);
    if (since == null || since >= uploadEvery) {
      flush();
    } else if (_upload?.isActive != true) {
      _upload = Timer(uploadEvery - since, flush);
    }
    onStatus?.call(status);
  }

  /// Still here: the last fix with the current time
  void _repeatLast() {
    final fix = lastFix;
    if (fix == null || queue.isNotEmpty || paused) return;
    _onFix((time: DateTime.now(), lat: fix.lat, lon: fix.lon, accuracy: fix.accuracy, speed: 0, altitude: fix.altitude));
  }

  Future<void> flush() async {
    if (_sending || (queue.isEmpty && _pauseVersion == _pauseSent) || gone) return;
    _sending = true;
    final batch = queue.take(_batch).toList();
    final pauseVersion = _pauseVersion;
    var sent = false;
    try {
      final level = await battery?.call();
      final response = await _http.post(
        Uri.parse('${config.server}/api/phones/positions'),
        headers: {'content-type': 'application/json', 'authorization': 'Bearer ${config.token}'},
        body: jsonEncode({
          if (level != null && level != _batterySent) 'battery': level,
          if (pauseVersion != _pauseSent) 'pausedUntil': pausedUntil?.toUtc().toIso8601String(),
          'positions': [
            for (final fix in batch)
              {
                'time': fix.time.toUtc().toIso8601String(),
                'lat': fix.lat,
                'lon': fix.lon,
                'accuracy': fix.accuracy,
                'speed': fix.speed,
                'altitude': fix.altitude,
              },
          ],
        }),
      );
      if (response.statusCode == 401) {
        // Phone deleted or a new token elsewhere: nothing more to send
        gone = true;
        queue.clear();
        stop();
      } else if (response.statusCode < 300 || response.statusCode == 400) {
        // 400: invalid batch, never accepted: dropped instead of blocking the queue
        queue.removeRange(0, batch.length);
        lastSent = DateTime.now();
        sent = true;
        _batterySent = level ?? _batterySent;
        // Changed again while sending: the new state goes with the next request
        _pauseSent = pauseVersion;
      }
    } on Exception {
      // Offline: retried with the next fix
    }
    _sending = false;
    onStatus?.call(status);
    // A long offline queue goes in consecutive batches
    if (sent && batch.length == _batch && queue.isNotEmpty) await flush();
  }
}
