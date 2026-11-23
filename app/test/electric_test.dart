import 'dart:convert';

import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/screens/device/refuels_screen.dart';
import 'package:car_tracking/screens/summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'vehicle_test.dart' show deadline;

// Electric vehicles (charges in kWh at home or at a station, price per kWh, no national
// average), the mileage allowance of the business km, the day expected for the deadlines by km
// and the alerts of new errors for the administrators

/// Electric car 1: profile and charges kept by the fake backend
FakeBackend electricBackend() {
  final rates = <String, List<Map<String, dynamic>>>{
    'price': [
      {'validFrom': '2026-11-10', 'value': 0.5, 'source': 'refuel'},
    ],
    'consumption': [],
    'wear': [],
    'reimbursement': [],
  };
  final charges = <Map<String, dynamic>>[
    {
      'id': 2, 'day': '2026-11-15', 'litres': 32, 'cost': 16, 'odometerKm': 1200, 'full': true, 'place': 'public', 'note': '',
      'pricePerLitre': 0.5, 'km': 200, 'consumption': 16, 'since': '2026-11-10',
    },
    {
      'id': 1, 'day': '2026-11-10', 'litres': 40, 'cost': 10, 'odometerKm': 1000, 'full': false, 'place': 'home', 'note': '',
      'pricePerLitre': 0.25, 'km': null, 'consumption': null, 'since': null,
    },
  ];
  Map<String, dynamic> profile() => {
        'model': 'Zoe',
        'fuelUnit': 'l_per_100km',
        'fuelType': 'electric',
        'energyUnit': 'kWh',
        'fuelPriceAuto': false,
        'ratesFromRefuels': true,
        'rates': rates,
        'current': {
          'price': 0.5,
          'consumption': null,
          'wear': null,
          'reimbursement': rates['reimbursement']!.isEmpty ? null : rates['reimbursement']!.first['value'],
        },
        'costPerKm': null,
        'average': null,
      };
  Map<String, dynamic> state() => {
        'refuels': charges,
        'summary': {'count': charges.length, 'litres': 72, 'cost': 26, 'averageConsumption': 16, 'lastConsumption': 16, 'measuredKm': 200},
        'ratesFromRefuels': true,
        'fuelUnit': 'l_per_100km',
        'energyUnit': 'kWh',
        'odometerKm': 1250,
      };
  return fullBackend()
    ..on('GET', '/api/devices/1/refuels', (_) => state())
    ..on('POST', '/api/devices/1/refuels', (_) => state())
    ..on('PATCH', '/api/refuels/1', (_) => state())
    ..on('GET', '/api/devices/1/vehicle', (_) => profile())
    ..on('PUT', '/api/devices/1/vehicle', (_) => profile())
    ..on('POST', '/api/devices/1/rates', (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      rates[body['kind'] as String] = [
        {'validFrom': body['validFrom'], 'value': body['value'], 'source': 'manual'},
        ...rates[body['kind']]!,
      ];
      return profile();
    });
}

