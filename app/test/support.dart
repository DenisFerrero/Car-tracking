import 'dart:async';
import 'dart:convert';

import 'package:car_tracking/app.dart';
import 'package:car_tracking/core/api.dart';
import 'package:car_tracking/core/live.dart';
import 'package:car_tracking/core/phone_tracker.dart';
import 'package:car_tracking/core/phone_uploader.dart';
import 'package:car_tracking/core/providers.dart';
import 'package:car_tracking/core/session.dart';
import 'package:car_tracking/l10n/app_localizations.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final it = lookupAppLocalizations(const Locale('it'));
final en = lookupAppLocalizations(const Locale('en'));

/// Response of the fake backend with a status different from 200
class Reply {
  Reply(this.status, [this.body]);

  /// Error in the format of the backend
  Reply.error(this.status, String code) : body = {'error': code, 'message': code};

  final int status;
  final Object? body;
}

typedef Handler = Object? Function(http.Request request);

/// File of the fake backend (exports): bytes and headers
class RawReply {
  RawReply(this.body, this.headers);

  final List<int> body;
  final Map<String, String> headers;
}

/// Backend in memory: handlers by "METHOD /path", every request recorded
class FakeBackend {
  final routes = <String, Handler>{};
  final requests = <http.Request>[];
  bool offline = false;

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final handler = routes['${request.method} ${request.url.path}'];
    final result = handler == null ? Reply.error(404, 'not_found') : handler(request);
    if (result is RawReply) return http.Response.bytes(result.body, 200, headers: result.headers);
    final reply = result is Reply ? result : Reply(200, result);
    return http.Response(reply.body == null ? '' : jsonEncode(reply.body), reply.status,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });

  void on(String method, String path, Handler handler) => routes['$method $path'] = handler;

  /// Requests to a path, optionally of one method
  List<http.Request> calls(String path, [String? method]) =>
      [for (final r in requests) if (r.url.path == path && (method == null || r.method == method)) r];

  /// JSON body of the last request to a path
  Map<String, dynamic> lastBody(String path, [String? method]) =>
      jsonDecode(calls(path, method).last.body) as Map<String, dynamic>;
}

String iso(DateTime value) => value.toUtc().toIso8601String();

DateTime ago(Duration duration) => DateTime.now().subtract(duration);

Map<String, dynamic> userJson({int id = 1, bool admin = true, String? locale = 'it'}) =>
    {'id': id, 'email': 'anna@example.com', 'name': 'Anna', 'isAdmin': admin, 'locale': locale};

Map<String, dynamic> positionJson({
  Duration age = const Duration(minutes: 2),
  double? lat = 45.07,
  double? lon = 7.68,
  int status = 0,
  bool stale = false,
  int events = 0,
  bool full = true,
}) =>
    {
      'time': iso(ago(age)),
      'lat': lat,
      'lon': lon,
      'speed': 48,
      'status': status,
      'stale': stale,
      'events': events,
      if (full) ...{
        'altitude': 240,
        'pressure': 990.5,
        'temperature': 21.5,
        'voltage': 11.5,
        'satellites': 9,
        'signal': -80,
      },
      if (lat == null) ...{'cell_lat': 45.08, 'cell_lon': 7.69, 'cell_accuracy': 900},
    };

Map<String, dynamic> ownerDevice({int? liveUntil, int? pausedUntil, bool registered = true, bool connected = true}) => {
      'id': 1,
      'imei': '863820040182648',
      'name': 'Panda',
      'color': '#E53935',
      'role': 'owner',
      'model': 'A7670E',
      'manufacturer': 'SIMCOM',
      'firmware': '1.2.0',
      'registeredAt': registered ? iso(ago(const Duration(days: 30))) : null,
      'lastSeenAt': iso(ago(const Duration(minutes: 1))),
      'connected': connected,
      'lastPosition': positionJson(events: 3),
      'liveUntil': liveUntil,
      'antitheftPausedUntil': pausedUntil,
    };

