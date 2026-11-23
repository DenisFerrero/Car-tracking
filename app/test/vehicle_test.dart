import 'dart:convert';

import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Statistics over time, health of the car battery, trip log, odometer and deadlines,
// state of the backups

Map<String, dynamic> period(String name, double km, {double business = 0, double? voltage}) => {
      'period': name,
      'distanceKm': km,
      'businessKm': business,
      'personalKm': 0,
      'drivingMin': 90,
      'trips': 3,
      'maxSpeed': 110,
      'trafficBytes': 30 * 1024 * 1024,
      'alarms': 1,
      'restVoltage': voltage,
      'days': 7,
    };

Map<String, dynamic> trendsJson(String state, {double? average = 12.05, double? trend = -0.3}) => {
      'months': [period('2026-10', 800, business: 120, voltage: 12.5), period('2026-11', 640)],
      'weeks': [period('2026-11-09', 150), period('2026-11-16', 210)],
      'simBudgetBytes': 200 * 1024 * 1024,
      'odometerKm': 50000,
      'battery': {
        'state': state,
        'average': average,
        'trendPerMonth': trend,
        'good': 12.4,
        'low': 12.2,
        'days': [
          {'day': '2026-11-18', 'restVoltage': 12.1, 'minVoltage': 11.9},
          {'day': '2026-11-19', 'restVoltage': null, 'minVoltage': null},
          {'day': '2026-11-20', 'restVoltage': 12.0, 'minVoltage': 11.8},
        ],
      },
    };

Map<String, dynamic> deadline(int id, String kind, String state, {String title = '', String? dueDate, int? dueKm, int? days, int? km, int? everyMonths, int? everyKm}) => {
      'id': id,
      'kind': kind,
      'title': title,
      'dueDate': dueDate,
      'dueKm': dueKm,
      'everyMonths': everyMonths,
      'everyKm': everyKm,
      'remindDays': 30,
      'remindKm': 1000,
      'note': '',
      'remainingDays': days,
      'remainingKm': km,
      'state': state,
    };

