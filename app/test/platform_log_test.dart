import 'package:car_tracking/screens/platform_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Platform log of the administration: errors, warnings, slow requests and queries grouped

Map<String, dynamic> logGroup(String message, {int count = 1, num? maxMs, num? avgMs, int? calls, Map<String, dynamic> details = const {}}) => {
      'source': 'http',
      'message': message,
      'count': count,
      'first': iso(ago(const Duration(days: 2))),
      'last': iso(ago(const Duration(minutes: 5))),
      'maxMs': maxMs,
      'avgMs': avgMs,
      'calls': calls,
      'details': details,
    };

/// Platform log of the backend by kind; every request recorded
FakeBackend logBackend({bool slowQueries = true}) => fullBackend()
  ..on('GET', '/api/admin/logs', (request) {
    final groups = switch (request.url.queryParameters['kind']) {
      'error' => [
          logGroup('GET /api/dashboards', count: 3, details: {
            'status': 500,
            'error': 'PostgresError',
            'errorMessage': 'relation "dashboards" does not exist',
            'stack': 'PostgresError: relation "dashboards" does not exist\n    at ErrorResponse',
          }),
        ],
      'slow_request' => [
          logGroup('POST /api/dashboards/data', count: 12, maxMs: 2400, avgMs: 1300, details: {'status': 200, 'avgMs': 1300}),
        ],
      'slow_query' => [
          {...logGroup('SELECT time_bucket(\$1, time) FROM positions WHERE device_id = \$2', count: 2, maxMs: 900, avgMs: 150, calls: 40), 'source': 'db'},
        ],
      _ => <Map<String, dynamic>>[],
    };
    return {'retentionDays': 30, 'slowRequestMs': 1000, 'slowQueryMs': 100, 'slowQueries': slowQueries, 'groups': groups};
  });

void main() {
  test('durations', () {
    expect(formatMs(850.4), '850 ms');
    expect(formatMs(2400), contains('s'));
  });

  testWidgets('platform log: kinds, periods, details copied', (tester) async {
    final backend = logBackend();
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/account/admin');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('openPlatformLog')));

    // Errors of the last 7 days, the latest details with the stack
    expect(backend.calls('/api/admin/logs').last.url.queryParameters, {'kind': 'error', 'days': '7'});
    expect(find.text(it.logErrorsHint(30)), findsOneWidget);
    expect(find.text('GET /api/dashboards'), findsOneWidget);
    expect(find.textContaining(it.logTimes(3)), findsOneWidget);
    await tapAndSettle(tester, find.text('GET /api/dashboards'));
    expect(find.byKey(const Key('logStack')), findsOneWidget);
    expect(find.textContaining('errorMessage: relation'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('logCopy')));
    expect(find.text(it.logCopied), findsOneWidget);

    // Other periods and kinds
    await tapAndSettle(tester, find.byKey(const Key('logDays')));
    await tapAndSettle(tester, find.text(it.periodLast30d));
    expect(backend.calls('/api/admin/logs').last.url.queryParameters, {'kind': 'error', 'days': '30'});
    await tapAndSettle(tester, find.text(it.logWarnings));
    expect(find.byKey(const Key('logEmpty')), findsOneWidget);
    await tapAndSettle(tester, find.text(it.logSlowRequests));
    expect(find.text(it.logRequestsHint(1000, 30)), findsOneWidget);
    expect(find.textContaining(it.logDurations('1,3 s', '2,4 s')), findsOneWidget);
    await tapAndSettle(tester, find.text(it.logSlowQueries));
    expect(find.text(it.logQueriesHint(100, 30)), findsOneWidget);
    expect(find.textContaining(it.logCalls(40)), findsOneWidget);
    expect(find.byKey(const Key('logQueriesOff')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('logGroup0')));
    expect(find.textContaining('time_bucket'), findsNWidgets(2));
  });

  testWidgets('platform log: slow queries not collected, errors', (tester) async {
    final backend = logBackend(slowQueries: false);
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/account/admin/logs');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.logSlowQueries));
    expect(find.byKey(const Key('logQueriesOff')), findsOneWidget);

    backend.on('GET', '/api/admin/logs', (_) => Reply.error(403, 'forbidden'));
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await settle(tester);
    expect(find.text(it.errForbidden), findsOneWidget);
  });
}
