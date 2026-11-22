import 'package:car_tracking/screens/device/areas_tab.dart';
import 'package:car_tracking/screens/devices.dart';
import 'package:car_tracking/widgets/charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

int _unix(Duration fromNow) => DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;

/// Backend with the data of the analysis endpoints
FakeBackend analysisBackend({bool empty = false}) {
  final b = fullBackend();
  final hour = DateTime.now().subtract(const Duration(hours: 2));
  Map<String, dynamic> row(int i, {bool climate = true}) => {
        'bucket': iso(hour.add(Duration(hours: i))),
        'avg_speed': 40 + i,
        'max_speed': i == 1 ? null : 90,
        'avg_signal': -80,
        'min_signal': -100,
        'avg_satellites': 9,
        'min_satellites': 5,
        'altitude': 240,
        'voltage': 12.4,
        'min_voltage': 11.7,
        'temperature': climate ? 20 + i : null,
        'pressure': climate ? 990 : null,
        'points': 30,
        'stale_points': 2,
      };
  b.on('GET', '/api/devices/1/stats', (_) => {'bucket': '1 hour', 'series': empty ? [] : [row(0), row(1), row(2)]});
  b.on('GET', '/api/devices/1/trips', (_) => {
        'totals': {'distanceKm': 12.34, 'drivingMin': 75, 'maxSpeed': 110, 'trips': 2},
        'days': empty
            ? []
            : [
                {'day': '2026-11-20', 'distanceKm': 5, 'drivingMin': 30},
                {'day': '2026-11-21', 'distanceKm': 7.34, 'drivingMin': 45},
              ],
        'trips': empty
            ? []
            : [
                {'start': iso(hour), 'end': iso(hour.add(const Duration(minutes: 30))), 'distanceKm': 5, 'durationMin': 30, 'avgSpeed': 40, 'maxSpeed': 90},
                {'start': iso(hour), 'end': iso(hour.add(const Duration(minutes: 90))), 'distanceKm': 7.34, 'durationMin': 90, 'avgSpeed': 50, 'maxSpeed': 110},
              ],
      });
  b.on('GET', '/api/devices/1/distribution', (_) => {
        'quality': {'total': 100, 'stale': 5, 'weak_fix': 10, 'weak_signal': 20},
        'signal': [for (final v in [-70, -85, -100, -110]) {'value': v, 'count': 25}],
        'satellites': [for (final v in [3, 5, 7, 10]) {'value': v, 'count': 25}],
        'speed': empty ? [] : [for (final v in [0, 10, 50]) {'value': v, 'count': 10}],
      });
  b.on('GET', '/api/devices/1/coverage', (_) => {
        'cells': [
          {'lat': 45.07, 'lon': 7.68, 'avg_signal': -80, 'points': 10},
          {'lat': 45.08, 'lon': 7.69, 'avg_signal': null, 'points': 2},
        ],
      });
  b.on('GET', '/api/devices/1/traffic', (_) => {
        'budgetBytes': 200 * 1024 * 1024,
        'month': {'estimatedBytes': 5e6, 'projectedBytes': empty ? 2.5e8 : 1.8e8},
        'daily': empty ? [] : [{'day': '2026-11-20', 'estimatedBytes': 200000}, {'day': '2026-11-21', 'estimatedBytes': 250000}],
      });
  return b;
}

Future<TestApp> openDevice(WidgetTester tester, FakeBackend backend, String location) async {
  final app = TestApp(backend);
  await app.start(tester);
  app.go(tester, location);
  await settle(tester);
  return app;
}

Future<void> scrollDown(WidgetTester tester, [int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await settle(tester, 3);
  }
}