void main() {
  setUpAll(initFormats);

  group('statistics over time', () {
    testWidgets('months and weeks, battery health, SIM against the plan', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1/trends', (_) => trendsJson('low'));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1/trends');
      await settle(tester);
      expect(find.text(it.trends), findsOneWidget);
      expect(find.textContaining(it.batteryLow('12,05')), findsOneWidget);
      expect(find.textContaining(it.batteryTrend('-0,30')), findsOneWidget);
      expect(find.text(it.trendsKmSplit('120', '0')), findsOneWidget);
      expect(find.text('ott 26'), findsWidgets);
      await reveal(tester, find.text(it.trendsAlarms));
      expect(find.text(it.trendsSim), findsOneWidget);

      await tapAndSettle(tester, find.text(it.trendsWeeks));
      expect(find.text('16/11'), findsWidgets);
      expect(find.text(it.trendsKmSplit('0', '0')), findsNothing);
    });

    testWidgets('states of the battery; phones without battery and SIM; errors', (tester) async {
      var state = 'good';
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/trends', (_) => trendsJson(state, trend: null))
        ..on('GET', '/api/devices/3/trends', (_) => {...trendsJson('unknown'), 'battery': null, 'simBudgetBytes': null});
      final app = TestApp(backend);
      await app.start(tester);
      for (final (value, text) in [('good', it.batteryGood('12,05')), ('fair', it.batteryFair('12,05'))]) {
        state = value;
        app.go(tester, '/devices/1/trends');
        await settle(tester);
        expect(find.text(text), findsOneWidget);
        app.go(tester, '/devices');
        await settle(tester);
      }
      backend.on('GET', '/api/devices/1/trends', (_) => trendsJson('unknown', average: null, trend: null));
      app.go(tester, '/devices/1/trends');
      await settle(tester);
      expect(find.text(it.batteryUnknown), findsOneWidget);

      app.go(tester, '/devices/3/trends');
      await settle(tester);
      expect(find.byKey(const Key('batteryHealth')), findsNothing);
      expect(find.text(it.trendsSim), findsNothing);

      backend.on('GET', '/api/devices/3/trends', (_) => Reply.error(403, 'owner_only'));
      app.go(tester, '/devices');
      await settle(tester);
      app.go(tester, '/devices/3/trends');
      await settle(tester);
      expect(find.text(it.errOwnerOnly), findsOneWidget);
    });
  });

  group('trip log', () {
    testWidgets('business or personal with a note, monthly CSV, links to the pages', (tester) async {
      final start = iso(ago(const Duration(hours: 2)));
      var trip = <String, dynamic>{
        'start': start,
        'end': iso(ago(const Duration(hours: 1, minutes: 30))),
        'distanceKm': 12.3,
        'durationMin': 30,
        'avgSpeed': 40,
        'maxSpeed': 90,
        'purpose': null,
        'note': '',
        'cost': {'fuelL': 0.62, 'fuelCost': 1.11, 'wearCost': 1.23, 'cost': 2.34},
      };
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/trips', (_) => {
              'trips': [trip],
              'days': [],
              'totals': {
                'distanceKm': 12.3,
                'drivingMin': 30,
                'maxSpeed': 90,
                'trips': 1,
                'cost': {'fuelL': 0.62, 'fuelCost': 1.11, 'wearCost': 1.23, 'cost': 2.34},
              },
            })
        ..on('GET', '/api/devices/1/stats', (_) => {'series': [], 'bucket': '1 hour'})
        ..on('GET', '/api/devices/1/distribution', (_) => {
              'quality': {'total': 0, 'stale': 0, 'weak_fix': 0, 'weak_signal': 0},
              'signal': [],
              'satellites': [],
              'speed': [],
            })
        ..on('GET', '/api/devices/1/coverage', (_) => {'cells': []})
        ..on('GET', '/api/devices/1/traffic', (_) => {
              'daily': [],
              'budgetBytes': 200 * 1024 * 1024,
              'month': {'estimatedBytes': 0, 'projectedBytes': 0},
            })
        ..on('PUT', '/api/devices/1/trips/tag', (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          trip = {...trip, 'purpose': body['purpose'], 'note': body['note']};
          return {'ok': true};
        })
        ..on('GET', '/api/devices/1/logbook', (request) => RawReply(
              utf8.encode('Data;Partenza'),
              {'content-disposition': 'attachment; filename="Panda-${request.url.queryParameters['month']}.csv"'},
            ))
        ..on('GET', '/api/devices/1/trends', (_) => trendsJson('good'))
        ..on('GET', '/api/devices/1/maintenance', (_) => {'odometerKm': null, 'items': [], 'log': []});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=2');
      await settle(tester);

      final now = DateTime.now();
      await tapAndSettle(tester, find.byKey(const Key('exportLogbook')));
      expect(app.saved.single.name, 'Panda-${now.year}-${now.month.toString().padLeft(2, '0')}.csv');
      backend.on('GET', '/api/devices/1/logbook', (_) => Reply.error(403, 'owner_only'));
      await tapAndSettle(tester, find.byKey(const Key('exportLogbook')));
      expect(find.text(it.errOwnerOnly), findsOneWidget);
      await clearSnackbars(tester);

      await reveal(tester, find.text(it.kpiCost));
      expect(find.text(it.kpiCost), findsOneWidget);
      await tapAndSettle(tester, find.text(it.tripsList(1)));
      expect(find.textContaining('≈ ${formatEuro(2.34)} (${it.costFuel(formatEuro(1.11))} · ${it.costWear(formatEuro(1.23))})'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(Key('tag$start')));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/trips/tag'), isEmpty);

      await tapAndSettle(tester, find.byKey(Key('tag$start')));
      await tapAndSettle(tester, find.text(it.purposeBusiness));
      await tester.enterText(find.byKey(const Key('tripNote')), ' Cliente Rossi ');
      await tapAndSettle(tester, find.byKey(const Key('tagSave')));
      expect(backend.lastBody('/api/devices/1/trips/tag'), {'start': start, 'purpose': 'business', 'note': 'Cliente Rossi'});
      expect(find.textContaining('Cliente Rossi'), findsOneWidget);
      expect(find.byIcon(Icons.work), findsOneWidget);

      await tapAndSettle(tester, find.byKey(Key('tag$start')));
      await tapAndSettle(tester, find.text(it.purposePersonal));
      await tapAndSettle(tester, find.byKey(const Key('tagSave')));
      expect(find.byIcon(Icons.home), findsWidgets);
      await tapAndSettle(tester, find.byKey(Key('tag$start')));
      await tapAndSettle(tester, find.text(it.purposeNone));
      await tapAndSettle(tester, find.byKey(const Key('tagSave')));
      expect(backend.lastBody('/api/devices/1/trips/tag')['purpose'], isNull);

      backend.on('PUT', '/api/devices/1/trips/tag', (_) => Reply.error(403, 'owner_only'));
      await tapAndSettle(tester, find.byKey(Key('tag$start')));
      await tapAndSettle(tester, find.byKey(const Key('tagSave')));
      expect(find.text(it.errOwnerOnly), findsOneWidget);
      await clearSnackbars(tester);

      await tapAndSettle(tester, find.byKey(const Key('openTrends')));
      expect(find.text(it.trendsKm), findsOneWidget);
      app.go(tester, '/devices/1?tab=2');
      await settle(tester);
      await tapAndSettle(tester, find.byKey(const Key('openMaintenance')));
      expect(find.text(it.odometerUnset), findsOneWidget);
    });

    test('cost of a trip: litres without the price, wear alone', () {
      expect(costText(it, {'fuelL': 0.6, 'fuelCost': null, 'wearCost': null, 'cost': null}), '0,60 l');
      expect(costText(it, {'fuelL': null, 'fuelCost': null, 'wearCost': 1.2, 'cost': 1.2}), '≈ ${formatEuro(1.2)} (${it.costWear(formatEuro(1.2))})');
    });

    testWidgets('litres in the totals when the fuel price is missing', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/3', (_) => phoneDevice())
        ..on('GET', '/api/devices/3/shares', (_) => [])
        ..on('GET', '/api/devices/3/geofences', (_) => [])
        ..on('GET', '/api/devices/3/positions', (_) => {'positions': [], 'truncated': false})
        ..on('GET', '/api/devices/3/trips', (_) => {
              'trips': [],
              'days': [],
              'totals': {
                'distanceKm': 10.0,
                'drivingMin': 20,
                'maxSpeed': 50,
                'trips': 1,
                'cost': {'fuelL': 0.6, 'fuelCost': null, 'wearCost': null, 'cost': null},
              },
            });
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3});
      app.go(tester, '/devices/3?tab=2');
      await settle(tester);
      expect(find.text(it.kpiFuel), findsOneWidget);
      expect(find.text('0,6 l'), findsOneWidget);
    });
  });

  group('trip costs', () {
    testWidgets('fuel, unit, national average, price, consumption and wear over time, errors', (tester) async {
      final rates = <String, List<Map<String, dynamic>>>{
        'price': [
          {'validFrom': '2026-11-01', 'value': 1.85},
          {'validFrom': '2026-09-15', 'value': 1.72},
        ],
        'consumption': [
          {'validFrom': '2026-01-01', 'value': 5},
        ],
        'wear': [],
      };
      var settings = <String, dynamic>{'model': '', 'fuelUnit': 'l_per_100km', 'fuelType': null, 'fuelPriceAuto': false};
      Map<String, dynamic> profile() => {
            ...settings,
            'rates': rates,
            'current': {
              'price': rates['price']!.firstOrNull?['value'],
              'consumption': rates['consumption']!.firstOrNull?['value'],
              'wear': rates['wear']!.firstOrNull?['value'],
            },
            'costPerKm': 0.19,
            'average': settings['fuelType'] == null ? null : {'week': '2026-11-16', 'price': 1.97},
          };
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/vehicle', (_) => profile())
        ..on('PUT', '/api/devices/1/vehicle', (request) {
          settings = jsonDecode(request.body) as Map<String, dynamic>;
          return profile();
        })
        ..on('POST', '/api/devices/1/rates', (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          rates[body['kind'] as String] = [
            {'validFrom': body['validFrom'], 'value': body['value']},
            ...rates[body['kind']]!,
          ];
          return profile();
        })
        ..on('DELETE', '/api/devices/1/rates/price/2026-09-15', (_) {
          rates['price']!.removeWhere((item) => item['validFrom'] == '2026-09-15');
          return profile();
        });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1/costs');
      await settle(tester);
      Future<void> show(Finder finder) async {
        await reveal(tester, finder);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(find.text(it.costPerKm(formatEuro(0.19, digits: 3))), findsOneWidget);
      expect(find.text(it.fuelPriceAutoNeedsType), findsOneWidget);
      expect(find.byKey(const Key('average')), findsNothing);

      // Fuel and unit, then the national average followed
      await tapAndSettle(tester, find.byKey(const Key('fuelType')));
      await tapAndSettle(tester, find.text(it.fuelDiesel).last);
      await tapAndSettle(tester, find.text('km/l'));
      await tester.enterText(find.byKey(const Key('vehicleModel')), ' Fiat Panda 1.2 ');
      await show(find.byKey(const Key('fuelPriceAuto')));
      await tapAndSettle(tester, find.byKey(const Key('fuelPriceAuto')));
      await show(find.byKey(const Key('vehicleSave')));
      await tapAndSettle(tester, find.byKey(const Key('vehicleSave')));
      expect(backend.lastBody('/api/devices/1/vehicle', 'PUT'),
          {'model': 'Fiat Panda 1.2', 'fuelUnit': 'km_per_l', 'fuelType': 'diesel', 'fuelPriceAuto': true, 'ratesFromRefuels': true});
      expect(find.text(it.costsSaved), findsOneWidget);
      expect(find.text(it.nationalAverage(it.fuelDiesel, formatEuro(1.97, digits: 3))), findsOneWidget);

      // The average as a price of today
      await clearSnackbars(tester);
      await show(find.byKey(const Key('useAverage')));
      await tapAndSettle(tester, find.byKey(const Key('useAverage')));
      expect(find.text('1,97'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(backend.lastBody('/api/devices/1/rates', 'POST'), {'kind': 'price', 'validFrom': today, 'value': 1.97});
      expect(find.text(it.rateNow('${formatEuro(1.97, digits: 3)}/l')), findsOneWidget);
      expect(find.text(it.rateTrend), findsOneWidget);

      // Consumption from a day, in the unit of the owner; out of range first
      await clearSnackbars(tester);
      await show(find.byKey(const Key('add_consumption')));
      // Consumption shown in km/l: 5 l/100 km = 20 km/l
      expect(find.text(it.rateNow('20 km/l')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('add_consumption')));
      await tester.enterText(find.byKey(const Key('rateValue')), '1');
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(find.text(it.valueRange('2', '100')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rateValue')), '16');
      await tapAndSettle(tester, find.byKey(const Key('rateDate')));
      await tapAndSettle(tester, find.text('OK'));
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(backend.lastBody('/api/devices/1/rates', 'POST'), {'kind': 'consumption', 'validFrom': today, 'value': 16.0, 'unit': 'km_per_l'});

      // Wear: not a number, cancelled; ACI search
      await clearSnackbars(tester);
      await show(find.byKey(const Key('add_wear')));
      expect(find.text(it.rateUnset), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('add_wear')));
      await tester.enterText(find.byKey(const Key('rateValue')), 'caro');
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(find.text(it.valueRange('0', '10')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rateValue')), '0,12');
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(backend.lastBody('/api/devices/1/rates', 'POST'), {'kind': 'wear', 'validFrom': today, 'value': 0.12});
      await tapAndSettle(tester, find.byKey(const Key('add_wear')));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/rates', 'POST'), hasLength(3));
      await clearSnackbars(tester);
      await show(find.byKey(const Key('searchAci')));
      await tapAndSettle(tester, find.byKey(const Key('searchAci')));
      expect(app.opened.single.queryParameters['q'], 'ACI costi chilometrici Fiat Panda 1.2');

      // Old price removed
      final old = find.byKey(const Key('delete_price_2026-09-15'));
      await show(old);
      await tapAndSettle(tester, old);
      expect(backend.calls('/api/devices/1/rates/price/2026-09-15', 'DELETE'), hasLength(1));
      expect(old, findsNothing);

      backend.on('POST', '/api/devices/1/rates', (_) => Reply.error(400, 'too_many_rates'));
      await clearSnackbars(tester);
      await show(find.byKey(const Key('add_wear')));
      await tapAndSettle(tester, find.byKey(const Key('add_wear')));
      await tester.enterText(find.byKey(const Key('rateValue')), '0,2');
      await tapAndSettle(tester, find.byKey(const Key('rateSave')));
      expect(find.text(it.errTooManyRates), findsOneWidget);
      backend.on('PUT', '/api/devices/1/vehicle', (_) => Reply.error(403, 'owner_only'));
      await clearSnackbars(tester);
      await show(find.byKey(const Key('vehicleSave')));
      await tapAndSettle(tester, find.byKey(const Key('vehicleSave')));
      expect(find.text(it.errOwnerOnly), findsOneWidget);
    });

    testWidgets('extra data of the tracker: latest values, readings, realtime, empty', (tester) async {
      var data = <String, dynamic>{'latest': [], 'items': []};
      final backend = fullBackend()..on('GET', '/api/devices/1/extra', (_) => data);
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=2');
      await settle(tester);
      await tapAndSettle(tester, find.byKey(const Key('openExtra')));
      await settle(tester);
      expect(find.byKey(const Key('extraEmpty')), findsOneWidget);

      final time = iso(ago(const Duration(minutes: 2)));
      data = {
        'latest': [
          {'key': 'coolant', 'value': 88.5, 'time': time},
          {'key': 'door', 'value': 'open', 'time': time},
          {'key': 'dtc', 'value': ['P0420'], 'time': time},
          {'key': 'ok', 'value': true, 'time': time},
          {'key': 'rpm', 'value': 900, 'time': time},
          {'key': 'none', 'value': null, 'time': time},
          {'key': 'gear', 'value': 3.0, 'time': time},
        ],
        'items': [
          {'time': time, 'data': {'rpm': 900, 'door': 'open'}},
          {'time': time, 'data': {'rpm': 820}},
        ],
      };
      app.socket.emit({'type': 'extra', 'deviceId': 1, 'time': time, 'data': {'rpm': 900}});
      await settle(tester);
      expect(find.text('88,50'), findsOneWidget);
      expect(find.text('open'), findsOneWidget);
      expect(find.text('["P0420"]'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(it.extraReadings(2)), findsOneWidget);
      expect(find.text(it.extraFields(1)), findsOneWidget);
      await reveal(tester, find.text(it.extraFields(2)));
      await tapAndSettle(tester, find.text(it.extraFields(2)));
      expect(find.text('900'), findsNWidgets(2));
    });

    testWidgets('costs that cannot be loaded', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/2/vehicle', (_) => Reply.error(403, 'owner_only'));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/2/costs');
      await settle(tester);
      expect(find.text(it.errOwnerOnly), findsOneWidget);
    });
  });

  group('deadlines', () {
    testWidgets('odometer, list by state, new, edit, done, delete, log', (tester) async {
      final soon = DateTime.now();
      final soonText = '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
      final backend = fullBackend()
        ..on('GET', '/api/devices/1/maintenance', (_) => {
              'odometerKm': 50000,
              'items': [
                deadline(1, 'inspection', 'due', title: 'Revisione 2026', dueDate: '2026-11-20', days: -1),
                deadline(2, 'service', 'soon', dueKm: 50500, km: 500, everyKm: 15000, everyMonths: 24),
                deadline(3, 'tax', 'ok', dueDate: '2027-03-01', days: 100, everyMonths: 12),
              ],
              'log': [
                {'id': 1, 'kind': 'tyres', 'title': '', 'doneOn': '2026-10-01', 'km': 48000, 'note': 'Invernali'},
                {'id': 2, 'kind': 'other', 'title': 'Lavaggio', 'doneOn': '2026-09-01', 'km': null, 'note': ''},
              ],
            })
        ..on('PUT', '/api/devices/1/odometer', (_) => {'odometerKm': 51000})
        ..on('POST', '/api/devices/1/maintenance', (_) => deadline(4, 'insurance', 'soon'))
        ..on('PATCH', '/api/maintenance/2', (_) => deadline(2, 'service', 'soon'))
        ..on('POST', '/api/maintenance/1/done', (_) => {'next': null})
        ..on('DELETE', '/api/maintenance/3', (_) => {'ok': true});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1/maintenance');
      await settle(tester);
      expect(find.text(it.odometerValue('50.000')), findsOneWidget);
      expect(find.text('Revisione 2026'), findsOneWidget);
      expect(find.textContaining(it.overdueDays(1)), findsOneWidget);
      expect(find.textContaining(it.inKm('500')), findsOneWidget);
      expect(find.textContaining(it.deadlineEvery(it.monthsShort(24))), findsOneWidget);
      expect(find.textContaining('Invernali'), findsOneWidget);
      expect(find.text('Lavaggio'), findsOneWidget);

      // Odometer: invalid, then saved
      await tapAndSettle(tester, find.byKey(const Key('odometer')));
      await tester.enterText(find.byKey(const Key('numberField')), 'tanti');
      await tapAndSettle(tester, find.byKey(const Key('numberSave')));
      expect(find.text(it.invalidNumber), findsOneWidget);
      await tester.enterText(find.byKey(const Key('numberField')), '51000');
      await tapAndSettle(tester, find.byKey(const Key('numberSave')));
      expect(backend.lastBody('/api/devices/1/odometer'), {'km': 51000});
      await tapAndSettle(tester, find.byKey(const Key('odometer')));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/devices/1/odometer'), hasLength(1));

      // New: a date or the km are needed (the picker opens on today)
      await tapAndSettle(tester, find.byKey(const Key('addDeadline')));
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      expect(find.text(it.deadlineNeedsDue), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('deadlineKind')));
      await tapAndSettle(tester, find.text(it.mkOther).last);
      expect(find.text(it.deadlineTitleRequired), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      expect(find.text(it.deadlineNeedsTitle), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('deadlineKind')));
      await tapAndSettle(tester, find.text(it.mkInsurance).last);
      await tapAndSettle(tester, find.byKey(const Key('deadlineDate')));
      await tapAndSettle(tester, find.text('OK'));
      await tester.enterText(find.byKey(const Key('deadlineTitle')), 'Polizza');
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      expect(backend.lastBody('/api/devices/1/maintenance', 'POST'), {
        'kind': 'insurance',
        'title': 'Polizza',
        'dueDate': soonText,
        'dueKm': null,
        'everyMonths': null,
        'everyKm': null,
        'remindDays': 30,
        'remindKm': 1000,
        'note': '',
      });

      // Edit: date removed, km set
      await tapAndSettle(tester, find.byKey(const Key('deadline1')));
      await tapAndSettle(tester, find.byKey(const Key('deadlineClearDate')));
      expect(find.text(it.deadlineNoDate), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));
      await tapAndSettle(tester, find.byKey(const Key('deadline2')));
      await tester.enterText(find.byKey(const Key('deadlineEveryKm')), '20000');
      await tester.enterText(find.byKey(const Key('deadlineRemindKm')), '');
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      final changes = backend.lastBody('/api/maintenance/2', 'PATCH');
      expect([changes['everyKm'], changes['everyMonths'], changes['remindKm'], changes['dueKm']], [20000, 24, 1000, 50500]);

      // Done with the km, delete after a confirmation
      await tapAndSettle(tester, find.byKey(const Key('deadlineMenu1')));
      await tapAndSettle(tester, find.text(it.deadlineDone));
      expect(find.text(it.deadlineDoneTitle('Revisione 2026')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('numberSave')));
      expect(backend.lastBody('/api/maintenance/1/done'), {'km': 50000});
      await tapAndSettle(tester, find.byKey(const Key('deadlineMenu3')));
      await tapAndSettle(tester, find.text(it.delete));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/maintenance/3'), isEmpty);
      await tapAndSettle(tester, find.byKey(const Key('deadlineMenu3')));
      await tapAndSettle(tester, find.text(it.delete));
      await tapAndSettle(tester, find.byKey(const Key('confirmDelete')));
      expect(backend.calls('/api/maintenance/3', 'DELETE'), hasLength(1));

      backend.on('PATCH', '/api/maintenance/2', (_) => Reply.error(400, 'deadline_untitled'));
      await tapAndSettle(tester, find.byKey(const Key('deadline2')));
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      expect(find.text(it.deadlineNeedsTitle), findsOneWidget);
      await clearSnackbars(tester);

      backend.on('POST', '/api/devices/1/maintenance', (_) => Reply.error(400, 'too_many_deadlines'));
      await tapAndSettle(tester, find.byKey(const Key('addDeadline')));
      await tester.enterText(find.byKey(const Key('deadlineKm')), '60000');
      await tapAndSettle(tester, find.byKey(const Key('deadlineSave')));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('no deadlines, errors', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices/1/maintenance', (_) => {'odometerKm': null, 'items': [], 'log': []});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1/maintenance');
      await settle(tester);
      expect(find.text(it.noDeadlines), findsOneWidget);
      backend.on('GET', '/api/devices/3/maintenance', (_) => Reply.error(400, 'not_a_tracker'));
      app.go(tester, '/devices/3/maintenance');
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(it.noDeadlines), findsNothing);
    });
  });

  group('texts', () {
    testWidgets('notifications of the car in both languages', (tester) async {
      final data = NotificationData(device: 'Panda', time: DateTime(2026, 11, 21, 9, 5), voltage: 12.1);
      expect(notificationText(it, 'battery_health', data).body, it.notificationBodyBatteryHealth('Panda', '12,10'));
      expect(notificationText(it, 'battery_health', NotificationData(device: 'Panda', time: DateTime(2026))).title, it.kindBatteryHealth);
      NotificationData deadlineData(String due, {int? days, int? km, String? title, String? kind}) =>
          NotificationData.fromJson({'device': 'Panda', 'maintenance': kind, 'title': title, 'due': due, 'days': days, 'km': km}, DateTime(2026));
      expect(notificationText(it, 'maintenance', deadlineData('soon', days: 10, km: 1500, kind: 'service')),
          (title: it.maintenanceSoonTitle(it.mkService), body: 'Panda: ${it.inDays(10)}${it.orJoin}${it.inKm('1.500')}'));
      expect(notificationText(it, 'maintenance', deadlineData('due', days: 0, title: 'Revisione 2026')).title, it.maintenanceDueTitle('Revisione 2026'));
      expect(notificationText(it, 'maintenance', deadlineData('due', days: -3, km: -20)).body, 'Panda: ${it.overdueDays(3)}${it.orJoin}${it.kmOver('20')}');
      expect(notificationText(it, 'maintenance', deadlineData('due', days: 0)).body, 'Panda: ${it.today}');
      for (final kind in ['inspection', 'insurance', 'tax', 'tyres', 'other']) {
        expect(maintenanceKindLabel(it, kind), isNotEmpty);
      }
      expect(kindLabel(it, 'battery_health'), it.kindBatteryHealth);
      expect(kindLabel(it, 'maintenance'), it.kindMaintenance);
      expect(AppNotification.fromJson(notificationJson(1, 'battery_health')).icon, Icons.battery_3_bar);
      expect(AppNotification.fromJson(notificationJson(1, 'maintenance')).icon, Icons.build);
    });
  });

  group('backups', () {
    testWidgets('state for the administrator, warning when stale, hidden when not set up', (tester) async {
      var stale = false;
      Map<String, dynamic>? verify = {'time': iso(ago(const Duration(days: 2))), 'ok': true, 'error': ''};
      var verifyStale = false;
      final backend = fullBackend()
        ..on('GET', '/api/admin/users', (_) => [])
        ..on('GET', '/api/admin/invites', (_) => [])
        ..on('GET', '/api/admin/firmware', (_) => [])
        ..on('GET', '/api/admin/backup', (_) => {
              'configured': true,
              'lastSuccess': iso(ago(const Duration(hours: 3))),
              'lastOffsite': stale ? null : iso(ago(const Duration(hours: 2))),
              'stale': stale,
              'verify': verify,
              'verifyStale': verifyStale,
              'latest': stale ? null : {'name': 'daily/2026-11-21_0330.dump', 'size': 2 * 1024 * 1024},
              'files': 12,
              'totalBytes': 30 * 1024 * 1024,
            });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account/admin');
      await settle(tester);
      expect(find.byKey(const Key('backupCard')), findsOneWidget);
      expect(find.textContaining(it.backupFiles(12, formatBytes(30 * 1024 * 1024))), findsOneWidget);
      expect(find.byIcon(Icons.backup), findsOneWidget);
      expect(find.textContaining(it.backupVerifyOk('').trim()), findsOneWidget);

      // Restore test failed, then old, then never done
      Future<void> reopen() async {
        app.go(tester, '/account');
        await settle(tester);
        app.go(tester, '/account/admin');
        await settle(tester);
      }

      verify = {'time': iso(ago(const Duration(days: 1))), 'ok': false, 'error': 'restore failed: out of disk'};
      verifyStale = true;
      await reopen();
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.textContaining('restore failed: out of disk'), findsOneWidget);
      verify = {'time': iso(ago(const Duration(days: 12))), 'ok': true, 'error': ''};
      await reopen();
      expect(find.textContaining(it.backupVerifyOld), findsOneWidget);
      verify = null;
      verifyStale = false;
      await reopen();
      expect(find.textContaining(it.backupNoVerify), findsOneWidget);

      stale = true;
      app.go(tester, '/account');
      await settle(tester);
      app.go(tester, '/account/admin');
      await settle(tester);
      expect(find.textContaining(it.backupStale), findsOneWidget);
      expect(find.textContaining(it.backupNoOffsite), findsOneWidget);

      backend.on('GET', '/api/admin/backup', (_) => {'configured': false, 'stale': true, 'files': 0, 'totalBytes': 0});
      app.go(tester, '/account');
      await settle(tester);
      app.go(tester, '/account/admin');
      await settle(tester);
      expect(find.byKey(const Key('backupCard')), findsNothing);
    });
  });
}
