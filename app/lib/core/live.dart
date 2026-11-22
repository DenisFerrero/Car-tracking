import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'ws_connect.dart';

typedef WebSocketConnector = WebSocketChannel Function(Uri uri, Map<String, String> headers);

/// Realtime channel (/api/live): positions, device state, commands, notifications,
/// access granted or revoked. Reconnects with backoff and restores the watched devices:
/// an owner watching a device asks the tracker for live tracking while the map is open.
class LiveChannel {
  // ignore: prefer_initializing_formals
  LiveChannel(this._api, {WebSocketConnector connector = connectWebSocket}) : _connector = connector;

  final ApiClient _api;
  final WebSocketConnector _connector;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _watched = <int, int>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  bool _active = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get active => _active;
  Iterable<int> get watched => _watched.keys;

  /// Events of one device
  Stream<Map<String, dynamic>> device(int id) => events.where((event) => event['deviceId'] == id);

  void start() {
    if (_active) return;
    _active = true;
    _connect();
  }

  void stop() {
    _active = false;
    _retry?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _connect() {
    if (!_active || !_api.hasServer) return;
    final base = Uri.parse(_api.baseUrl);
    final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/api/live');
    try {
      final channel = _connector(uri, _api.authHeaders);
      _channel = channel;
      _subscription = channel.stream.listen(
        (data) {
          final Map<String, dynamic> message;
          try {
            message = jsonDecode(data as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          if (message['type'] == 'hello') {
            _attempt = 0;
            for (final id in _watched.keys) {
              _send({'type': 'watch', 'deviceId': id});
            }
          }
          _events.add(message);
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _channel = null;
    if (!_active) return;
    _retry?.cancel();
    final seconds = [1, 2, 5, 10, 30][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// Reference counted: several screens can watch the same device
  void watch(int deviceId) {
    _watched.update(deviceId, (count) => count + 1, ifAbsent: () => 1);
    if (_watched[deviceId] == 1) _send({'type': 'watch', 'deviceId': deviceId});
  }

  void unwatch(int deviceId) {
    final count = (_watched[deviceId] ?? 1) - 1;
    if (count <= 0) {
      _watched.remove(deviceId);
      _send({'type': 'unwatch', 'deviceId': deviceId});
    } else {
      _watched[deviceId] = count;
    }
  }
}