Map<String, dynamic> viewerDevice({DateTime? expires}) => {
      'id': 2,
      'name': 'Golf',
      'color': '#43A047',
      'role': 'viewer',
      'ownerName': 'Mario',
      'shareExpiresAt': expires == null ? null : iso(expires),
      'lastSeenAt': iso(ago(const Duration(hours: 3))),
      'connected': false,
      'lastPosition': positionJson(lat: null, lon: null, status: 2, stale: true, full: false),
    };

Map<String, dynamic> notificationJson(int id, String kind, {bool read = false, int deviceId = 1, String? area}) => {
      'id': id,
      'deviceId': deviceId,
      'kind': kind,
      'data': {'device': deviceId == 1 ? 'Panda' : 'Golf', 'area': area, 'time': iso(ago(const Duration(minutes: 5)))},
      'createdAt': iso(ago(const Duration(minutes: 5))),
      'readAt': read ? iso(ago(const Duration(minutes: 1))) : null,
    };

/// Backend of a logged user with an owned and a shared device
FakeBackend fullBackend({String stage = 'full', bool admin = true, String? locale = 'it'}) {
  final b = FakeBackend();
  b.on('GET', '/api/config', (_) => {'appName': 'Tracker', 'simBudgetMb': 200, 'pushEnabled': true});
  b.on('GET', '/api/auth/session', (_) => {'stage': stage, 'user': userJson(admin: admin, locale: locale)});
  b.on('PATCH', '/api/account', (_) => {'ok': true});
  b.on('POST', '/api/auth/logout', (_) => {'ok': true});
  b.on('GET', '/api/devices', (_) => [ownerDevice(), viewerDevice(expires: DateTime.now().add(const Duration(hours: 5)))]);
  b.on('GET', '/api/devices/1', (_) => ownerDevice());
  b.on('GET', '/api/devices/2', (_) => viewerDevice());
  b.on('GET', '/api/notifications', (_) => {
        'notifications': [
          notificationJson(1, 'tilt'),
          notificationJson(2, 'geofence_enter', deviceId: 2, area: 'Casa'),
          notificationJson(3, 'geofence_exit', deviceId: 2, area: 'Casa', read: true),
        ],
        'unread': 2,
      });
  b.on('POST', '/api/notifications/read', (_) => {'ok': true});
  b.on('GET', '/api/devices/1/positions', (_) => {
        'positions': [
          positionJson(age: const Duration(minutes: 30), lat: 45.06, events: 1),
          positionJson(age: const Duration(minutes: 20), lat: 45.065, status: 1),
          positionJson(age: const Duration(minutes: 10), lat: null, lon: null, stale: true),
          positionJson(age: const Duration(minutes: 5)),
        ],
        'truncated': true,
      });
  b.on('GET', '/api/devices/2/positions', (_) => {'positions': [], 'truncated': false});
  b.on('GET', '/api/devices/1/shares', (_) => [
        {'userId': 5, 'name': 'Luca', 'expiresAt': null},
        {'userId': 6, 'name': 'Sara', 'expiresAt': iso(DateTime.now().add(const Duration(days: 2)))},
      ]);
  b.on('GET', '/api/friends', (_) => {
        'code': 'ABCDE12345',
        'friends': [
          {'id': 5, 'name': 'Luca', 'since': iso(ago(const Duration(days: 40)))},
          {'id': 7, 'name': 'Mario', 'since': iso(ago(const Duration(days: 3)))},
        ],
      });
  for (final id in [1, 2]) {
    b.on('GET', '/api/devices/$id/geofences', (_) => [
          {'id': 10, 'deviceId': id, 'name': 'Casa', 'lat': 45.07, 'lon': 7.68, 'radius': 500, 'notifyEnter': true, 'notifyExit': true, 'inside': true},
          {'id': 11, 'deviceId': id, 'name': 'Lavoro', 'lat': 45.1, 'lon': 7.7, 'radius': 12000, 'notifyEnter': false, 'notifyExit': false, 'inside': false},
        ]);
  }
  b.on('GET', '/api/devices/1/notification-settings', (_) => {
        'kinds': ['tilt', 'power_lost'],
        'available': ['motion', 'tilt', 'power_lost', 'low_battery', 'offline', 'online'],
      });
  b.on('PUT', '/api/devices/1/notification-settings', (_) => {'ok': true});
  b.on('POST', '/api/devices/1/commands', (_) => {'id': 1});
  return b;
}

