import 'dart:convert';

import 'package:car_tracking/core/api.dart';
import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/core/live.dart';
import 'package:car_tracking/core/models.dart';
import 'package:car_tracking/core/providers.dart';
import 'package:car_tracking/core/session.dart';
import 'package:car_tracking/screens/add_device.dart';
import 'package:car_tracking/screens/device/device_screen.dart';
import 'package:car_tracking/widgets/track_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

Position _point(int minute, {double? lat, int speed = 50, bool stale = false, int? signal, int? satellites, int events = 0}) =>
    Position(
      time: DateTime(2026, 11, 20, 10, minute),
      lat: lat ?? 45.0 + minute * 0.001,
      lon: 9.0,
      speed: speed,
      status: TrackStatus.moving,
      stale: stale,
      signal: signal,
      satellites: satellites,
      events: events,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFormats);
  setUp(() => Intl.defaultLocale = 'it');

  group('format', () {
    final now = DateTime(2026, 11, 21, 12);

    test('relative times and durations', () {
      expect(formatAgo(it, null), it.never);
      expect(formatAgo(it, now.subtract(const Duration(seconds: 10)), now), it.now);
      expect(formatAgo(it, now.subtract(const Duration(minutes: 5)), now), it.minutesAgo(5));
      expect(formatAgo(en, now.subtract(const Duration(hours: 3)), now), en.hoursAgo(3));
      expect(formatAgo(it, now.subtract(const Duration(days: 2)), now), it.daysAgo(2));
      expect(formatAgo(it, DateTime(2026, 10, 1, 8), now), formatDayTime(DateTime(2026, 10, 1, 8)));
      expect(formatDuration(it, 45), '45 min');
      expect(formatDuration(it, 135), '2 h 15 min');
    });

    test('dates follow the language of the app', () {
      final date = DateTime(2026, 3, 2, 9, 5, 7);
      expect(formatTime(date), '09:05');
      expect(formatFull(date), '2 mar 2026 09:05:07');
      Intl.defaultLocale = 'en';
      expect(formatDay(date), 'Mon 2 Mar');
      expect(formatDate(date), '2 Mar 2026 09:05');
    });

    test('sizes and distances', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2,0 KB');
      expect(formatBytes(3 * 1024 * 1024), '3,0 MB');
      expect(formatMeters(250), '250 m');
      expect(formatMeters(1500), '1,5 km');
      expect(formatMeters(20000), '20 km');
    });

    test('signal and satellite quality', () {
      expect([for (final dbm in [null, -70, -85, -100, -110]) signalQuality(it, dbm).label],
          [it.notAvailable, it.qualityExcellent, it.qualityGood, it.qualityPoor, it.qualityBad]);
      expect([for (final n in [null, 10, 7, 4, 2]) satelliteQuality(en, n).label],
          [en.notAvailable, en.qualityExcellent, en.qualityGood, en.qualityWeak, en.qualityNone]);
      expect(scaleColor(0, 0, 10).toARGB32(), Colors.green.toARGB32());
      expect(scaleColor(10, 0, 10).toARGB32(), Colors.red.toARGB32());
      expect(scaleColor(2, 0, 10).toARGB32(), isNot(Colors.green.toARGB32()));
    });

    test('labels of states, events and kinds', () {
      expect([for (final s in TrackStatus.values) statusLabel(it, s)],
          [it.statusMoving, it.statusEngineOff, it.statusParked, it.statusAlarm]);
      expect(eventLabels(en, 15), [en.eventMotion, en.eventTilt, en.eventPowerLost, en.eventLowBattery]);
      expect(eventLabels(en, 0), isEmpty);
      for (final kind in ['motion', 'tilt', 'power_lost', 'low_battery', 'offline', 'online']) {
        expect(kindLabel(it, kind), isNot(kind));
      }
      expect(kindLabel(it, 'custom'), 'custom');
    });

    test('notification texts', () {
      final data = NotificationData(device: 'Panda', area: 'Casa', time: DateTime(2026, 1, 1, 8, 30));
      expect(notificationText(it, 'geofence_enter', data), (title: it.kindGeofenceEnter('Panda'), body: it.notificationBodyEnter('Casa', '08:30')));
      expect(notificationText(en, 'geofence_exit', data), (title: en.kindGeofenceExit('Panda'), body: en.notificationBodyExit('Casa', '08:30')));
      expect(notificationText(it, 'tilt', data), (title: it.kindTilt, body: it.notificationBodyAt('Panda', '08:30')));
      final noArea = NotificationData(device: 'Panda', time: DateTime(2026, 1, 1, 8, 30));
      expect(notificationText(it, 'geofence_enter', noArea).body, it.notificationBodyEnter('', '08:30'));
      expect(notificationText(it, 'geofence_exit', noArea).body, it.notificationBodyExit('', '08:30'));
    });

    test('error texts by code', () {
      const codes = [
        'network', 'invalid_credentials', 'locked', 'invalid_code', 'enroll_expired', 'step_up_required',
        'invalid_password', 'email_taken', 'self', 'invalid_pairing', 'already_claimed', 'owner_only', 'share_self',
        'too_many_shares', 'owner_cannot_leave', 'too_many_areas', 'live_too_long', 'period_too_long', 'rate_limited',
        'not_found', 'validation', 'bad_request', 'invalid_passkey', 'challenge_expired', 'unauthorized',
        'stage_enroll', 'stage_mfa_pending', 'forbidden', 'bad_origin', 'too_many_phones', 'not_a_tracker', 'friend_self',
        'too_many_friends',
      ];
      for (final code in codes) {
        expect(errorText(it, ApiException(400, code, code)), isNot(it.errGeneric(400)), reason: code);
      }
      expect(errorText(it, ApiException(500, 'boom', 'boom')), it.errGeneric(500));
      expect(errorText(it, StateError('x')), 'Bad state: x');
    });
  });

  group('models', () {
    test('reads the QR code of the label', () {
      expect(parseLabel('CT1:863820040182648:6MDFSV3C'), (imei: '863820040182648', code: '6MDFSV3C'));
      expect(parseLabel(' CT1:863820040182648:6mdf-sv3c '), (imei: '863820040182648', code: '6MDF-SV3C'));
      expect(parseLabel('CT1:12345:6MDFSV3C'), isNull);
    });

    test('colors', () {
      expect(colorToHex(parseColor('#ff5722')), '#FF5722');
      expect(parseColor('nope'), const Color(0xFF1E88E5));
      expect(parseColor(null), const Color(0xFF1E88E5));
    });

    test('positions fall back to the cell estimate', () {
      final p = Position.fromJson(positionJson(lat: null, lon: null, status: 9, stale: true));
      expect(p.fromCell, isTrue);
      expect(p.point!.latitude, 45.08);
      expect(p.status, TrackStatus.alarm);
      expect(Position(time: DateTime(2026)).point, isNull);
      final defaults = Position.fromJson({'time': '2026-01-01T00:00:00Z'});
      expect(defaults.status, TrackStatus.heartbeat);
      expect(defaults.events, 0);
    });

    test('devices of owner and viewer', () {
      final owner = Device.fromJson(ownerDevice(liveUntil: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600, registered: false));
      expect(owner.isOwner, isTrue);
      expect(owner.isLive, isTrue);
      expect(owner.waitingFirstContact, isTrue);
      final viewer = Device.fromJson({...viewerDevice(expires: DateTime(2027)), 'role': null, 'lastPosition': null});
      expect(viewer.isOwner, isFalse);
      expect(viewer.isLive, isFalse);
      expect(viewer.waitingFirstContact, isFalse);
      expect(viewer.imei, '');
      expect(viewer.shareExpiresAt, DateTime(2027));
    });

    test('notifications, shares, areas, users, config', () {
      final icons = {
        for (final kind in ['motion', 'tilt', 'power_lost', 'low_battery', 'offline', 'online', 'geofence_enter', 'geofence_exit'])
          AppNotification.fromJson(notificationJson(1, kind)).icon,
      };
      expect(icons.length, 8);
      final bare = AppNotification.fromJson({...notificationJson(1, 'tilt', read: true), 'data': null, 'lat': 45, 'lon': 7});
      expect(bare.data.device, '');
      expect(bare.data.time, bare.createdAt);
      expect(bare.readAt, isNotNull);
      expect(bare.lat, 45.0);

      final share = Share.fromJson({'userId': 3, 'name': 'Luca', 'email': 'l@x', 'expiresAt': null});
      expect(share.expiresAt, isNull);

      final area = Geofence.fromJson({'id': 1, 'deviceId': 2, 'name': 'Casa', 'lat': 45, 'lon': 7, 'radius': 300.4});
      expect((area.notifyEnter, area.notifyExit, area.inside, area.radius), (true, false, null, 300));
      expect(area.center.longitude, 7.0);

      expect(User.fromJson(userJson(locale: null)).locale, isNull);
      final config = ServerConfig.fromJson({});
      expect((config.appName, config.simBudgetMb, config.pushEnabled), ('Car Tracking', 200.0, false));
    });

    test('only network failures are retried', () {
      expect(retryNetwork(0, ApiException(0, 'network', '')), const Duration(seconds: 2));
      expect(retryNetwork(2, ApiException(0, 'network', '')), const Duration(seconds: 8));
      expect(retryNetwork(3, ApiException(0, 'network', '')), isNull);
      expect(retryNetwork(0, ApiException(403, 'forbidden', '')), isNull);
      expect(retryNetwork(0, StateError('x')), isNull);
    });

    test('periods', () {
      final now = DateTime(2026, 11, 21, 12);
      final period = PeriodChoice.last('24h', const Duration(hours: 24), now);
      expect(period.from, DateTime(2026, 11, 20, 12));
      expect(period.to, DateTime(2026, 11, 21, 12, 1));
      expect(PeriodChoice.last('x', const Duration(hours: 1)).to.isAfter(DateTime.now()), isTrue);
      expect(periodQuery((deviceId: 1, from: DateTime.utc(2026), to: DateTime.utc(2026, 2))),
          {'from': '2026-01-01T00:00:00.000Z', 'to': '2026-02-01T00:00:00.000Z'});
    });
  });

  group('track layers', () {
    final positions = [
      _point(0, speed: 20, signal: -70, satellites: 12),
      _point(1, speed: 20, signal: -70, satellites: 12, events: 2),
      _point(2, speed: 140, signal: -110, satellites: 3),
      _point(3, speed: 140),
      _point(30, speed: 140),
      _point(31, speed: 140, stale: true),
    ];

    test('splits the track by color and marks the gaps', () {
      final plain = trackPolylines(positions, TrackColoring.plain, Colors.blue);
      expect(plain.length, 2);
      expect(plain[1].color, Colors.grey);
      final speed = trackPolylines(positions, TrackColoring.speed, Colors.blue);
      expect(speed.length, 3);
      expect(speed[1].points.first, speed[0].points.last);
      expect(trackPolylines(positions, TrackColoring.signal, Colors.blue), isNotEmpty);
      expect(trackPolylines(positions, TrackColoring.satellites, Colors.blue), isNotEmpty);
      expect(trackPolylines(const [], TrackColoring.plain, Colors.blue), isEmpty);
    });

    test('labels and event markers', () {
      expect([for (final c in TrackColoring.values) c.label(it)], [it.coloringPlain, it.coloringSpeed, it.coloringSignal, it.coloringSatellites]);
      expect(eventMarkers(positions, (_) {}).length, 1);
    });
  });

  group('api client', () {
    test('sends JSON with the token and decodes the answers', () async {
      final backend = FakeBackend()
        ..on('GET', '/api/x', (r) => {'query': r.url.queryParameters, 'auth': r.headers['authorization']})
        ..on('POST', '/api/x', (r) => jsonDecode(r.body))
        ..on('PUT', '/api/x', (_) => Reply(204))
        ..on('PATCH', '/api/x', (_) => Reply(200, 'text'))
        ..on('DELETE', '/api/x', (r) => {'body': r.body});
      final store = MemoryTokenStore();
      final api = ApiClient('https://t', 'tok', client: backend.client, store: store, web: false);
      expect(api.clientType, 'app');
      expect(api.token, 'tok');
      expect(await api.get('/api/x', {'a': '1'}), {'query': {'a': '1'}, 'auth': 'Bearer tok'});
      expect(api.uri('/api/x', {}).hasQuery, isFalse);
      expect(await api.post('/api/x'), {});
      expect(await api.post('/api/x', {'b': 2}), {'b': 2});
      expect(await api.put('/api/x', {}), isNull);
      expect(await api.patch('/api/x', {}), 'text');
      expect(await api.delete('/api/x'), {'body': ''});
      await api.setToken('new');
      expect((api.token, store.value), ('new', 'new'));
      await api.setToken(null);
      expect(api.authHeaders, isEmpty);
    });

    test('errors of the backend and of the network', () async {
      final backend = FakeBackend()
        ..on('GET', '/api/coded', (_) => Reply.error(403, 'owner_only'))
        ..on('GET', '/api/plain', (_) => Reply(502));
      backend.routes['GET /api/html'] = (_) => Reply(500, null);
      final api = ApiClient('https://t', null, client: backend.client, store: MemoryTokenStore(), web: true);
      expect(api.clientType, 'web');
      await expectLater(api.get('/api/coded'),
          throwsA(isA<ApiException>().having((e) => (e.status, e.code, e.toString()), 'error', (403, 'owner_only', 'owner_only'))));
      await expectLater(api.get('/api/plain'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'http_502')));
      await expectLater(api.get('/api/html'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'HTTP 500')));
      backend.offline = true;
      await expectLater(api.get('/api/coded'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')));
      // The browser keeps the cookie: no token
      await api.setToken('x');
      expect(api.token, isNull);
    });

    test('non-JSON answers are null', () async {
      final backend = FakeBackend();
      final client = ApiClient('https://t', null, client: backend.client, store: MemoryTokenStore(), web: false);
      backend.routes['GET /api/bad'] = (_) => Reply(200, null);
      expect(await client.get('/api/bad'), isNull);
    });

    test('server address and token survive restarts', () async {
      SharedPreferences.setMockInitialValues({'server_url': 'https://saved'});
      FlutterSecureStorage.setMockInitialValues({'session_token': 'abc'});
      final api = await ApiClient.create();
      expect((api.baseUrl, api.token, api.hasServer), ('https://saved', 'abc', true));
      await api.setServer('https://other.example//');
      expect(api.baseUrl, 'https://other.example');
      expect((await SharedPreferences.getInstance()).getString('server_url'), 'https://other.example');
      await api.setToken('def');
      expect(await const TokenStore().read(), 'def');
      await api.setToken(null);
      expect(await const TokenStore().read(), isNull);
      SharedPreferences.setMockInitialValues({});
      expect((await ApiClient.create()).hasServer, isFalse);
    });
  });

  group('live channel', () {
    late FakeBackend backend;
    late ApiClient api;
    late List<FakeSocket> sockets;
    late LiveChannel live;

    setUp(() {
      backend = FakeBackend();
      api = ApiClient('https://t', 'tok', client: backend.client, store: MemoryTokenStore(), web: false);
      sockets = [];
      live = LiveChannel(api, connector: (uri, headers) {
        final socket = FakeSocket(uri, headers);
        sockets.add(socket);
        return socket;
      });
    });

    test('connects with the token and restores the watched devices', () async {
      live.watch(7);
      live.start();
      live.start();
      expect(sockets.length, 1);
      expect(sockets[0].uri.toString(), 'wss://t/api/live');
      expect(sockets[0].headers, {'authorization': 'Bearer tok'});
      // Watched before the connection: sent on the hello
      final events = <Map<String, dynamic>>[];
      final sub = live.device(7).listen(events.add);
      sockets[0].emit({'type': 'hello'});
      sockets[0].emitRaw('not json');
      sockets[0].emit({'type': 'position', 'deviceId': 7});
      sockets[0].emit({'type': 'position', 'deviceId': 8});
      await Future<void>.delayed(Duration.zero);
      expect(sockets[0].sent, [{'type': 'watch', 'deviceId': 7}]);
      expect(events.length, 1);
      expect(live.watched, [7]);

      live.watch(7);
      live.unwatch(7);
      expect(sockets[0].sent.length, 1);
      live.watch(9);
      expect(sockets[0].sent.last, {'type': 'watch', 'deviceId': 9});
      live.unwatch(9);
      live.unwatch(7);
      expect(sockets[0].sent.last, {'type': 'unwatch', 'deviceId': 7});
      expect(live.watched, isEmpty);
      live.unwatch(3);
      await sub.cancel();
      live.stop();
      expect(sockets[0].closed, isTrue);
      expect(live.active, isFalse);
    });

    testWidgets('reconnects with backoff', (tester) async {
      api.baseUrl = 'http://plain';
      live.start();
      expect(sockets.single.uri.scheme, 'ws');
      await sockets[0].drop();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(sockets.length, 2);
      sockets[1].fail();
      await tester.pump(const Duration(seconds: 2));
      expect(sockets.length, 3);
      live.stop();
      await tester.pump(const Duration(seconds: 30));
      expect(sockets.length, 3);
    });

    testWidgets('retries when the connection cannot start', (tester) async {
      var attempts = 0;
      final failing = LiveChannel(api, connector: (uri, headers) {
        attempts++;
        throw Exception('dns');
      });
      failing.start();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(attempts, 3);
      failing.stop();
      // Stopped channels and channels without server do not connect
      final idle = LiveChannel(ApiClient('', null, client: backend.client, store: MemoryTokenStore(), web: false),
          connector: (uri, headers) => throw StateError('no'));
      idle.start();
      idle.stop();
    });
  });

  group('session', () {
    Session build(FakeBackend backend, {String locale = 'it', bool web = false, String server = 'https://t'}) {
      final api = ApiClient(server, null, client: backend.client, store: MemoryTokenStore(), web: web);
      return Session(api, LiveChannel(api, connector: (uri, headers) => FakeSocket(uri, headers)),
          passkeys: FakePasskeys(), deviceLocale: Locale(locale));
    }

    test('detects the language of the device', () {
      expect(detectLanguage(const Locale('it', 'CH')), 'it');
      expect(detectLanguage(const Locale('de')), 'en');
    });

    test('first login saves the detected language', () async {
      final backend = fullBackend(locale: null);
      final session = build(backend, locale: 'en');
      expect(session.language, 'en');
      await session.load();
      expect(session.loggedIn, isTrue);
      expect(backend.lastBody('/api/account', 'PATCH'), {'locale': 'en'});
      expect(session.language, 'en');
      session.live.stop();
    });

    test('language saved with the account wins, errors keep it for the session', () async {
      final backend = fullBackend(locale: 'it');
      final session = build(backend, locale: 'en');
      await session.load();
      expect(session.language, 'it');
      expect(backend.calls('/api/account', 'PATCH'), isEmpty);
      backend.on('PATCH', '/api/account', (_) => Reply.error(500, 'boom'));
      await session.setLanguage('en');
      expect(session.language, 'en');
      await session.setLanguage('fr');
      expect(session.language, 'en');
      session.live.stop();
      await session.logout();
      await session.setLanguage('it');
      expect(session.user, isNull);
    });

    test('rename updates the user', () async {
      final backend = fullBackend();
      final session = build(backend);
      await session.load();
      await session.rename('Anna Maria');
      expect(session.user!.name, 'Anna Maria');
      expect(session.user!.locale, 'it');
      session.live.stop();
    });

    test('load without server or with errors', () async {
      final backend = fullBackend();
      final empty = build(backend, server: '');
      await empty.load();
      expect((empty.ready, empty.stage), (true, Stage.none));
      backend.on('GET', '/api/auth/session', (_) => Reply.error(500, 'x'));
      final broken = build(backend);
      await broken.load();
      expect((broken.ready, broken.stage), (true, Stage.none));
    });

    test('connects to a platform, restoring the previous one on failure', () async {
      SharedPreferences.setMockInitialValues({});
      final backend = fullBackend();
      final session = build(backend, server: '');
      await session.connect(' tracking.test ');
      expect(session.api.baseUrl, 'https://tracking.test');
      expect(session.config!.appName, 'Tracker');
      backend.offline = true;
      await expectLater(session.connect('http://other'), throwsA(isA<ApiException>()));
      expect(session.api.baseUrl, 'https://tracking.test');
      backend.offline = false;
      await session.changeServer();
      expect((session.api.hasServer, session.config), (false, null));
    });

    test('authentication flows', () async {
      final backend = fullBackend(stage: 'none');
      final session = build(backend);
      backend.on('POST', '/api/auth/login', (_) => {'token': 't1'});
      backend.on('POST', '/api/auth/totp', (_) => {'token': 't2'});
      backend.on('POST', '/api/auth/recovery', (_) => {'token': 't3', 'recoveryCodesLeft': 2});
      backend.on('POST', '/api/auth/passkey/options', (_) => {'challenge': 'c'});
      backend.on('POST', '/api/auth/passkey/verify', (_) => {'token': 't4'});
      backend.on('GET', '/api/auth/invites/abc', (_) => {'email': 'a@x', 'name': 'A'});
      backend.on('POST', '/api/auth/invites/abc', (_) => {'token': 't5'});
      backend.on('POST', '/api/auth/enroll/start', (_) => {'secret': 'S', 'uri': 'otpauth://x'});
      backend.on('POST', '/api/auth/enroll/confirm', (_) => {'token': 't6', 'recoveryCodes': ['a', 'b']});
      backend.on('POST', '/api/account/passkeys/options', (_) => {'challenge': 'c'});
      backend.on('POST', '/api/account/passkeys', (_) => {'ok': true});

      await session.login(' anna@example.com ', 'pw');
      expect(backend.lastBody('/api/auth/login'), {'email': 'anna@example.com', 'password': 'pw', 'client': 'app'});
      expect(session.api.token, 't1');
      await session.verifyTotp(' 123456 ');
      expect(backend.lastBody('/api/auth/totp'), {'code': '123456'});
      expect(await session.verifyRecoveryCode('AAAA'), 2);
      backend.on('POST', '/api/auth/recovery', (_) => {});
      expect(await session.verifyRecoveryCode('AAAA'), 0);
      await session.loginWithPasskey();
      expect(backend.lastBody('/api/auth/passkey/verify')['response'], {'id': 'cred', 'type': 'public-key'});
      expect(await session.invite('abc'), {'email': 'a@x', 'name': 'A'});
      await session.acceptInvite('abc', 'password');
      expect(await session.startEnrollment(), (secret: 'S', uri: 'otpauth://x'));
      await session.confirmEnrollment('111111');
      expect(session.pendingRecoveryCodes, ['a', 'b']);
      session.clearRecoveryCodes();
      expect(session.pendingRecoveryCodes, isNull);
      await session.addPasskey('Phone', code: '222222');
      expect(backend.lastBody('/api/account/passkeys/options'), {'code': '222222'});
      await session.addPasskey('Phone');
      expect(backend.lastBody('/api/account/passkeys/options'), isEmpty);
      expect(backend.lastBody('/api/account/passkeys'), {'name': 'Phone', 'response': {'id': 'new', 'type': 'public-key'}});

      backend.offline = true;
      await session.logout();
      expect((session.stage, session.user, session.api.token), (Stage.none, null, null));
    });

    test('stages of the backend', () async {
      for (final (value, stage) in [('mfa_pending', Stage.mfaPending), ('enroll', Stage.enroll), ('full', Stage.full), ('x', Stage.none)]) {
        final session = build(fullBackend(stage: value));
        await session.load();
        expect(session.stage, stage);
        session.live.stop();
      }
    });
  });
}
