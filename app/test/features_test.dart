import 'dart:async';
import 'dart:convert';

import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/core/models.dart';
import 'package:car_tracking/core/phone_uploader.dart';
import 'package:car_tracking/core/providers.dart';
import 'package:car_tracking/screens/auth.dart';
import 'package:car_tracking/screens/device/alerts.dart';
import 'package:car_tracking/screens/device/areas_tab.dart';
import 'package:car_tracking/screens/device/firmware_section.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

// Friend requests, pause and battery of the phones, clusters on the map, export of the
// trips, export and deletion of the account, firmware updates

Map<String, dynamic> accountJson() =>
    {'user': userJson(), 'passkeys': [], 'sessions': [], 'recoveryCodesLeft': 10, 'pushEnabled': true};

Map<String, dynamic> tripJson(Duration ago_, int minutes) => {
      'start': iso(ago(ago_)),
      'end': iso(ago(ago_ - Duration(minutes: minutes))),
      'distanceKm': 4.2,
      'durationMin': minutes,
      'avgSpeed': 25,
      'maxSpeed': 48,
    };

Map<String, dynamic> withPosition(Map<String, dynamic> device, double lat, double lon) =>
    {...device, 'lastPosition': {...positionJson(), 'lat': lat, 'lon': lon}};

void main() {
  setUpAll(initFormats);

  group('friend requests', () {
    testWidgets('received and sent, request by code, realtime notices', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/account', (_) => accountJson())
        ..on('GET', '/api/friends', (_) => {
              'code': 'ABCDE12345',
              'friends': [],
              'incoming': [
                {'id': 8, 'name': 'Bea', 'since': iso(ago(const Duration(hours: 2)))},
              ],
              'outgoing': [
                {'id': 9, 'name': 'Carlo', 'since': iso(ago(const Duration(days: 1)))},
              ],
            })
        ..on('POST', '/api/friends/requests/8/accept', (_) => {'id': 8, 'name': 'Bea'})
        ..on('DELETE', '/api/friends/requests/8', (_) => {'ok': true})
        ..on('DELETE', '/api/friends/requests/9', (_) => {'ok': true})
        ..on('POST', '/api/friends', (_) => {'id': 10, 'name': 'Dario', 'status': 'requested'});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account/friends');
      await settle(tester);
      expect(find.text(it.requestsReceived), findsOneWidget);
      await reveal(tester, find.text('Carlo'));
      expect(find.text(it.requestWaiting), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip(it.accept));
      expect(backend.calls('/api/friends/requests/8/accept', 'POST').length, 1);
      expect(find.text(it.friendAdded('Bea')), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.decline));
      expect(backend.calls('/api/friends/requests/8', 'DELETE').length, 1);
      await tapAndSettle(tester, find.byTooltip(it.withdraw));
      expect(backend.calls('/api/friends/requests/9', 'DELETE').length, 1);

      backend
        ..on('DELETE', '/api/friends/requests/9', (_) => Reply.error(404, 'not_found'))
        ..on('POST', '/api/friends/requests/8/accept', (_) => Reply.error(400, 'too_many_friends'));
      await tapAndSettle(tester, find.byTooltip(it.withdraw));
      expect(find.text(it.errNotFound), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.accept));
      expect(find.text(it.errTooManyFriends), findsOneWidget);

      await reveal(tester, find.byKey(const Key('friendCode')));
      await tester.enterText(find.byKey(const Key('friendCode')), 'FGHJK-23456');
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.friendRequested('Dario')), findsOneWidget);
      backend.on('POST', '/api/friends', (_) => Reply.error(400, 'too_many_requests'));
      await tester.enterText(find.byKey(const Key('friendCode')), 'FGHJK-23456');
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.errTooManyRequests), findsOneWidget);

      // Elsewhere in the app: a request received (it opens the friends), a request accepted
      app.go(tester, '/devices');
      await settle(tester);
      app.socket.emit({'type': 'friends', 'userId': 11, 'name': 'Elena', 'request': true});
      await settle(tester);
      expect(find.text(it.friendRequestReceived('Elena')), findsOneWidget);
      await tester.tap(find.text(it.open));
      await settle(tester);
      expect(find.text(it.yourCode), findsOneWidget);
      // On the friends screen: no notice
      app.socket.emit({'type': 'friends', 'userId': 12, 'name': 'Fabio', 'request': true});
      await settle(tester);
      expect(find.text(it.friendRequestReceived('Fabio')), findsNothing);
      app.go(tester, '/devices');
      await settle(tester);
      app.socket.emit({'type': 'friends', 'userId': 10, 'name': 'Dario', 'added': true});
      await settle(tester);
      expect(find.text(it.friendAddedYou('Dario')), findsOneWidget);
    });
  });

  group('phone: pause and battery', () {
    const config = PhoneConfig(server: 'https://tracking.test', userId: 1, deviceId: 3, token: 'upload-1');
    Fix fix() => (time: DateTime.now(), lat: 45.07, lon: 7.68, accuracy: 8, speed: 30, altitude: null);

    test('battery when it changes, the pause drops the fixes and is sent, resume', () async {
      final backend = FakeBackend()..on('POST', '/api/phones/positions', (_) => {'accepted': 1});
      Map<String, dynamic> body(int index) => jsonDecode(backend.calls('/api/phones/positions')[index].body) as Map<String, dynamic>;
      final fixes = StreamController<Fix>();
      var battery = 70;
      final statuses = <PhoneStatus>[];
      final uploader = PhoneUploader(config, fixes.stream,
          client: backend.client, uploadEvery: Duration.zero, keepAlive: null, battery: () async => battery, onStatus: statuses.add)
        ..start();
      fixes.add(fix());
      await pumpEventQueue();
      expect(body(0)['battery'], 70);
      expect(body(0).containsKey('pausedUntil'), isFalse);
      fixes.add(fix());
      await pumpEventQueue();
      expect(body(1).containsKey('battery'), isFalse);
      battery = 69;
      fixes.add(fix());
      await pumpEventQueue();
      expect(body(2)['battery'], 69);

      uploader.pause(const Duration(hours: 1));
      await pumpEventQueue();
      expect(body(3)['positions'], isEmpty);
      expect(DateTime.parse(body(3)['pausedUntil'] as String).isAfter(DateTime.now()), isTrue);
      expect(uploader.paused, isTrue);
      expect(statuses.last.pausedUntil, isNotNull);
      fixes.add(fix());
      await pumpEventQueue();
      expect(backend.calls('/api/phones/positions').length, 4);

      uploader.pause(null);
      await pumpEventQueue();
      expect(body(4).containsKey('pausedUntil'), isTrue);
      expect(body(4)['pausedUntil'], isNull);
      expect(uploader.paused, isFalse);
      uploader.stop();

      // The pause ends by itself
      final short = PhoneUploader(config, const Stream.empty(), client: backend.client, keepAlive: null)..start();
      short.pause(const Duration(milliseconds: 20));
      expect(short.paused, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(short.paused, isFalse);
      short.stop();

      final until = DateTime(2026, 1, 1, 10, 30);
      expect(PhoneStatus.fromJson(PhoneStatus(pausedUntil: until).toJson()).pausedUntil, until);
      expect(PhoneStatus.fromJson(const PhoneStatus().toJson()).pausedUntil, isNull);
    });

    testWidgets('pause and resume from the phone screen', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [ownerDevice(), phoneDevice()])
        ..on('POST', '/api/phones/3/token', (_) => {'uploadToken': 'upload-2'})
        ..on('POST', '/api/phones/positions', (_) => {'accepted': 0});
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3, 'phone.1.sharing': true});
      expect(app.phone.sharing, isTrue);
      app.go(tester, '/devices/phone');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.phonePauseHour));
      expect(app.phone.paused, isTrue);
      expect(find.textContaining(it.phonePausedUntil('').trim()), findsOneWidget);
      expect(backend.lastBody('/api/phones/positions')['battery'], 80);
      await tapAndSettle(tester, find.text(it.phoneResume));
      expect(app.phone.paused, isFalse);
      expect(find.text(it.phoneSharing), findsOneWidget);
      expect(backend.lastBody('/api/phones/positions')['pausedUntil'], isNull);
    });

    testWidgets('friends see battery and pause, also in realtime', (tester) async {
      final paused = DateTime.now().add(const Duration(minutes: 40));
      final shared = {...phoneDevice(owner: false), 'battery': 54, 'pausedUntil': iso(paused)};
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [shared])
        ..on('GET', '/api/devices/3', (_) => shared)
        ..on('GET', '/api/devices/3/geofences', (_) => []);
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      expect(find.textContaining(it.battery(54)), findsOneWidget);
      expect(find.textContaining(it.phonePausedUntil(formatTimeForTest(paused))), findsOneWidget);

      app.go(tester, '/devices/3');
      await settle(tester);
      expect(find.textContaining(it.battery(54)), findsOneWidget);
      app.socket.emit({'type': 'device', 'deviceId': 3, 'battery': 41, 'pausedUntil': null});
      await settle(tester);
      expect(find.textContaining(it.battery(41)), findsOneWidget);
      expect(find.textContaining(it.sharingActive), findsOneWidget);
    });
  });

  group('map clusters', () {
    test('devices too close at a zoom are grouped', () {
      Device at(int id, double lat) => Device.fromJson(withPosition({...ownerDevice(), 'id': id}, lat, 7.68));
      final devices = [at(1, 45.07), at(2, 45.070225), at(3, 45.12), Device.fromJson({...ownerDevice(), 'id': 4, 'lastPosition': null})];
      expect(clusterDevices(devices, 10).map((group) => group.map((d) => d.id).toList()), [
        [1, 2],
        [3],
      ]);
      expect(clusterDevices(devices, 18).length, 3);
      expect(mercatorPixels(const LatLng(0, 0), 0), const Offset(128, 128));
    });

    testWidgets('a tap on a cluster zooms in, then lists the devices in the same place', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [
              withPosition(ownerDevice(), 45.07, 7.68),
              withPosition(phoneDevice(), 45.07, 7.68),
              withPosition({...viewerDevice(), 'id': 2}, 45.070225, 7.68),
            ]);
      final app = TestApp(backend);
      await app.start(tester);
      Finder count(String text) => find.descendant(of: find.byKey(const Key('cluster1')), matching: find.text(text));
      expect(count('3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cluster1')));
      await settle(tester);
      // Zoomed in: the viewer device apart, the two in the same place still together
      expect(count('2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cluster1')));
      await settle(tester);
      expect(find.text('Pixel'), findsOneWidget);
      await tester.tap(find.text('Pixel'));
      await settle(tester);
      expect(find.text('Pixel'), findsWidgets);
    });
  });

  group('trips and export', () {
    testWidgets('trips of a phone, map of a trip, GPX and CSV files', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/3', (_) => phoneDevice())
        ..on('GET', '/api/devices/3/shares', (_) => [])
        ..on('GET', '/api/devices/3/geofences', (_) => [])
        ..on('GET', '/api/devices/3/positions', (_) => {
              'positions': [positionJson(age: const Duration(minutes: 50)), positionJson(age: const Duration(minutes: 40), lat: 45.08)],
              'truncated': false,
            })
        ..on('GET', '/api/devices/3/trips', (_) => {
              'trips': [tripJson(const Duration(minutes: 50), 10)],
              'days': [
                {'day': '2026-11-21', 'distanceKm': 4.2, 'drivingMin': 10, 'trips': 1},
              ],
              'totals': {'distanceKm': 4.2, 'drivingMin': 10, 'maxSpeed': 48, 'trips': 1},
            })
        ..on('GET', '/api/devices/3/export', (request) => RawReply(
              utf8.encode('<gpx/>'),
              {'content-disposition': 'attachment; filename="Pixel-2026-11-21.${request.url.queryParameters['format']}"'},
            ));
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3});
      app.go(tester, '/devices/3?tab=2');
      await settle(tester);
      expect(find.text(it.exportPeriod), findsOneWidget);
      expect(backend.calls('/api/devices/3/stats'), isEmpty);

      await tapAndSettle(tester, find.text('GPX'));
      expect(app.saved.single.name, 'Pixel-2026-11-21.gpx');
      expect(app.saved.single.mimeType, 'application/gpx+xml');
      expect(utf8.decode(app.saved.single.bytes), '<gpx/>');
      await tapAndSettle(tester, find.text('CSV'));
      expect(app.saved.last.name, 'Pixel-2026-11-21.csv');
      expect(backend.calls('/api/devices/3/export').last.url.queryParameters['from'], isNotNull);
      backend.on('GET', '/api/devices/3/export', (_) => Reply.error(400, 'period_too_long'));
      await tapAndSettle(tester, find.text('CSV'));
      expect(find.text(it.errPeriodTooLong), findsOneWidget);
      await clearSnackbars(tester);

      await tapAndSettle(tester, find.text(it.tripsList(1)));
      await tapAndSettle(tester, find.byIcon(Icons.map_outlined));
      expect(find.byIcon(Icons.trip_origin), findsOneWidget);
      await tapAndSettle(tester, find.byIcon(Icons.close));
      expect(find.byIcon(Icons.trip_origin), findsNothing);
    });

    testWidgets('a download without a file name uses the path', (tester) async {
      final backend = fullBackend()..on('GET', '/api/account/export', (_) => RawReply([1, 2], {}));
      final app = TestApp(backend);
      await app.start(tester);
      final file = await app.api.download('/api/account/export');
      expect(file.name, 'export');
      expect(file.bytes, [1, 2]);
    });
  });

  group('account data', () {
    testWidgets('export of the data, deletion with the email and the code', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/account', (_) => accountJson())
        ..on('GET', '/api/account/export', (_) => RawReply(utf8.encode('{}'), {'content-disposition': 'attachment; filename="car-tracking-2026-11-21.json"'}))
        ..on('DELETE', '/api/account', (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body['code'] == null ? Reply.error(401, 'step_up_required') : {'ok': true};
        });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.exportData));
      expect(app.saved.single.name, 'car-tracking-2026-11-21.json');

      await tapAndSettle(tester, find.text(it.deleteAccount));
      expect(find.text(it.deleteAccountTitle), findsOneWidget);
      FilledButton confirm() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, it.deleteAccount));
      expect(confirm().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('deleteEmail')), 'Anna@Example.com ');
      await settle(tester, 2);
      expect(confirm().onPressed, isNotNull);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.deleteAccount));
      // Old login: the code of the authenticator app
      await tester.enterText(find.byKey(const Key('totp')), '123456');
      await tapAndSettle(tester, find.text(it.confirm));
      expect(backend.lastBody('/api/account', 'DELETE'), {'email': 'Anna@Example.com', 'code': '123456'});
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('deletion refused, or cancelled', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/account', (_) => accountJson())
        ..on('DELETE', '/api/account', (_) => Reply.error(400, 'last_admin'));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.deleteAccount));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/account', 'DELETE'), isEmpty);
      await tapAndSettle(tester, find.text(it.deleteAccount));
      await tester.enterText(find.byKey(const Key('deleteEmail')), 'anna@example.com');
      await settle(tester, 2);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.deleteAccount));
      expect(find.text(it.errLastAdmin), findsOneWidget);
    });
  });

  group('firmware updates', () {
    Map<String, dynamic> state({Map<String, dynamic>? update, bool available = true}) => {
          'version': '1.2.0',
          'variant': 'default',
          'available': [
            if (available) {'id': 4, 'version': '1.3.0', 'size': 1258291, 'notes': 'GPS migliore', 'createdAt': iso(ago(const Duration(days: 1)))},
          ],
          'update': update,
          'autoUpdate': true,
          'updateCheckedAt': null,
        };
    Map<String, dynamic> update({int sent = 0, String? status, bool finished = false, bool automatic = false}) => {
          'automatic': automatic,
          'firmwareId': 4,
          'version': '1.3.0',
          'size': 1000,
          'sent': sent,
          'status': status,
          'requestedAt': iso(ago(const Duration(minutes: 5))),
          'finishedAt': finished ? iso(ago(const Duration(minutes: 1))) : null,
        };

    testWidgets('owner: available version, install, progress, cancel, results', (tester) async {
      var current = state();
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/firmware', (_) => current)
        ..on('POST', '/api/devices/1/firmware', (_) {
          current = state(update: update());
          return current['update'];
        })
        ..on('DELETE', '/api/devices/1/firmware', (_) {
          current = state();
          return {'ok': true};
        });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=4');
      await settle(tester);
      await reveal(tester, find.text(it.firmwareAvailable('1.3.0')));
      expect(find.text('GPS migliore'), findsOneWidget);

      await tapAndSettle(tester, find.text(it.firmwareInstall));
      expect(find.text(it.firmwareInstallTitle('1.3.0')), findsOneWidget);
      expect(find.textContaining(it.firmwareInstallBody('1,2')), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/firmware', 'POST'), isEmpty);
      await tapAndSettle(tester, find.text(it.firmwareInstall));
      await tapAndSettle(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text(it.firmwareInstall)));
      expect(backend.lastBody('/api/devices/1/firmware', 'POST'), {'firmwareId': 4});
      expect(find.text(it.firmwareWaiting('1.3.0')), findsOneWidget);

      // Progress in realtime
      current = state(update: update(sent: 500));
      app.socket.emit({'type': 'firmware', 'deviceId': 1, 'update': current['update']});
      await settle(tester);
      expect(find.text(it.firmwareDownloading('1.3.0')), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/firmware', 'DELETE').length, 1);
      expect(find.text(it.firmwareAvailable('1.3.0')), findsOneWidget);

      backend.on('POST', '/api/devices/1/firmware', (_) => Reply.error(400, 'not_newer'));
      await tapAndSettle(tester, find.text(it.firmwareInstall));
      await tapAndSettle(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text(it.firmwareInstall)));
      expect(find.text(it.errFirmware), findsOneWidget);

      current = state(update: update(status: 'done', finished: true), available: false);
      app.socket.emit({'type': 'firmware', 'deviceId': 1, 'update': current['update']});
      await settle(tester);
      expect(find.text(it.firmwareDone('1.3.0')), findsOneWidget);

      // Automatic updates: this firmware never asked; switched off by the owner
      expect(find.text(it.autoUpdateNever), findsOneWidget);
      backend.on('PUT', '/api/devices/1/firmware/auto', (_) {
        current = {...current, 'autoUpdate': false, 'updateCheckedAt': iso(ago(const Duration(hours: 3)))};
        return current;
      });
      await reveal(tester, find.byKey(const Key('autoUpdate')));
      await tapAndSettle(tester, find.byKey(const Key('autoUpdate')));
      expect(backend.lastBody('/api/devices/1/firmware/auto', 'PUT'), {'enabled': false});
      await settle(tester);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('autoUpdate'))).value, isFalse);
      expect(find.textContaining(it.autoUpdateChecked('').trim()), findsOneWidget);
    });

    test('status texts', () {
      Map<String, dynamic> u(String? status, [int sent = 0]) => {'version': '2.0', 'status': status, 'sent': sent};
      expect(firmwareStatusText(it, u(null)), it.firmwareWaiting('2.0'));
      expect(firmwareStatusText(it, u(null, 10)), it.firmwareDownloading('2.0'));
      expect(firmwareStatusText(it, u('installed')), it.firmwareRebooting('2.0'));
      expect(firmwareStatusText(it, u('done')), it.firmwareDone('2.0'));
      expect(firmwareStatusText(it, u('not_applied')), it.firmwareNotApplied('2.0'));
      expect(firmwareStatusText(it, u('bad_hash')), it.firmwareFailed('2.0'));
      expect(firmwareStatusText(it, {...u('done'), 'automatic': true}), '${it.firmwareDone('2.0')} · ${it.firmwareAutomatic}');
    });

    testWidgets('up to date; error; administrator list and removal', (tester) async {
      var images = [
        {'id': 4, 'version': '1.3.0', 'variant': 'default', 'size': 1258291, 'sha256': 'ab', 'notes': 'GPS', 'createdAt': iso(ago(const Duration(days: 1))), 'pending': 2},
      ];
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/firmware', (_) => state(available: false))
        ..on('GET', '/api/account', (_) => accountJson())
        ..on('GET', '/api/admin/users', (_) => [])
        ..on('GET', '/api/admin/invites', (_) => [])
        ..on('GET', '/api/admin/firmware', (_) => images)
        ..on('DELETE', '/api/admin/firmware/4', (_) {
          images = [];
          return {'ok': true};
        });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=4');
      await settle(tester);
      await reveal(tester, find.text(it.firmwareUpToDate('1.2.0')));
      backend.on('GET', '/api/devices/1/firmware', (_) => Reply.error(500, 'internal'));
      app.socket.emit({'type': 'firmware', 'deviceId': 1, 'update': null});
      await settle(tester);
      expect(find.byIcon(Icons.system_update), findsOneWidget);

      app.go(tester, '/account/admin');
      await settle(tester);
      await reveal(tester, find.text('1.3.0 · default'));
      expect(find.textContaining(it.firmwarePending(2)), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.delete));
      expect(backend.calls('/api/admin/firmware/4', 'DELETE').length, 1);
      expect(find.text('1.3.0 · default'), findsNothing);
    });
  });
  group('app updates', () {
    Map<String, dynamic> release(String version) => {
          'release': {
            'version': version,
            'url': 'https://github.com/me/car-tracking/releases/tag/v$version',
            'apkUrl': 'https://github.com/me/car-tracking/releases/download/v$version/car-tracking.apk',
            'publishedAt': iso(DateTime(2026, 11, 20)),
          },
        };

    test('versions compared by number', () {
      expect(isNewerVersion('1.10.0', '1.9.3'), isTrue);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('2.0.0', '2.0.1'), isFalse);
      expect(isNewerVersion('2.0.1', '2'), isTrue);
    });

    testWidgets('Android app older than the release: banner, download', (tester) async {
      final backend = fullBackend()..on('GET', '/api/app/release', (_) => release('1.1.0'));
      final app = TestApp(backend)..appBuild = (version: '1.0.0', updatable: true);
      await app.start(tester);
      expect(find.text(it.appUpdateAvailable('1.1.0')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('appUpdateDownload')));
      expect(app.opened.single.path, '/me/car-tracking/releases/download/v1.1.0/car-tracking.apk');
      expect(find.byKey(const Key('appUpdate')), findsNothing);
    });

    testWidgets('later: not shown again for that version', (tester) async {
      final backend = fullBackend()..on('GET', '/api/app/release', (_) => release('1.1.0'));
      final app = TestApp(backend)..appBuild = (version: '1.0.0', updatable: true);
      await app.start(tester);
      await tapAndSettle(tester, find.text(it.later));
      expect(find.byKey(const Key('appUpdate')), findsNothing);
      expect((await SharedPreferences.getInstance()).getString('appUpdateDismissed'), '1.1.0');
    });

    testWidgets('no banner: dismissed, up to date, no release, error, web app', (tester) async {
      for (final (build, prefs, reply) in [
        ((version: '1.0.0', updatable: true), {'appUpdateDismissed': '1.1.0'}, release('1.1.0')),
        ((version: '1.1.0', updatable: true), <String, Object>{}, release('1.1.0')),
        ((version: '1.0.0', updatable: true), <String, Object>{}, {'release': null}),
        ((version: '1.0.0', updatable: true), <String, Object>{}, Reply.error(500, 'internal')),
        ((version: '1.0.0', updatable: false), <String, Object>{}, release('1.1.0')),
      ]) {
        final backend = fullBackend()..on('GET', '/api/app/release', (_) => reply);
        final app = TestApp(backend)..appBuild = build;
        await app.start(tester, prefs: prefs);
        expect(find.byKey(const Key('appUpdate')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('alerts', () {
    test('texts of the new notifications, schedules', () {
      NotificationData data({int? battery, int? hours}) => NotificationData(device: 'Pixel', time: DateTime(2026, 11, 23, 9, 5), battery: battery, hours: hours);
      expect(notificationText(it, 'phone_battery', data(battery: 20)).title, it.kindPhoneBattery('Pixel', 20));
      expect(notificationText(it, 'phone_battery', data(battery: 20)).body, it.notificationBodyPhoneBattery('09:05'));
      expect(notificationText(it, 'long_stop', data(hours: 4)).title, it.kindLongStop('Pixel', 4));
      expect(notificationText(it, 'long_stop', data(hours: 1)).title, it.kindLongStop('Pixel', 1));
      expect(it.kindLongStop('Pixel', 1), contains("un'ora"));
      expect(en.kindLongStop('Pixel', 1), contains('an hour'));
      // Singular and plural
      expect([it.inDays(1), it.inDays(3), en.overdueDays(1), it.backupFiles(1, '1 MB'), en.phoneQueued(2)],
          ['tra 1 giorno', 'tra 3 giorni', 'overdue by 1 day', '1 copia, 1 MB in totale', '2 positions to send']);
      final firmware = NotificationData.fromJson({'device': 'Panda', 'version': '2.5.0', 'automatic': true}, DateTime(2026));
      expect(notificationText(it, 'firmware', firmware), (title: it.firmwareNewTitle('2.5.0'), body: it.firmwareNewAutomatic('Panda')));
      expect(notificationText(it, 'firmware', NotificationData(device: 'Panda', time: DateTime(2026))).body, it.firmwareNewManual('Panda'));
      expect(kindLabel(it, 'firmware'), it.kindFirmware);
      expect(notificationText(it, 'long_stop', data(hours: 1)).body, it.notificationBodyLongStop('09:05'));
      final parsed = NotificationData.fromJson({'device': 'Pixel', 'battery': 18, 'hours': 2}, DateTime(2026));
      expect((parsed.battery, parsed.hours), (18, 2));
      AppNotification of(String kind) => AppNotification.fromJson(
          {'id': 1, 'deviceId': 3, 'kind': kind, 'data': {'device': 'Pixel'}, 'createdAt': iso(DateTime(2026))});
      expect(of('phone_battery').icon, Icons.battery_alert);
      expect(of('long_stop').icon, Icons.timer);
      expect(of('firmware').icon, Icons.system_update);

      final schedule = AreaSchedule.fromJson({'days': [5, 1], 'from': '22:30', 'to': '06:00'});
      expect(schedule.toJson(), {'days': [1, 5], 'from': '22:30', 'to': '06:00'});
      expect(scheduleText(it, schedule), '${weekdayName(1)} ${weekdayName(5)} 22:30–06:00');
      expect(scheduleText(it, AreaSchedule.fromJson({'days': [7], 'from': '00:00', 'to': '00:00'})), '${weekdayName(7)} ${it.areaAllDay}');
      expect(stopAlertText(it, null), it.stopAlertOff);
      expect(stopAlertText(it, 1), it.stopAlertAfterOne);
      expect(stopAlertText(it, 8), it.stopAlertAfter(8));
    });

    testWidgets('areas only at certain times: days, hours, removal', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/geofences', (_) => [
              {'id': 10, 'deviceId': 1, 'name': 'Casa', 'lat': 45.07, 'lon': 7.68, 'radius': 500, 'notifyEnter': true, 'notifyExit': true,
                'inside': true, 'schedule': {'days': [1], 'from': '23:00', 'to': '06:00'}},
            ])
        ..on('PATCH', '/api/geofences/10', (_) => {'ok': true})
        ..on('POST', '/api/devices/1/geofences', (_) => {'id': 12});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=3');
      await settle(tester);
      expect(find.textContaining('${weekdayName(1)} 23:00–06:00'), findsOneWidget);

      await tapAndSettle(tester, find.text('Casa'));
      // The last day stays selected
      await tapAndSettle(tester, find.byKey(const Key('day1')));
      await tapAndSettle(tester, find.byKey(const Key('day6')));
      await tapAndSettle(tester, find.byKey(const Key('areaFrom')));
      final ok = MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog))).okButtonLabel;
      await tapAndSettle(tester, find.text(ok));
      await tapAndSettle(tester, find.byKey(const Key('areaTo')));
      Navigator.of(tester.element(find.byType(TimePickerDialog))).pop();
      await settle(tester);
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(backend.lastBody('/api/geofences/10', 'PATCH')['schedule'], {'days': [1, 6], 'from': '23:00', 'to': '06:00'});

      await tapAndSettle(tester, find.text('Casa'));
      await tapAndSettle(tester, find.byKey(const Key('areaScheduled')));
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(backend.lastBody('/api/geofences/10', 'PATCH')['schedule'], isNull);

      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.addArea));
      await tapAndSettle(tester, find.byKey(const Key('areaScheduled')));
      expect(find.text(it.areaFrom('08:00')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(backend.lastBody('/api/devices/1/geofences', 'POST')['schedule'], {'days': [1, 2, 3, 4, 5], 'from': '08:00', 'to': '18:00'});
    });

    testWidgets('long stop: off, after some hours', (tester) async {
      final backend = fullBackend()..on('PATCH', '/api/devices/1/alerts', (_) => {'ok': true});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=4');
      await settle(tester);
      await reveal(tester, find.text(it.stopAlertOff));
      await tapAndSettle(tester, find.byKey(const Key('stopAlert')));
      await tapAndSettle(tester, find.byKey(const Key('stop4')));
      expect(backend.lastBody('/api/devices/1/alerts', 'PATCH'), {'stopAlertHours': 4});
      expect(find.text(it.stopAlertAfter(4)), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('stopAlert')));
      await tapAndSettle(tester, find.byKey(const Key('stop1')));
      expect(find.text(it.stopAlertAfterOne), findsOneWidget);
      // Dismissed: nothing changes
      await tapAndSettle(tester, find.byKey(const Key('stopAlert')));
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(backend.calls('/api/devices/1/alerts', 'PATCH'), hasLength(2));
      backend.on('PATCH', '/api/devices/1/alerts', (_) => Reply.error(500, 'internal'));
      await tapAndSettle(tester, find.byKey(const Key('stopAlert')));
      await tapAndSettle(tester, find.byKey(const Key('stop0')));
      expect(find.text(it.stopAlertAfterOne), findsOneWidget);
      expect(Device.fromJson({...ownerDevice(), 'stopAlertHours': 12}).stopAlertHours, 12);
    });

    testWidgets('viewer: own long stop and low battery alerts on a shared phone', (tester) async {
      final shared = {...phoneDevice(owner: false), 'battery': 54, 'batteryAlert': 20, 'stopAlertHours': null};
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [shared])
        ..on('GET', '/api/devices/3', (_) => shared)
        ..on('GET', '/api/devices/3/geofences', (_) => [])
        ..on('PATCH', '/api/devices/3/alerts', (_) => {'ok': true});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/3');
      await settle(tester);
      Future<void> menu(String text) async {
        await tapAndSettle(tester, find.byKey(const Key('viewerMenu')));
        await tapAndSettle(tester, find.textContaining(text));
      }

      await menu('${it.batteryAlert}: ${it.batteryAlertAt(20)}');
      await tapAndSettle(tester, find.byKey(const Key('battery30')));
      expect(backend.lastBody('/api/devices/3/alerts', 'PATCH'), {'batteryAlert': 30});
      await menu('${it.stopAlert}: ${it.stopAlertOff}');
      await tapAndSettle(tester, find.byKey(const Key('stop2')));
      expect(backend.lastBody('/api/devices/3/alerts', 'PATCH'), {'stopAlertHours': 2});
      await menu('${it.batteryAlert}: ${it.batteryAlertAt(30)}');
      await tapAndSettle(tester, find.byKey(const Key('battery0')));
      expect(backend.lastBody('/api/devices/3/alerts', 'PATCH'), {'batteryAlert': null});
      // Dismissed, failed: nothing changes
      await menu('${it.stopAlert}: ${it.stopAlertAfter(2)}');
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      backend.on('PATCH', '/api/devices/3/alerts', (_) => Reply.error(500, 'internal'));
      await menu('${it.batteryAlert}: ${it.stopAlertOff}');
      await tapAndSettle(tester, find.byKey(const Key('battery10')));
      expect(backend.calls('/api/devices/3/alerts', 'PATCH'), hasLength(4));
      expect(batteryAlertText(it, 15), it.batteryAlertAt(15));
      // The share can still be left
      await menu(it.leaveShare);
      await tapAndSettle(tester, find.text(it.cancel));
    });
  });
}

String formatTimeForTest(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
