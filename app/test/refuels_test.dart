import 'dart:convert';

import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/screens/device/refuels_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Refuels of a vehicle: real consumption, prices for the costs of the trips

Map<String, dynamic> refuelJson(int id, String day, num litres,
        {num? cost, int? odometerKm, bool full = true, num? consumption, int? km, String note = ''}) =>
    {
      'id': id,
      'day': day,
      'litres': litres,
      'cost': cost,
      'odometerKm': odometerKm,
      'full': full,
      'note': note,
      'pricePerLitre': cost == null ? null : cost / litres,
      'km': km,
      'consumption': consumption,
      'since': null,
    };

/// Refuels of the tracker 1, kept by the fake backend
FakeBackend refuelsBackend({List<Map<String, dynamic>>? initial, String unit = 'l_per_100km', bool fromRefuels = true}) {
  final refuels = initial ??
      [
        refuelJson(2, '2026-11-15', 40, cost: 76, odometerKm: 21000, consumption: 6.5, km: 615, note: 'Autostrada'),
        refuelJson(1, '2026-10-20', 12, odometerKm: 20385, full: false),
      ];
  Map<String, dynamic> state() => {
        'refuels': refuels,
        'summary': {
          'count': refuels.length,
          'litres': refuels.fold<num>(0, (sum, item) => sum + (item['litres'] as num)),
          'cost': refuels.any((item) => item['cost'] != null) ? 76 : null,
          'averageConsumption': refuels.any((item) => item['consumption'] != null) ? 6.5 : null,
          'lastConsumption': refuels.any((item) => item['consumption'] != null) ? 6.5 : null,
          'measuredKm': 615,
        },
        'ratesFromRefuels': fromRefuels,
        'fuelUnit': unit,
        'odometerKm': 21480,
      };
  return fullBackend()
    ..on('GET', '/api/devices/1/refuels', (_) => state())
    ..on('POST', '/api/devices/1/refuels', (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      refuels.insert(0, refuelJson(9, body['day'] as String, body['litres'] as num, cost: body['cost'] as num?, odometerKm: body['odometerKm'] as int?));
      return state();
    })
    ..on('PATCH', '/api/refuels/2', (_) => state())
    ..on('GET', '/api/devices/1/vehicle', (_) => {
          'model': '',
          'fuelUnit': unit,
          'fuelType': 'petrol',
          'fuelPriceAuto': true,
          'ratesFromRefuels': fromRefuels,
          'rates': {
            'price': [
              {'validFrom': '2026-11-15', 'value': 1.9, 'source': 'refuel'},
              {'validFrom': '2026-11-09', 'value': 1.95, 'source': 'auto'},
            ],
            'consumption': [],
            'wear': [],
          },
          'current': {'price': 1.9, 'consumption': null, 'wear': null},
          'costPerKm': null,
          'average': null,
        })
    ..on('PUT', '/api/devices/1/vehicle', (_) => Reply.error(403, 'owner_only'))
    ..on('DELETE', '/api/refuels/1', (_) {
      refuels.removeWhere((item) => item['id'] == 1);
      return state();
    });
}

