import 'dart:convert';

import 'package:car_tracking/screens/device/device_screen.dart';
import 'package:car_tracking/screens/map_overview.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Trackers installed in vehicles: paired in a vehicle of the user, moved to another
// vehicle, removed; archived vehicles

void main() {
  testWidgets('paired in a vehicle of the user, or in a new one', (tester) async {
    final backend = fullBackend()
      ..on('GET', '/api/devices', (_) => [ownerDevice(), {...vehicleDevice(), 'archived': true}])
      ..on('POST', '/api/devices/claim/check', (_) => {'available': true, 'registered': true})
      ..on('POST', '/api/devices/claim', (_) => {'id': 4, 'registered': true})
      ..on('GET', '/api/devices/4', (_) => {...vehicleDevice(), 'kind': 'tracker', 'imei': '863820040182648'});
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/add');
    await settle(tester);
    await tester.enterText(find.byKey(const Key('imei')), '863820040182648');
    await tester.enterText(find.byKey(const Key('pairing')), '6MDF-SV3C');
    await tapAndSettle(tester, find.text(it.verify));

    // The vehicles of the user without a tracker, archived ones too
    expect(find.text(it.pairInHint), findsOneWidget);
    expect(find.text('Punto · ${it.archived}'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('pairIn_4')));
    expect(find.byKey(const Key('name')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('pairNew')));
    expect(find.byKey(const Key('name')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('pairIn_4')));
    await tapAndSettle(tester, find.text(it.addToAccount));
    expect(backend.lastBody('/api/devices/claim'), {'imei': '863820040182648', 'code': '6MDF-SV3C', 'vehicleId': 4});
    expect(find.text(it.trackerConnected), findsOneWidget);
  });

  testWidgets('tracker moved to another vehicle, removed; installations', (tester) async {
    final backend = fullBackend()
      ..on('GET', '/api/devices', (_) => [ownerDevice(), vehicleDevice()])
      ..on('GET', '/api/devices/1', (_) => {
            ...ownerDevice(),
            'installations': [
              {'imei': '863820040182648', 'installedAt': iso(ago(const Duration(days: 30))), 'removedAt': null},
              {'imei': '863820040182600', 'installedAt': iso(ago(const Duration(days: 300))), 'removedAt': iso(ago(const Duration(days: 30)))},
            ],
          })
      ..on('GET', '/api/devices/4', (_) => vehicleDevice())
      ..on('GET', '/api/devices/1/shares', (_) => [])
      ..on('GET', '/api/devices/4/shares', (_) => [])
      ..on('POST', '/api/devices/1/tracker/move', (_) => Reply.error(400, 'vehicle_has_tracker'))
      ..on('DELETE', '/api/devices/1/tracker', (_) => {'ok': true});
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1?tab=4');
    await settle(tester);

    await reveal(tester, find.byKey(const Key('detachTracker')));
    expect(find.textContaining('863820040182600'), findsOneWidget);
    expect(find.byKey(const Key('archive')), findsNothing);

    // Moved: to a vehicle of the user, or to a new one
    await tapAndSettle(tester, find.byKey(const Key('moveTracker')));
    expect(find.text(it.moveTrackerTitle), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('moveConfirm')));
    expect(find.text(it.errVehicleHasTracker), findsOneWidget);
    expect(backend.lastBody('/api/devices/1/tracker/move'), {'vehicleId': 4, 'archive': true});

    await tapAndSettle(tester, find.byKey(const Key('moveTracker')));
    await tapAndSettle(tester, find.byKey(const Key('moveTarget')));
    await tapAndSettle(tester, find.text(it.pairNewVehicle).last);
    await tapAndSettle(tester, find.byKey(const Key('moveArchive')));
    await tapAndSettle(tester, find.byKey(const Key('moveConfirm')));
    expect(backend.calls('/api/devices/1/tracker/move'), hasLength(1));
    await tester.enterText(find.byKey(const Key('moveName')), 'Ypsilon');
    await settle(tester);
    backend.on('POST', '/api/devices/1/tracker/move', (_) => {'id': 4});
    await tapAndSettle(tester, find.byKey(const Key('moveConfirm')));
    await settle(tester);
    expect(backend.lastBody('/api/devices/1/tracker/move'), {'vehicle': {'name': 'Ypsilon'}, 'archive': false});
    expect(find.text(it.trackerMoved('Ypsilon')), findsOneWidget);
    expect(find.byType(DeviceScreen), findsOneWidget);

    // Removed: the vehicle stays
    app.go(tester, '/devices/1?tab=4');
    await settle(tester);
    await reveal(tester, find.byKey(const Key('detachTracker')));
    await tapAndSettle(tester, find.byKey(const Key('detachTracker')));
    expect(find.text(it.detachTrackerBody), findsOneWidget);
    await tapAndSettle(tester, find.text(it.confirm));
    expect(backend.calls('/api/devices/1/tracker', 'DELETE'), hasLength(1));
    expect(find.text(it.trackerDetached), findsOneWidget);
  });

  testWidgets('archived vehicles: in the list, last, not on the map; archived from the settings', (tester) async {
    var archived = true;
    final backend = fullBackend()
      ..on('GET', '/api/devices', (_) => [{...vehicleDevice(), 'archived': archived}, ownerDevice()])
      ..on('GET', '/api/devices/4', (_) => {...vehicleDevice(), 'archived': archived})
      ..on('GET', '/api/devices/4/shares', (_) => [])
      ..on('PATCH', '/api/devices/4', (request) {
        archived = (jsonDecode(request.body) as Map<String, dynamic>)['archived'] as bool;
        return {'ok': true};
      });
    final app = TestApp(backend);
    await app.start(tester);
    expect(find.byType(MapOverviewScreen), findsOneWidget);
    expect(find.byType(DeviceMarker), findsOneWidget);

    app.go(tester, '/devices');
    await settle(tester);
    expect(find.textContaining(it.archived), findsOneWidget);
    expect(tester.getTopLeft(find.text('Panda')).dy, lessThan(tester.getTopLeft(find.text('Punto')).dy));

    app.go(tester, '/devices/4?tab=4');
    await settle(tester);
    await reveal(tester, find.byKey(const Key('archive')));
    await tapAndSettle(tester, find.byKey(const Key('archive')));
    expect(backend.lastBody('/api/devices/4', 'PATCH'), {'archived': false});
    await settle(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('archive'))).value, isFalse);
  });
}
