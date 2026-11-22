// Screenshots of the main screens with the data of the tests, to check the interface by
// eye (real fonts, phone and desktop browser sizes, light and dark theme). Not part of
// `flutter test`:
//   flutter test screenshots --update-goldens   ->   screenshots/out/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_tracking/screens/dashboards/catalog.dart';

import '../test/dashboards_test.dart' show dashboardBackend, dashboardJson, fakeResult;
import '../test/device_test.dart' show analysisBackend;
import '../test/support.dart';
import '../test/vehicle_test.dart' show deadline, trendsJson;

const phone = Size(412, 892);
const tall = Size(412, 1700);

/// Browser on a desktop: navigation rail instead of the bottom bar
const desktop = Size(1280, 800);

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async => ByteData.view(Uint8List.fromList(await File('$dir/$name').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(font('Roboto-$weight.ttf'));
  }
  await roboto.load();
  // The font of the theme, bundled with the app
  final barlow = FontLoader('Barlow');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    barlow.addFont(File('assets/fonts/Barlow-$weight.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await barlow.load();
  await (FontLoader('MaterialIcons')..addFont(font('MaterialIcons-Regular.otf'))).load();
}

/// Backend with data on every page of the car
FakeBackend demoBackend() {
  final hour = DateTime.now().subtract(const Duration(hours: 3));
  Map<String, dynamic> trip(int minutes, double km, String? purpose, String note, double cost) => {
        'start': iso(hour.add(Duration(minutes: minutes))),
        'end': iso(hour.add(Duration(minutes: minutes + 25))),
        'distanceKm': km,
        'durationMin': 25,
        'avgSpeed': 42,
        'maxSpeed': 96,
        'purpose': purpose,
        'note': note,
        'cost': {'fuelL': km * 0.05, 'fuelCost': km * 0.09, 'wearCost': km * 0.1, 'cost': cost},
      };
  final b = analysisBackend()
    ..on('GET', '/api/devices', (_) => _devices())
    ..on('GET', '/api/devices/1/trips', (_) => {
          'totals': {
            'distanceKm': 48.6,
            'drivingMin': 95,
            'maxSpeed': 118,
            'trips': 3,
            'cost': {'fuelL': 2.43, 'fuelCost': 4.37, 'wearCost': 4.86, 'cost': 9.23},
          },
          'days': [
            {'day': '2026-11-19', 'distanceKm': 12.0, 'drivingMin': 25},
            {'day': '2026-11-20', 'distanceKm': 22.4, 'drivingMin': 45},
            {'day': '2026-11-21', 'distanceKm': 14.2, 'drivingMin': 25},
          ],
          'trips': [
            trip(0, 12.0, 'business', 'Cliente Rossi', 2.28),
            trip(60, 22.4, 'personal', '', 4.26),
            trip(120, 14.2, null, '', 2.70),
          ],
        })
    ..on('GET', '/api/devices/1/trends', (_) => trendsJson('fair', average: 12.31, trend: -0.05))
    ..on('GET', '/api/devices/1/maintenance', (_) => {
          'odometerKm': 48250,
          'items': [
            deadline(1, 'inspection', 'due', title: 'Revisione 2026', dueDate: '2026-11-20', days: -2),
            deadline(2, 'service', 'soon', dueKm: 48900, km: 650, everyKm: 15000, everyMonths: 24),
            deadline(3, 'other', 'ok', title: 'Bollino blu', dueDate: '2027-05-10', days: 169, everyMonths: 12),
            deadline(4, 'insurance', 'ok', dueDate: '2027-03-01', days: 99, everyMonths: 12),
          ],
          'log': [
            {'id': 1, 'kind': 'tyres', 'title': '', 'doneOn': '2026-10-28', 'km': 47100, 'note': 'Invernali'},
          ],
        })
    ..on('GET', '/api/devices/1/vehicle', (_) => {
          'model': 'Fiat Panda 1.2 benzina',
          'fuelUnit': 'l_per_100km',
          'fuelType': 'petrol',
          'fuelPriceAuto': true,
          'rates': {
            'price': [
              {'validFrom': '2026-11-16', 'value': 1.97},
              {'validFrom': '2026-10-01', 'value': 1.762},
              {'validFrom': '2026-08-20', 'value': 1.905},
            ],
            'consumption': [
              {'validFrom': '2026-09-01', 'value': 5.9},
              {'validFrom': '2026-03-01', 'value': 5.6},
            ],
            'wear': [
              {'validFrom': '2026-01-01', 'value': 0.11},
            ],
          },
          'current': {'price': 1.97, 'consumption': 5.9, 'wear': 0.11},
          'costPerKm': 0.226,
          'average': {'week': '2026-11-16', 'price': 1.97},
        })
    ..on('GET', '/api/devices/1/extra', (_) => {
          'latest': [
            {'key': 'coolant', 'value': 88.5, 'time': iso(ago(const Duration(minutes: 2)))},
            {'key': 'fuelLevel', 'value': 41, 'time': iso(ago(const Duration(minutes: 2)))},
            {'key': 'rpm', 'value': 820, 'time': iso(ago(const Duration(minutes: 2)))},
          ],
          'items': [
            {'time': iso(ago(const Duration(minutes: 2))), 'data': {'rpm': 820, 'coolant': 88.5, 'fuelLevel': 41}},
            {'time': iso(ago(const Duration(minutes: 7))), 'data': {'rpm': 0, 'coolant': 61.0}},
          ],
        })
    ..on('GET', '/api/admin/backup', (_) => {
          'configured': true,
          'stale': false,
          'files': 17,
          'totalBytes': 48 * 1024 * 1024,
          'latest': {'size': 3 * 1024 * 1024},
          'lastSuccess': iso(ago(const Duration(hours: 5))),
          'lastOffsite': iso(ago(const Duration(hours: 4))),
        })
    ..on('GET', '/api/admin/users', (_) => [
          {'id': 1, 'name': 'Anna', 'email': 'anna@example.com', 'isAdmin': true, 'devices': 1, 'passkeys': 2, 'totpEnabled': true, 'lastLoginAt': iso(ago(const Duration(minutes: 3)))},
          {'id': 2, 'name': 'Mario', 'email': 'mario@example.com', 'isAdmin': false, 'devices': 2, 'passkeys': 0, 'totpEnabled': false, 'disabled': false},
        ])
    ..on('GET', '/api/admin/invites', (_) => [])
    ..on('GET', '/api/admin/firmware', (_) => []);
  // Account page
  Map<String, dynamic> session(int id, String agent, String client, {bool current = false}) =>
      {'id': id, 'client': client, 'user_agent': agent, 'ip': '10.0.0.$id', 'last_seen_at': iso(ago(Duration(minutes: id))), 'current': current};
  // Pairing of a tracker; installations of the car
  b
    ..on('POST', '/api/devices/claim/check', (_) => {'available': true, 'registered': false})
    ..on('GET', '/api/devices/1', (_) => {
          ...ownerDevice(),
          'installations': [
            {'imei': '863820040182648', 'installedAt': iso(ago(const Duration(days: 30))), 'removedAt': null},
          ],
        });
  b.on('GET', '/api/account', (_) => {
        'passkeys': [
          {'id': 'pk1', 'name': 'Pixel 9', 'created_at': iso(ago(const Duration(days: 3))), 'last_used_at': iso(ago(const Duration(hours: 2))), 'backed_up': true},
        ],
        'sessions': [
          session(1, 'Mozilla/5.0 (X11; Linux) Chrome/130', 'web', current: true),
          session(2, 'Mozilla/5.0 (Linux; Android 15)', 'app'),
        ],
        'recoveryCodesLeft': 8,
        'pushEnabled': true,
      });
  return b;
}

List<Map<String, dynamic>> _devices() => [
      {...ownerDevice(), 'lastPosition': positionJson(age: const Duration(minutes: 1), lat: 45.07)},
      {...viewerDevice(), 'lastSeenAt': iso(ago(const Duration(hours: 1))), 'lastPosition': positionJson(status: 1, lat: 45.2, full: false)},
      phoneDevice(),
      {...phoneDevice(id: 4, owner: false, connected: false), 'name': 'iPhone Mario', 'lastPosition': {...positionJson(lat: 45.3, full: false), 'accuracy': 30}},
      {...vehicleDevice(id: 5), 'name': 'Punto (venduta)', 'archived': true},
    ];

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  // The root overlay: pages and dialogs
  await expectLater(find.byType(Overlay).first, matchesGoldenFile('out/$name.png'));
  // Checked by the framework at the end of the test, before the tear downs
  debugDisableShadows = true;
}

Future<TestApp> open(WidgetTester tester, String location, {Size size = phone, bool dark = false, FakeBackend? backend}) async {
  debugDisableShadows = false;
  tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final app = TestApp(backend ?? demoBackend());
  await app.start(tester, size: size);
  if (location != '/') {
    app.go(tester, location);
    await settle(tester, 20);
  }
  return app;
}

void main() {
  setUpAll(() async {
    await initFormats();
    await loadFonts();
  });

  testWidgets('01 map', (tester) async {
    await open(tester, '/');
    await shot(tester, '01_map');
  });
  testWidgets('02 devices', (tester) async {
    await open(tester, '/devices');
    await shot(tester, '02_devices');
  });
  testWidgets('03 live', (tester) async {
    await open(tester, '/devices/1');
    await shot(tester, '03_live');
  });
  testWidgets('04 history', (tester) async {
    await open(tester, '/devices/1?tab=1');
    await shot(tester, '04_history');
  });
  testWidgets('05 analysis', (tester) async {
    await open(tester, '/devices/1?tab=2', size: tall);
    await shot(tester, '05_analysis');
  });
  testWidgets('06 trips', (tester) async {
    await open(tester, '/devices/1?tab=2', size: tall);
    await tapAndSettle(tester, find.byIcon(Icons.list));
    await shot(tester, '06_trips');
  });
  testWidgets('07 trends', (tester) async {
    await open(tester, '/devices/1/trends', size: tall);
    await shot(tester, '07_trends');
  });
  testWidgets('08 maintenance', (tester) async {
    await open(tester, '/devices/1/maintenance');
    await shot(tester, '08_maintenance');
  });
  testWidgets('09 deadline editor', (tester) async {
    await open(tester, '/devices/1/maintenance');
    await tapAndSettle(tester, find.byKey(const Key('deadline3')));
    await shot(tester, '09_deadline_editor');
  });
  testWidgets('10 costs', (tester) async {
    await open(tester, '/devices/1/costs', size: tall);
    await shot(tester, '10_costs');
  });
  testWidgets('11 fuel price dialog', (tester) async {
    await open(tester, '/devices/1/costs');
    await reveal(tester, find.byKey(const Key('add_price')));
    await tapAndSettle(tester, find.byKey(const Key('add_price')));
    await shot(tester, '11_fuel_price');
  });
  testWidgets('22 extra data', (tester) async {
    await open(tester, '/devices/1/extra');
    await shot(tester, '22_extra');
  });
  testWidgets('12 areas', (tester) async {
    await open(tester, '/devices/1?tab=3');
    await shot(tester, '12_areas');
  });
  testWidgets('13 settings', (tester) async {
    await open(tester, '/devices/1?tab=4', size: tall);
    await shot(tester, '13_settings');
  });
  testWidgets('14 notifications', (tester) async {
    await open(tester, '/notifications');
    await shot(tester, '14_notifications');
  });
  testWidgets('15 account', (tester) async {
    await open(tester, '/account', size: tall);
    await shot(tester, '15_account');
  });
  testWidgets('16 admin', (tester) async {
    await open(tester, '/account/admin');
    await shot(tester, '16_admin');
  });
  testWidgets('17 shared device', (tester) async {
    await open(tester, '/devices/2');
    await shot(tester, '17_shared');
  });
  testWidgets('18 login', (tester) async {
    final backend = fullBackend()..on('GET', '/api/auth/session', (_) => {'stage': 'none', 'user': userJson()});
    await open(tester, '/', backend: backend);
    await shot(tester, '18_login');
  });
  testWidgets('19 dark live', (tester) async {
    await open(tester, '/devices/1', dark: true);
    await shot(tester, '19_dark_live');
  });
  testWidgets('20 dark costs', (tester) async {
    await open(tester, '/devices/1/costs', dark: true, size: tall);
    await shot(tester, '20_dark_costs');
  });
  testWidgets('21 dark trends', (tester) async {
    await open(tester, '/devices/1/trends', dark: true, size: tall);
    await shot(tester, '21_dark_trends');
  });
  testWidgets('23 pairing in a vehicle', (tester) async {
    await open(tester, '/devices/add');
    await pairingVehicleStep(tester);
    await shot(tester, '23_pairing_vehicle');
  });
  testWidgets('24 tracker moved', (tester) async {
    await open(tester, '/devices/1?tab=4');
    await reveal(tester, find.byKey(const Key('moveTracker')));
    await tapAndSettle(tester, find.byKey(const Key('moveTracker')));
    await shot(tester, '24_move_tracker');
  });

  testWidgets('25 dashboard', (tester) async {
    await open(tester, '/dashboards', size: tall, backend: _dashboards());
    await shot(tester, '25_dashboard');
  });
  testWidgets('26 dashboard edit', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards());
    await tapAndSettle(tester, find.byKey(const Key('dashboardEdit')));
    await shot(tester, '26_dashboard_edit');
  });
  testWidgets('27 widget editor', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards());
    await tapAndSettle(tester, find.byKey(const Key('dashboardEdit')));
    await tapAndSettle(tester, find.text(it.mDistance).first);
    await shot(tester, '27_widget_editor');
  });
  testWidgets('28 dashboard received', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards(current: true, received: true));
    await shot(tester, '28_dashboard_received');
  });
  testWidgets('29 dashboard menu', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards(current: true));
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await shot(tester, '29_dashboard_menu');
  });
  testWidgets('30 dashboard share', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards());
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardShare));
    await shot(tester, '30_dashboard_share');
  });
  testWidgets('31 dashboard use', (tester) async {
    await open(tester, '/dashboards', backend: _dashboards(received: true));
    await tapAndSettle(tester, find.byKey(const Key('use_30')));
    await tapAndSettle(tester, find.byKey(const Key('useAll')));
    await tapAndSettle(tester, find.byKey(const Key('use_device_1')));
    await shot(tester, '31_dashboard_use');
  });
  testWidgets('32 analysis with the current dashboard', (tester) async {
    await open(tester, '/devices/1?tab=2', size: tall, backend: _dashboards(current: true, kind: 'diagnostics'));
    await shot(tester, '32_analysis_dashboard');
  });

  // Desktop browser
  final pages = {
    'map': '/',
    'devices': '/devices',
    'live': '/devices/1',
    'analysis': '/devices/1?tab=2',
    'maintenance': '/devices/1/maintenance',
    'costs': '/devices/1/costs',
    'settings': '/devices/1?tab=4',
    'account': '/account',
    'admin': '/account/admin',
  };
  for (final (index, MapEntry(key: name, value: location)) in pages.entries.indexed) {
    testWidgets('desktop $name', (tester) async {
      await open(tester, location, size: desktop);
      await shot(tester, 'd${(index + 1).toString().padLeft(2, '0')}_$name');
    });
  }
  testWidgets('desktop deadline editor', (tester) async {
    await open(tester, '/devices/1/maintenance', size: desktop);
    await tapAndSettle(tester, find.byKey(const Key('deadline3')));
    await shot(tester, 'd10_deadline_editor');
  });
  testWidgets('desktop pairing', (tester) async {
    await open(tester, '/devices/add', size: desktop);
    await pairingVehicleStep(tester);
    await shot(tester, 'd11_pairing_vehicle');
  });
  testWidgets('desktop dark live', (tester) async {
    await open(tester, '/devices/1', size: desktop, dark: true);
    await shot(tester, 'd12_dark_live');
  });
  testWidgets('desktop dashboard', (tester) async {
    await open(tester, '/dashboards', size: desktop, backend: _dashboards());
    await shot(tester, 'd14_dashboard');
  });
  testWidgets('desktop dark dashboard', (tester) async {
    await open(tester, '/dashboards', size: desktop, dark: true, backend: _dashboards());
    await shot(tester, 'd15_dark_dashboard');
  });
  testWidgets('desktop analysis with the current dashboard', (tester) async {
    await open(tester, '/devices/1?tab=2', size: desktop, backend: _dashboards(current: true));
    await shot(tester, 'd16_analysis_dashboard');
  });
  testWidgets('desktop dark dashboard received', (tester) async {
    await open(tester, '/dashboards', size: desktop, dark: true, backend: _dashboards(current: true, received: true));
    await shot(tester, 'd17_dark_dashboard_received');
  });
  testWidgets('desktop dark settings', (tester) async {
    await open(tester, '/devices/1?tab=4', size: desktop, dark: true);
    await shot(tester, 'd13_dark_settings');
  });
}