void main() {
  test('consumption in the unit of the owner', () {
    expect(consumptionText(5, 'l_per_100km'), contains('l/100 km'));
    expect(consumptionText(5, 'km_per_l'), '${formatDecimal(20, 1)} km/l');
  });

  testWidgets('refuels: list, real consumption, added, changed, deleted, errors', (tester) async {
    final backend = refuelsBackend();
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1?tab=2');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('openRefuels')));

    expect(find.text(it.realConsumption(consumptionText(6.5, 'l_per_100km'))), findsOneWidget);
    expect(find.textContaining(it.refuelMeasured(consumptionText(6.5, 'l_per_100km'), formatInt(615))), findsOneWidget);
    expect(find.textContaining(it.refuelPartial), findsOneWidget);
    expect(find.textContaining('Autostrada'), findsOneWidget);
    expect(find.text(it.refuelRatesOn), findsOneWidget);

    // New refuel: the odometer of today proposed, the price per litre shown, invalid values refused
    await tapAndSettle(tester, find.byKey(const Key('addRefuel')));
    expect(find.text('21480'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('refuelLitres')), '0');
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(find.text(it.refuelInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('refuelLitres')), '42,5');
    await tester.enterText(find.byKey(const Key('refuelCost')), '80');
    await settle(tester);
    expect(find.text('${formatEuro(80 / 42.5, digits: 3)}/l'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('refuelOdometer')), '21.500');
    await tapAndSettle(tester, find.byKey(const Key('refuelFull')));
    await tester.enterText(find.byKey(const Key('refuelNote')), ' Self ');
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    final body = backend.lastBody('/api/devices/1/refuels', 'POST');
    expect((body['litres'], body['cost'], body['odometerKm'], body['full'], body['note']), (42.5, 80, 21500, false, 'Self'));
    expect(body['day'], isA<String>());
    expect(find.text(it.refuelSaved), findsOneWidget);
    expect(find.byKey(const Key('refuel_9')), findsOneWidget);

    // Changed: the values of the refuel in the dialog; the date picker opens and closes
    await clearSnackbars(tester);
    await tester.ensureVisible(find.byKey(const Key('refuel_2')));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const Key('refuel_2')));
    expect(find.text(it.editRefuel), findsOneWidget);
    expect(find.text('Autostrada'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('refuelDate')));
    await tapAndSettle(tester, find.text('OK'));
    await tester.enterText(find.byKey(const Key('refuelCost')), '');
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(backend.lastBody('/api/refuels/2', 'PATCH')['cost'], isNull);

    // Deleted, then an error of the backend; cancelled
    await clearSnackbars(tester);
    await reveal(tester, find.byKey(const Key('refuel_1')));
    await tester.ensureVisible(find.byKey(const Key('refuel_1')));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const Key('refuel_1')));
    await tapAndSettle(tester, find.byKey(const Key('refuelDelete')));
    expect(find.byKey(const Key('refuel_1')), findsNothing);
    backend.on('PATCH', '/api/refuels/2', (_) => Reply.error(400, 'refuel_future'));
    await tapAndSettle(tester, find.byKey(const Key('refuel_2')));
    await tapAndSettle(tester, find.byKey(const Key('refuelSave')));
    expect(find.text(it.errRefuelFuture), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('refuel_2')));
    await tapAndSettle(tester, find.text(it.cancel));
    expect(backend.calls('/api/refuels/2', 'PATCH'), hasLength(2));

    // The costs from the line of the option: the values of the refuels can't be deleted
    await tapAndSettle(tester, find.descendant(of: find.byKey(const Key('refuelRates')), matching: find.text(it.tripCosts)));
    for (final key in ['ratesFromRefuels', 'vehicleSave']) {
      await reveal(tester, find.byKey(Key(key)));
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(Key(key)));
    }
    expect(backend.lastBody('/api/devices/1/vehicle', 'PUT')['ratesFromRefuels'], false);
    await reveal(tester, find.textContaining(it.rateFromAverage));
    expect(find.textContaining(it.rateFromRefuel), findsOneWidget);
    expect(find.byKey(const Key('delete_price_2026-11-15')), findsNothing);
    expect(find.byKey(const Key('delete_price_2026-11-09')), findsOneWidget);
  });

  testWidgets('refuels: none yet, km/l, not used for the costs, not loaded', (tester) async {
    final backend = refuelsBackend(initial: [], unit: 'km_per_l', fromRefuels: false);
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1/refuels');
    await settle(tester);
    expect(find.byKey(const Key('noRefuels')), findsOneWidget);
    expect(find.text(it.realConsumptionUnknown), findsOneWidget);
    expect(find.text(it.refuelRatesOff), findsOneWidget);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await settle(tester);

    backend.on('GET', '/api/devices/1/refuels', (_) => Reply.error(400, 'not_a_vehicle'));
    app.go(tester, '/devices/1');
    await settle(tester);
    app.go(tester, '/devices/1/refuels');
    await settle(tester);
    expect(find.text(it.errGeneric(400)), findsOneWidget);
  });
}