void main() {
  setUpAll(initFormats);

  group('live', () {
    testWidgets('owner: data, realtime events, commands', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1', (_) => ownerDevice(liveUntil: _unix(const Duration(minutes: 20))));
      final app = await openDevice(tester, backend, '/devices/1');
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('-80 dBm'), findsOneWidget);
      expect(find.text('9 sat'), findsOneWidget);
      expect(find.text('11,5 V'), findsOneWidget);
      expect(find.text(it.eventTilt), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);

      // Walking directions in Google Maps, a message when nothing opens them
      await tapAndSettle(tester, find.byKey(const Key('walkTo')));
      final route = app.opened.single;
      expect([route.host, route.path, route.queryParameters['destination'], route.queryParameters['travelmode']],
          ['www.google.com', '/maps/dir/', '45.07,7.68', 'walking']);
      app.canOpen = false;
      await tapAndSettle(tester, find.byKey(const Key('walkTo')));
      expect(find.text(it.openFailed), findsOneWidget);
      await clearSnackbars(tester);
      expect(app.socket.sent.any((m) => m['type'] == 'watch' && m['deviceId'] == 1), isTrue);

      await tapAndSettle(tester, find.text(it.live30));
      expect(backend.lastBody('/api/devices/1/commands'), {'type': 'live', 'seconds': 1800});
      expect(find.text(it.commandSent), findsOneWidget);
      await tapAndSettle(tester, find.text(it.stopLive));
      expect(backend.lastBody('/api/devices/1/commands'), {'type': 'live', 'seconds': 0});
      await tapAndSettle(tester, find.text(it.locate));
      expect(backend.lastBody('/api/devices/1/commands'), {'type': 'locate', 'seconds': 0});

      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.pauseAntitheft));
      await tapAndSettle(tester, find.text(it.pause24h));
      expect(backend.lastBody('/api/devices/1/commands'), {'type': 'antitheft', 'seconds': 86400});

      backend.on('POST', '/api/devices/1/commands', (_) => Reply.error(400, 'live_too_long'));
      await tapAndSettle(tester, find.text(it.live30));
      expect(find.text(it.errLiveTooLong), findsOneWidget);

      await clearSnackbars(tester);
      await tapAndSettle(tester, find.byIcon(Icons.gps_fixed));
      expect(find.byIcon(Icons.gps_not_fixed), findsOneWidget);
      app.socket.emit({'type': 'position', 'deviceId': 1, 'position': positionJson(age: Duration.zero, lat: 45.2)});
      await settle(tester);
      await tapAndSettle(tester, find.byIcon(Icons.gps_not_fixed));
      app.socket.emit({'type': 'position', 'deviceId': 1, 'position': positionJson(age: Duration.zero, lat: 45.3)});
      app.socket.emit({'type': 'position', 'deviceId': 1, 'position': positionJson(age: const Duration(hours: 1), lat: 45.1)});
      app.socket.emit({'type': 'device', 'deviceId': 1, 'online': true, 'lastSeenAt': iso(DateTime.now())});
      app.socket.emit({'type': 'device', 'deviceId': 1});
      app.socket.emit({'type': 'command', 'deviceId': 1});
      await settle(tester);
      expect(backend.calls('/api/devices/1', 'GET').length, greaterThan(1));

      app.go(tester, '/devices');
      await settle(tester);
      expect(app.socket.sent.last, {'type': 'unwatch', 'deviceId': 1});
    });

    testWidgets('owner: offline tracker, paused antitheft, cell position', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/1', (_) => {
              ...ownerDevice(connected: false, pausedUntil: _unix(const Duration(hours: 5))),
              'lastPosition': positionJson(lat: null, lon: null, stale: true, status: 2, full: false),
            })
        ..on('GET', '/api/devices/1/positions', (_) => Reply.error(500, 'x'));
      await openDevice(tester, backend, '/devices/1');
      expect(find.textContaining(it.cellEstimate('900')), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.text(it.notAvailable), findsNWidgets(2));
      await tapAndSettle(tester, find.byIcon(Icons.shield));
      expect(backend.lastBody('/api/devices/1/commands'), {'type': 'antitheft', 'seconds': 0});
      expect(find.text(it.commandQueued), findsOneWidget);
    });

    testWidgets('owner: no position yet, then the stale last known one', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1', (_) => {...ownerDevice(), 'lastPosition': null});
      final app = await openDevice(tester, backend, '/devices/1');
      expect(find.text(it.noPositionReceived), findsOneWidget);
      expect(find.byKey(const Key('walkTo')), findsNothing);
      app.socket.emit({'type': 'position', 'deviceId': 1, 'position': positionJson(stale: true, status: 1, full: false)});
      await settle(tester);
      expect(find.textContaining(it.noFix), findsOneWidget);
    });

    testWidgets('viewer: notice, two tabs, leave the share', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/2', (_) => viewerDevice(expires: DateTime(2026, 12, 24, 18)))
        ..on('DELETE', '/api/devices/2/access', (_) => Reply.error(409, 'owner_cannot_leave'));
      final app = await openDevice(tester, backend, '/devices/2');
      expect(find.text(it.viewerNotice('Mario', it.viewerUntil('24 dic 2026 18:00'))), findsOneWidget);
      expect(find.text(it.tabHistory), findsNothing);
      expect(find.text(it.live30), findsNothing);
      expect(find.text('-80 dBm'), findsNothing);

      await tapAndSettle(tester, find.byIcon(Icons.more_vert));
      await tapAndSettle(tester, find.text(it.leaveShare));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/2/access'), isEmpty);

      await tapAndSettle(tester, find.byIcon(Icons.more_vert));
      await tapAndSettle(tester, find.text(it.leaveShare));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.leaveShare));
      expect(find.text(it.errOwnerCannotLeave), findsOneWidget);

      backend.on('DELETE', '/api/devices/2/access', (_) => {'ok': true});
      await tapAndSettle(tester, find.byIcon(Icons.more_vert));
      await tapAndSettle(tester, find.text(it.leaveShare));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.leaveShare));
      expect(find.byType(DevicesScreen), findsOneWidget);
      expect(app.backend.calls('/api/devices/2/access', 'DELETE'), hasLength(2));
    });

    testWidgets('loading errors', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1', (_) => Reply.error(404, 'not_found'));
      await openDevice(tester, backend, '/devices/1');
      expect(find.text(it.errNotFound), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('colorings, replay, events, period', (tester) async {
      final app = await openDevice(tester, fullBackend(), '/devices/1?tab=1');
      expect(find.text(it.truncated), findsOneWidget);

      for (final label in [it.coloringSpeed, it.coloringSignal, it.coloringSatellites, it.coloringPlain]) {
        await tapAndSettle(tester, find.text(label));
      }
      await tapAndSettle(tester, find.text(it.coloringSatellites));
      expect(find.text(it.legendNoFix), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(-400, 0));
      await settle(tester);
      expect(find.textContaining(it.statusMoving), findsWidgets);
      await tapAndSettle(tester, find.byIcon(Icons.warning_amber));
      expect(find.textContaining(it.eventMotion), findsOneWidget);
      await tapAndSettle(tester, find.byIcon(Icons.local_parking));
      expect(find.textContaining(it.statusEngineOff), findsOneWidget);

      // Period: preset, then custom range
      await tapAndSettle(tester, find.text(it.last24h));
      await tapAndSettle(tester, find.text(it.periodLast7d));
      expect(find.text(it.periodLast7d), findsOneWidget);
      final before = app.backend.calls('/api/devices/1/positions').length;
      await tapAndSettle(tester, find.text(it.periodLast7d));
      await tapAndSettle(tester, find.text(it.periodCustom));
      final material = MaterialLocalizations.of(tester.element(find.byType(Scaffold).last));
      await tapAndSettle(tester, find.text(material.saveButtonLabel));
      expect(app.backend.calls('/api/devices/1/positions').length, greaterThan(before));

      await tapAndSettle(tester, find.byIcon(Icons.date_range).first);
      await tapAndSettle(tester, find.text(it.periodCustom));
      await tapAndSettle(tester, find.byIcon(Icons.close).last);
      await tapAndSettle(tester, find.byIcon(Icons.date_range).first);
      await tester.tapAt(const Offset(200, 50));
      await settle(tester);

      await tapAndSettle(tester, find.text(it.tabLive));
      expect(find.byIcon(Icons.date_range), findsNothing);
    });

    testWidgets('empty period and errors', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1/positions', (_) => {'positions': [positionJson()]});
      await openDevice(tester, backend, '/devices/1?tab=1');
      expect(find.byType(Slider), findsNothing);
      backend.on('GET', '/api/devices/1/positions', (_) => {'positions': []});
      await tapAndSettle(tester, find.text(it.last24h));
      await tapAndSettle(tester, find.text(it.periodLast30d));
      expect(find.text(it.noPositions), findsOneWidget);
      backend.on('GET', '/api/devices/1/positions', (_) => Reply.error(400, 'period_too_long'));
      await tapAndSettle(tester, find.text(it.periodLast30d));
      await tapAndSettle(tester, find.text(it.periodLast90d));
      expect(find.text(it.errPeriodTooLong), findsOneWidget);
    });
  });

  group('analysis', () {
    testWidgets('all the sections', (tester) async {
      final app = await openDevice(tester, analysisBackend(), '/devices/1?tab=2');
      expect(find.text('12,3 km'), findsOneWidget);
      expect(find.text('1 h 15 min'), findsOneWidget);
      final before = app.backend.calls('/api/devices/1/stats').length;
      await tester.drag(find.byKey(const Key('openTrends')), const Offset(0, 400));
      await settle(tester);
      expect(app.backend.calls('/api/devices/1/stats').length, greaterThan(before));
      await tapAndSettle(tester, find.text(it.tripsList(2)));
      await reveal(tester, find.textContaining('7,3 km'));
      await scrollDown(tester, 4);
      expect(find.byType(ChartCard), findsWidgets);
      await reveal(tester, find.text(it.simMonth));
      await reveal(tester, find.text(it.dataPerDay));
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 20000));
      await settle(tester);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 400));
      await settle(tester);
    });

    testWidgets('empty period and errors', (tester) async {
      final backend = analysisBackend(empty: true)..on('GET', '/api/devices/1/coverage', (_) => Reply.error(500, 'x'));
      await openDevice(tester, backend, '/devices/1?tab=2');
      await reveal(tester, find.text(it.noData));
      expect(find.text(it.noData), findsOneWidget);
      await reveal(tester, find.text(it.errGeneric(500)));
      await reveal(tester, find.text(it.simMonth));
      expect(find.text(it.dataPerDay), findsNothing);
    });
  });

  group('areas', () {
    testWidgets('list, create, edit, delete', (tester) async {
      final backend = fullBackend()
        ..on('POST', '/api/devices/1/geofences', (_) => Reply.error(400, 'too_many_areas'))
        ..on('PATCH', '/api/geofences/10', (_) => {'ok': true})
        ..on('DELETE', '/api/geofences/11', (_) => Reply.error(404, 'not_found'))
        ..on('DELETE', '/api/geofences/10', (_) => {'ok': true});
      await openDevice(tester, backend, '/devices/1?tab=3');
      expect(find.textContaining(it.areaSummary('500 m', it.areaInside)), findsOneWidget);
      expect(find.textContaining(it.areaSummary('12 km', it.areaOutside)), findsOneWidget);

      await tapAndSettle(tester, find.text(it.addArea));
      expect(find.text(it.tapMapToPlace), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)) + const Offset(30, 30));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('areaName')), 'Scuola');
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tapAndSettle(tester, find.text(it.notifyExit));
      await tapAndSettle(tester, find.text(it.notifyEnter));
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(find.text(it.errTooManyAreas), findsOneWidget);
      final body = backend.lastBody('/api/devices/1/geofences', 'POST');
      expect((body['name'], body['notifyEnter'], body['notifyExit']), ('Scuola', false, true));
      expect(body['radius'], greaterThan(500));
      expect(body['lat'], isNot(45.07));

      backend.on('POST', '/api/devices/1/geofences', (_) => {'id': 12});
      await tester.enterText(find.byKey(const Key('areaName')), '  ');
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(backend.lastBody('/api/devices/1/geofences', 'POST')['name'], it.areaDefaultName);
      expect(find.byType(AreaEditor), findsNothing);

      await tapAndSettle(tester, find.text('Casa'));
      expect(find.text(it.editArea), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('saveArea')));
      expect(backend.lastBody('/api/geofences/10', 'PATCH')['radius'], 500);

      await tapAndSettle(tester, find.byTooltip(it.delete).last);
      await tapAndSettle(tester, find.text(it.cancel));
      await tapAndSettle(tester, find.byTooltip(it.delete).last);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.delete));
      expect(find.text(it.errNotFound), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.delete).first);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.delete));
      expect(backend.calls('/api/geofences/10', 'DELETE'), hasLength(1));
    });

    testWidgets('viewer areas: empty list, no position, errors', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/2/geofences', (_) => [])
        ..on('GET', '/api/devices/2', (_) => {...viewerDevice(), 'lastPosition': null});
      await openDevice(tester, backend, '/devices/2?tab=1');
      expect(find.text(it.noAreas), findsOneWidget);
      await tapAndSettle(tester, find.text(it.addArea));
      await tapAndSettle(tester, find.byType(CloseButton));
      expect(find.text(it.noAreas), findsOneWidget);
    });

    testWidgets('areas that cannot be loaded', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1/geofences', (_) => Reply.error(500, 'x'));
      await openDevice(tester, backend, '/devices/1?tab=3');
      expect(find.text(it.errGeneric(500)), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('name, color, alarm notifications', (tester) async {
      final backend = fullBackend()..on('PATCH', '/api/devices/1', (_) => {'ok': true});
      await openDevice(tester, backend, '/devices/1?tab=4');
      expect(find.text('863820040182648'), findsOneWidget);
      expect(find.textContaining('SIMCOM A7670E'), findsOneWidget);

      await tapAndSettle(tester, find.text(it.tapToRename));
      await tapAndSettle(tester, find.text(it.cancel));
      await tapAndSettle(tester, find.text(it.tapToRename));
      await tester.enterText(find.byKey(const Key('deviceName')), 'Panda 4x4');
      await tapAndSettle(tester, find.text(it.save));
      expect(backend.lastBody('/api/devices/1', 'PATCH'), {'name': 'Panda 4x4'});
      expect(find.text('Panda 4x4'), findsWidgets);

      await tapAndSettle(tester, find.byIcon(Icons.check));
      await tapAndSettle(tester, find.byType(CircleAvatar).at(3));
      expect(backend.lastBody('/api/devices/1', 'PATCH').keys, ['color']);

      await tapAndSettle(tester, find.text(it.kindMotion));
      expect(backend.lastBody('/api/devices/1/notification-settings', 'PUT')['kinds'], containsAll(['tilt', 'power_lost', 'motion']));
      await tapAndSettle(tester, find.text(it.kindTilt));
      expect(backend.lastBody('/api/devices/1/notification-settings', 'PUT')['kinds'], isNot(contains('tilt')));

      backend.on('PATCH', '/api/devices/1', (_) => Reply.error(400, 'validation'));
      await tapAndSettle(tester, find.text(it.tapToRename));
      await tester.enterText(find.byKey(const Key('deviceName')), 'X');
      await tapAndSettle(tester, find.text(it.save));
      expect(find.text(it.errValidation), findsOneWidget);
    });

    testWidgets('sharing: quick durations, custom end, change, revoke', (tester) async {
      final backend = fullBackend()
        ..on('POST', '/api/devices/1/shares', (_) => Reply.error(400, 'share_self'))
        ..on('PATCH', '/api/devices/1/shares/6', (_) => {'ok': true})
        ..on('DELETE', '/api/devices/1/shares/5', (_) => {'ok': true});
      await openDevice(tester, backend, '/devices/1?tab=4');
      await reveal(tester, find.text(it.sharePermanent));
      expect(find.textContaining(it.shareUntil('')), findsOneWidget);

      // Only friends: the first one is chosen
      await tapAndSettle(tester, find.text(it.shareWith));
      await tapAndSettle(tester, find.text(it.hoursShort(3)));
      await tapAndSettle(tester, find.text(it.share));
      expect(find.text(it.errShareSelf), findsOneWidget);
      expect(backend.lastBody('/api/devices/1/shares', 'POST')['userId'], 5);
      final end = DateTime.parse(backend.lastBody('/api/devices/1/shares', 'POST')['expiresAt'] as String);
      expect(end.difference(DateTime.now()).inMinutes, closeTo(180, 2));

      backend.on('POST', '/api/devices/1/shares', (_) => {'ok': true});
      await tapAndSettle(tester, find.text(it.shareWith));
      await tapAndSettle(tester, find.byKey(const Key('shareFriend')));
      await tapAndSettle(tester, find.text('Mario').last);
      await tapAndSettle(tester, find.text(it.daysShort(7)));
      await tapAndSettle(tester, find.text(it.permanent).first);
      await tapAndSettle(tester, find.text(it.share));
      expect(backend.lastBody('/api/devices/1/shares', 'POST'), {'userId': 7, 'expiresAt': null});
      expect(find.text(it.shared), findsOneWidget);

      // Custom end: date then time
      await tapAndSettle(tester, find.text(it.shareWith));
      await tapAndSettle(tester, find.text(it.customEnd));
      final material = MaterialLocalizations.of(tester.element(find.byType(Scaffold).last));
      await tapAndSettle(tester, find.text(material.okButtonLabel));
      await tapAndSettle(tester, find.text(material.okButtonLabel));
      expect(find.text(it.customEnd), findsNothing);
      await tapAndSettle(tester, find.text(it.share));
      expect(backend.lastBody('/api/devices/1/shares', 'POST')['expiresAt'], isNotNull);

      // Picker closed without a date or a time
      await tapAndSettle(tester, find.text(it.shareWith));
      await tapAndSettle(tester, find.text(it.customEnd));
      await tapAndSettle(tester, find.text(material.cancelButtonLabel).last);
      await tapAndSettle(tester, find.text(it.customEnd));
      await tapAndSettle(tester, find.text(material.okButtonLabel));
      await tapAndSettle(tester, find.text(material.cancelButtonLabel).last);
      await tapAndSettle(tester, find.text(it.cancel));

      await tapAndSettle(tester, find.byTooltip(it.changeEnd).last);
      expect(find.text('Sara'), findsWidgets);
      await tapAndSettle(tester, find.text(it.hoursShort(1)));
      await tapAndSettle(tester, find.text(it.save));
      expect(backend.lastBody('/api/devices/1/shares/6', 'PATCH')['expiresAt'], isNotNull);
      await tapAndSettle(tester, find.text('Sara'));
      await tapAndSettle(tester, find.text(it.cancel));

      await tapAndSettle(tester, find.byTooltip(it.revoke).first);
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/shares/5'), isEmpty);
      await tapAndSettle(tester, find.byTooltip(it.revoke).first);
      await tapAndSettle(tester, find.text(it.confirm));
      expect(find.text(it.shareRevoked), findsOneWidget);
    });

    testWidgets('no viewers, failing lists, remove the tracker', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/shares', (_) => [])
        ..on('GET', '/api/devices/1', (_) => {...ownerDevice(registered: false), 'model': '', 'firmware': ''})
        ..on('DELETE', '/api/devices/1', (_) => {'ok': true});
      await openDevice(tester, backend, '/devices/1?tab=4');
      expect(find.text(it.neverConnected), findsOneWidget);
      await reveal(tester, find.text(it.noShares));
      await tapAndSettle(tester, find.text(it.removeTracker));
      await tapAndSettle(tester, find.text(it.confirm));
      expect(find.byType(DevicesScreen), findsOneWidget);
    });

    testWidgets('shares that cannot be loaded', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1/shares', (_) => Reply.error(403, 'owner_only'));
      await openDevice(tester, backend, '/devices/1?tab=4');
      await reveal(tester, find.text(it.errOwnerOnly));
    });
  });
}
