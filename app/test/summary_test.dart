import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/screens/summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Summary of the month: totals with the month before, vehicles, deadlines, the
// notification of the start of the month and its switch in the account

Map<String, dynamic> summaryJson(String month, {bool complete = true, bool empty = false}) => {
      'month': month,
      'from': '$month-01',
      'to': '$month-28',
      'complete': complete,
      'devices': empty
          ? []
          : [
              {
                'id': 1, 'name': 'Panda', 'color': '#1E88E5', 'kind': 'tracker', 'distanceKm': 1234.4, 'businessKm': 300, 'personalKm': 0,
                'drivingMin': 1500, 'trips': 42, 'maxSpeed': 128,
                'cost': {'fuelL': 80, 'fuelCost': 150, 'wearCost': 60, 'cost': 210},
                'refuels': {'count': 2, 'litres': 70, 'cost': 135, 'consumption': 6.4},
                'trafficBytes': 25 * 1024 * 1024, 'alarms': 1,
              },
              {
                'id': 4, 'name': 'Punto', 'color': '#FFB300', 'kind': 'vehicle', 'distanceKm': 0, 'businessKm': 0, 'personalKm': 0,
                'drivingMin': 0, 'trips': 0, 'maxSpeed': 0, 'cost': null,
                'refuels': {'count': 1, 'litres': 30, 'cost': null, 'consumption': null},
                'trafficBytes': null, 'alarms': 0,
              },
            ],
      'totals': {'distanceKm': empty ? 0 : 1234.4, 'drivingMin': 1500, 'trips': 42, 'cost': empty ? null : 210, 'refuelCost': 135},
      'previous': {'distanceKm': 1000, 'drivingMin': 0, 'trips': 40, 'cost': null, 'refuelCost': null},
      'deadlines': empty
          ? []
          : [
              {'deviceId': 1, 'kind': 'tax', 'title': '', 'dueDate': '$month-28', 'dueKm': null, 'remainingDays': -2, 'remainingKm': null, 'state': 'due'},
              {'deviceId': 1, 'kind': 'other', 'title': 'Bollino', 'dueDate': null, 'dueKm': 22000, 'remainingDays': null, 'remainingKm': 500, 'state': 'soon'},
            ],
    };

void main() {
  test('months', () {
    expect(shiftMonth('2026-01', -1), '2025-12');
    expect(shiftMonth('2026-12', 1), '2027-01');
    expect(lastMonth(DateTime(2026, 3, 15)), '2026-02');
    expect(monthName('2026-10'), isNotEmpty);
  });

  testWidgets('summary of the month: totals, vehicles, deadlines, months', (tester) async {
    final month = lastMonth();
    final backend = fullBackend()
      ..on('GET', '/api/account', (_) => {'user': userJson(), 'passkeys': [], 'sessions': [], 'recoveryCodesLeft': 10, 'monthlySummary': true})
      ..on('GET', '/api/summary/$month', (_) => summaryJson(month))
      ..on('GET', '/api/summary/${shiftMonth(month, -1)}', (_) => summaryJson(shiftMonth(month, -1), empty: true))
      ..on('GET', '/api/summary/${shiftMonth(month, 1)}', (_) => summaryJson(shiftMonth(month, 1), complete: false));
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/account');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('openSummary')));

    expect(find.text('${formatInt(1234)} km'), findsOneWidget);
    expect(find.text(it.comparedToBefore('+23%')), findsOneWidget);
    expect(find.text(it.comparedToBefore('+5%')), findsOneWidget);
    expect(find.text(formatEuro(210)), findsOneWidget);
    expect(find.textContaining(it.summaryRefuels(2, formatEuro(135))), findsOneWidget);
    expect(find.textContaining(it.summaryRefuels(1, '${formatDecimal(30, 1)} l')), findsOneWidget);
    expect(find.textContaining(it.summaryAlarms(1)), findsOneWidget);
    expect(find.textContaining(it.summaryBusiness(formatInt(300))), findsOneWidget);
    await reveal(tester, find.textContaining('Bollino'));
    expect(find.textContaining(maintenanceKindLabel(it, 'tax')), findsOneWidget);

    // The month before (no vehicles), then the current one (partial), not beyond
    await tapAndSettle(tester, find.byKey(const Key('summaryPrevious')));
    expect(find.text(it.summaryEmpty), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('summaryNext')));
    await tapAndSettle(tester, find.byKey(const Key('summaryNext')));
    expect(find.byKey(const Key('summaryPartial')), findsOneWidget);
    final next = tester.widget<IconButton>(find.byKey(const Key('summaryNext')));
    expect(next.onPressed, isNull);

    // A vehicle opens its analysis, a deadline the deadlines
    backend.on('GET', '/api/summary/$month', (_) => summaryJson(month));
    app.go(tester, '/account/summary?month=$month');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('summaryDevice_1')));
    expect(find.byKey(const Key('openRefuels')), findsOneWidget);
  });

  testWidgets('switch of the notification, errors; the notification opens the summary', (tester) async {
    final month = lastMonth();
    final backend = fullBackend()
      ..on('GET', '/api/account', (_) => {'user': userJson(), 'passkeys': [], 'sessions': [], 'recoveryCodesLeft': 10, 'monthlySummary': true})
      ..on('GET', '/api/summary/$month', (_) => Reply.error(400, 'month_out_of_range'))
      ..on('GET', '/api/notifications', (_) => {
            'notifications': [
              {
                ...notificationJson(7, 'monthly_summary'),
                'deviceId': null,
                'data': {'device': '', 'month': month, 'distanceKm': 1234.5, 'trips': 42, 'cost': 156.4, 'time': iso(ago(const Duration(hours: 1)))},
              },
            ],
            'unread': 1,
          });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/account');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('monthlySummary')));
    expect(backend.lastBody('/api/account', 'PATCH'), {'monthlySummary': false});
    backend.on('PATCH', '/api/account', (_) => Reply.error(500, 'x'));
    await tapAndSettle(tester, find.byKey(const Key('monthlySummary')));
    expect(find.text(it.errGeneric(500)), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('monthlySummary'))).value, isFalse);

    app.go(tester, '/notifications');
    await settle(tester);
    final title = it.summaryNotificationTitle('');
    expect(find.textContaining(title.trim()), findsOneWidget);
    expect(find.textContaining(formatEuro(156.4)), findsOneWidget);
    await tapAndSettle(tester, find.textContaining(title.trim()));
    expect(find.text(it.monthlySummary), findsOneWidget);
    expect(find.text(it.errGeneric(400)), findsOneWidget);
  });
}