/// Device of the user that shares the position of a phone
Map<String, dynamic> phoneDevice({int id = 3, bool owner = true, bool connected = true}) => {
      'id': id,
      'kind': 'phone',
      'imei': '',
      'name': 'Pixel',
      'color': '#43A047',
      'role': owner ? 'owner' : 'viewer',
      if (!owner) 'ownerName': 'Mario',
      'model': 'phone',
      'registeredAt': iso(ago(const Duration(days: 1))),
      'lastSeenAt': iso(ago(const Duration(minutes: 1))),
      'connected': connected,
      'lastPosition': {...positionJson(status: 1, full: false), 'accuracy': 14, 'altitude': 230},
    };

/// Vehicle without a tracker, fed by the phone of the owner
Map<String, dynamic> vehicleDevice({int id = 4, bool connected = false}) => {
      'id': id,
      'kind': 'vehicle',
      'imei': '',
      'name': 'Punto',
      'color': '#FFB300',
      'role': 'owner',
      'model': 'vehicle',
      'registeredAt': iso(ago(const Duration(days: 1))),
      'lastSeenAt': iso(ago(const Duration(hours: 2))),
      'connected': connected,
      'lastPosition': {...positionJson(status: 1, full: false, age: const Duration(hours: 2)), 'accuracy': 9, 'altitude': 230},
    };

/// Background service of the phone in the test isolate: the real uploader on the fake
/// backend; the test grants or refuses the permissions and pushes the fixes
class FakePhoneService implements PhoneService {
  FakePhoneService(this._client, {this.supported = true});

  final http.Client _client;
  @override
  final bool supported;
  String? refuse;
  bool always = false;
  int? battery = 80;
  Duration uploadEvery = Duration.zero;
  Duration? keepAlive;
  final fixes = StreamController<Fix>.broadcast();
  final _status = StreamController<PhoneStatus>.broadcast();
  final titles = <String>[];
  PhoneConfig? stored;
  PhoneUploader? uploader;

  @override
  Future<String?> requestPermissions() async => refuse;

  @override
  Future<bool> backgroundAllowed() async => always;

  @override
  Future<bool> requestBackground() async => always = true;

  @override
  Future<bool> start(PhoneConfig config, {required Map<String, String> labels}) async {
    uploader?.stop();
    stored = config;
    titles.add(labels['title']!);
    uploader = PhoneUploader(config, fixes.stream, client: _client, uploadEvery: uploadEvery, keepAlive: keepAlive, battery: () async => battery, onStatus: (status) {
      // The service stops by itself, like on the phone
      if (status.gone) {
        stored = null;
        uploader = null;
      }
      _status.add(status);
    })
      ..start();
    return true;
  }

  @override
  Future<void> stop() async {
    uploader?.stop();
    uploader = null;
    stored = null;
  }

  @override
  Future<bool> running() async => uploader != null;

  @override
  Future<PhoneConfig?> config() async => stored;

  @override
  Stream<PhoneStatus> get status => _status.stream;

  @override
  void refresh() {
    if (uploader case final uploader?) _status.add(uploader.status);
  }

  @override
  void pause(Duration? duration) => uploader?.pause(duration);

  @override
  void drive(int? vehicleId) {
    uploader?.drive(vehicleId);
    if (stored case final config?) stored = config.withVehicle(vehicleId);
  }

  void emit({double lat = 45.07, double lon = 7.68, double accuracy = 8, double? speed = 30, DateTime? time}) =>
      fixes.add((time: time ?? DateTime.now(), lat: lat, lon: lon, accuracy: accuracy, speed: speed, altitude: 240));
}

/// Tiles without network
class TestTiles extends TileProvider {
  static final _png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

class MemoryTokenStore extends TokenStore {
  MemoryTokenStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? token) async => value = token;
}