/// Label checked: the step of the vehicle
Future<void> pairingVehicleStep(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('imei')), '863820040182648');
  await tester.enterText(find.byKey(const Key('pairing')), '6MDF-SV3C');
  await tapAndSettle(tester, find.text(it.verify));
}

/// A dashboard of a template with the values of the tests (the current one), and a
/// dashboard received from a friend
FakeBackend _dashboards({bool current = false, bool received = false, String kind = 'overview'}) =>
    dashboardBackend(
      initial: [
        {...dashboardJson(1, 'Famiglia', [for (final widget in template(kind)) widget.toJson()]), 'current': current},
      ],
      result: _onlyChosen,
    )
      ..on('GET', '/api/dashboards/shares', (_) => [
            if (received)
              {
                'id': 30,
                'from': 'Luca',
                'name': 'Flotta aziendale',
                'layout': Dashboard.layout('30d', template('diagnostics')),
                'createdAt': iso(DateTime.now()),
              },
          ]);

/// Values of the test, only of the vehicles of the widget when it has some (the analysis
/// of a vehicle)
Map<String, dynamic> _onlyChosen(Map<String, dynamic> widget) {
  final result = fakeResult(widget);
  final chosen = widget['devices'];
  if (chosen is! List) return result;
  bool keep(Object? item) => chosen.contains((item as Map)['deviceId'] ?? item['id']);
  return {
    for (final MapEntry(:key, :value) in result.entries)
      key: key == 'devices' || key == 'values' || key == 'series' || key == 'items' ? (value as List).where(keep).toList() : value,
  };
}