void main() {
  setUpAll(initFormats);

  test('consumption of the electric ones', () {
    expect(consumptionText(16, 'l_per_100km', 'kWh'), '${formatDecimal(16, 1)} kWh/100 km');
    expect(consumptionText(16, 'km_per_l', 'kWh'), '${formatDecimal(6.25, 1)} km/kWh');
    expect(remainingText(en, null, 900, '2026-12-04'), '${en.inKm('900')} (${en.expectedAround('4 December')})');
  });

  testWidgets('charges of an electric car: kWh, place, price per kWh', (tester) async {
    final backend = electricBackend();
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1/refuels');
    await settle(tester);
    expect(find.text(it.charges), findsOneWidget);
    expect(find.text(it.realConsumption(consumptionText(16, 'l_per_100km', 'kWh'))), findsOneWidget);
    expect(find.textContaining(it.lastCharge('')), findsOneWidget);
    expect(find.textContaining(it.chargeTotals(2, '72 kWh', formatEuro(26))), findsOneWidget);
    expect(find.textContaining(it.chargePublic), findsOneWidget);
    expect(find.textContaining('${formatEuro(0.5, digits: 3)}/kWh'), findsOneWidget);
    expect(find.textContaining(it.chargePartial), findsOneWidget);

    // New charge at home
    await tapAndSettle(tester, find.text(it.addCharge));
    expect(find.text(it.chargeEnergy), findsOneWidget);
    await tester.enterText(find.byKey(const Key('refuelLitres')), '0');
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(find.text(it.chargeInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('refuelLitres')), '30');
    await tester.enterText(find.byKey(const Key('refuelCost')), '9');
    await settle(tester);
    expect(find.text('${formatEuro(0.3, digits: 3)}/kWh'), findsOneWidget);
    await tapAndSettle(tester, find.text(it.chargeHome));
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(backend.lastBody('/api/devices/1/refuels', 'POST')['place'], 'home');

    // Changed: the place cleared
    await clearSnackbars(tester);
    await reveal(tester, find.byKey(const Key('refuel_1')));
    await tester.ensureVisible(find.byKey(const Key('refuel_1')));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const Key('refuel_1')));
    expect(find.text(it.editCharge), findsOneWidget);
    await tapAndSettle(tester, find.text(it.chargePlaceUnset));
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(backend.lastBody('/api/refuels/1', 'PATCH')['place'], isNull);
  });

  testWidgets('costs of an electric car: price per kWh, no national average, mileage allowance', (tester) async {
    final backend = electricBackend();
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1/costs');
    await settle(tester);
    Future<void> show(Finder finder) async {
      await reveal(tester, finder);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    expect(find.text(it.nationalAverageNone), findsOneWidget);
    expect(find.text('kWh/100 km'), findsOneWidget);
    await show(find.byKey(const Key('ratesFromRefuels')));
    expect(find.text(it.chargeRatesFrom), findsOneWidget);
    await show(find.byKey(const Key('vehicleSave')));
    await tapAndSettle(tester, find.byKey(const Key('vehicleSave')));
    expect(backend.lastBody('/api/devices/1/vehicle', 'PUT')['fuelPriceAuto'], false);

    await show(find.text(it.energyPrices));
    expect(find.text(it.rateNow('${formatEuro(0.5, digits: 3)}/kWh')), findsOneWidget);

    // The allowance per km of the business trips
    await clearSnackbars(tester);
    await show(find.byKey(const Key('add_reimbursement')));
    expect(find.text(it.reimbursementHint), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('add_reimbursement')));
    await tester.enterText(find.byKey(const Key('rateValue')), '11');
    await tapAndSettle(tester, find.byKey(const Key('rateSave')));
    expect(find.text(it.valueRange('0', '10')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rateValue')), '0,42');
    await tapAndSettle(tester, find.byKey(const Key('rateSave')));
    expect(backend.lastBody('/api/devices/1/rates', 'POST')['kind'], 'reimbursement');
    expect(backend.lastBody('/api/devices/1/rates', 'POST')['value'], 0.42);
    await show(find.text(it.rateNow('${formatEuro(0.42, digits: 3)}/km')));
    expect(find.text(it.rateNow('${formatEuro(0.42, digits: 3)}/km')), findsOneWidget);

    // A hybrid: the national average of petrol can be followed
    await show(find.byKey(const Key('fuelType')));
    await tapAndSettle(tester, find.byKey(const Key('fuelType')));
    await tapAndSettle(tester, find.text(it.fuelHybrid).last);
    expect(find.text(it.fuelPriceAutoHint), findsOneWidget);
  });

  testWidgets('summary: allowance, charges in kWh, deadline expected by km', (tester) async {
    final month = lastMonth();
    final backend = fullBackend()
      ..on('GET', '/api/summary/$month', (_) => {
            'month': month,
            'from': '$month-01',
            'to': '$month-28',
            'complete': true,
            'devices': [
              {
                'id': 1, 'name': 'Zoe', 'color': '#1E88E5', 'kind': 'tracker', 'distanceKm': 300, 'businessKm': 100, 'personalKm': 0,
                'drivingMin': 300, 'trips': 10, 'maxSpeed': 110, 'cost': null, 'reimbursement': 42, 'energyUnit': 'kWh',
                'refuels': {'count': 3, 'litres': 48, 'cost': null, 'consumption': 16},
                'trafficBytes': null, 'alarms': 0,
              },
            ],
            'totals': {'distanceKm': 300, 'drivingMin': 300, 'trips': 10, 'cost': null, 'refuelCost': null, 'reimbursement': 42},
            'previous': {'distanceKm': 200, 'drivingMin': 200, 'trips': 8, 'cost': null, 'refuelCost': null, 'reimbursement': 30},
            'deadlines': [
              {...deadline(1, 'service', 'soon', dueKm: 22000, km: 600), 'deviceId': 1, 'expectedDate': '2026-12-04'},
            ],
          });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/account/summary?month=$month');
    await settle(tester);
    expect(find.text(formatEuro(42)), findsOneWidget);
    expect(find.text(it.comparedToBefore('+40%')), findsOneWidget);
    expect(find.textContaining(it.summaryReimbursement(formatEuro(42))), findsOneWidget);
    expect(find.textContaining(it.summaryCharges(3, '${formatDecimal(48, 1)} kWh')), findsOneWidget);
    expect(find.textContaining('kWh/100 km'), findsOneWidget);
    await reveal(tester, find.textContaining(it.expectedAround('')));
    expect(find.textContaining(it.expectedAround('4 dicembre')), findsOneWidget);
  });

  testWidgets('deadlines: average km a day and day expected', (tester) async {
    final backend = fullBackend()
      ..on('GET', '/api/devices/1/maintenance', (_) => {
            'odometerKm': 50000,
            'kmPerDay': 42.4,
            'items': [
              {...deadline(2, 'service', 'soon', dueKm: 50600, km: 600), 'expectedDate': '2027-01-09'},
            ],
            'log': [],
          });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1/maintenance');
    await settle(tester);
    expect(find.textContaining(it.kmPerDayAverage('42')), findsOneWidget);
    expect(find.textContaining(it.expectedAround('9 gennaio')), findsOneWidget);
  });

  testWidgets('administrators: alerts of new errors in the account', (tester) async {
    final backend = fullBackend()
      ..on('GET', '/api/account', (_) => {'passkeys': [], 'sessions': [], 'recoveryCodesLeft': 10, 'monthlySummary': true, 'adminAlerts': true});
    final app = TestApp(backend);
    await app.start(tester);
    await tapAndSettle(tester, find.text(it.navAccount));
    await reveal(tester, find.byKey(const Key('adminAlerts')));
    await tapAndSettle(tester, find.byKey(const Key('adminAlerts')));
    expect(backend.lastBody('/api/account', 'PATCH'), {'adminAlerts': false});
    backend.on('PATCH', '/api/account', (_) => Reply.error(403, 'forbidden'));
    await tapAndSettle(tester, find.byKey(const Key('adminAlerts')));
    expect(find.text(it.errForbidden), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('adminAlerts'))).value, false);
  });
}