/// Platform passkeys replaced by canned answers (or a failure: dialog closed)
class FakePasskeys extends Passkeys {
  bool fail = false;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    calls.add('register');
    if (fail) throw Exception('cancelled');
    return {'id': 'new', 'type': 'public-key'};
  }

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async {
    calls.add('authenticate');
    if (fail) throw Exception('cancelled');
    return {'id': 'cred', 'type': 'public-key'};
  }
}

class FakeSink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// WebSocket of the realtime channel: the test pushes the events of the server
class FakeSocket implements WebSocketChannel {
  FakeSocket(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
  final _incoming = StreamController<dynamic>();
  final _sink = FakeSink();

  List<Map<String, dynamic>> get sent => _sink.sent;
  bool get closed => _sink.closed;

  void emit(Map<String, dynamic> event) => _incoming.add(jsonEncode(event));
  void emitRaw(Object data) => _incoming.add(data);
  void fail() => _incoming.addError(Exception('broken'));
  Future<void> drop() => _incoming.close();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> initFormats() async {
  for (final language in supportedLanguages) {
    await initializeDateFormatting(language);
  }
  BaseMap.tileProvider = TestTiles.new;
}

/// The whole app on a fake backend
class TestApp {
  TestApp(this.backend, {bool web = true, String server = 'https://tracking.test', Locale locale = const Locale('it'), String? token})
      : store = MemoryTokenStore(token) {
    api = ApiClient(web ? 'https://tracking.test' : server, token, client: backend.client, store: store, web: web);
    live = LiveChannel(api, connector: (uri, headers) {
      final socket = FakeSocket(uri, headers);
      sockets.add(socket);
      return socket;
    });
    session = Session(api, live, passkeys: passkeys, deviceLocale: locale);
    phoneService = FakePhoneService(backend.client, supported: !web);
    phone = PhoneTracker(api, session, phoneService);
  }

  final FakeBackend backend;
  final MemoryTokenStore store;
  final passkeys = FakePasskeys();
  final sockets = <FakeSocket>[];
  late final ApiClient api;
  late final LiveChannel live;
  late final Session session;
  late final FakePhoneService phoneService;
  late final PhoneTracker phone;

  /// Files saved by the app (exports)
  final saved = <({String name, String mimeType, Uint8List bytes})>[];

  /// Links opened in other apps; false: nothing can open them
  final opened = <Uri>[];
  bool canOpen = true;

  /// Version of the app and whether it's the Android app (updates from the releases)
  AppBuild appBuild = (version: '1.0.0', updatable: false);

  FakeSocket get socket => sockets.last;

  Future<void> start(WidgetTester tester, {Size size = const Size(420, 900), Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(live.stop);
    addTearDown(phone.dispose);
    // Clipboard of the platform
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    await session.load();
    await tester.pumpWidget(ProviderScope(
      retry: retryNetwork,
      overrides: [
        apiProvider.overrideWithValue(api),
        liveProvider.overrideWithValue(live),
        sessionProvider.overrideWithValue(session),
        phoneTrackerProvider.overrideWithValue(phone),
        fileSaverProvider.overrideWithValue((name, mimeType, bytes) async => saved.add((name: name, mimeType: mimeType, bytes: bytes))),
        appBuildProvider.overrideWithValue(appBuild),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return canOpen;
        }),
      ],
      child: CarTrackingApp(session: session),
    ));
    await settle(tester);
  }

  void go(WidgetTester tester, String location) => GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

/// Frames for the network answers and the animations (spinners never settle)
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the innermost vertical list until the widget is built and visible
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    try {
      await tester.scrollUntilVisible(finder, 250, scrollable: lists.last, maxScrolls: 60);
    } on StateError {
      await tester.scrollUntilVisible(finder, -250, scrollable: lists.last, maxScrolls: 120);
    }
  }
  // Scrolls only when needed (the explicit policy would also move the tab pages)
  final element = tester.element(finder.first);
  await Scrollable.ensureVisible(element, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
  await Scrollable.ensureVisible(element, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  await settle(tester, 3);
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder, [int frames = 12]) async {
  await reveal(tester, finder);
  await tester.tap(finder.first);
  await settle(tester, frames);
}

/// Snackbars expire: the next one can be found alone
Future<void> clearSnackbars(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
  await settle(tester, 4);
}
