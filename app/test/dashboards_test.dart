import 'dart:convert';

import 'package:car_tracking/screens/dashboards/catalog.dart';
import 'package:car_tracking/screens/dashboards/widget_card.dart';
import 'package:car_tracking/screens/dashboards/widget_editor.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:car_tracking/widgets/charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Custom dashboards: templates, grid, widget editor, edit mode, devices no longer available,
// current dashboard in the analysis of the vehicles, layouts sent to friends

String day(int offset) => DateTime.now().add(Duration(days: offset)).toIso8601String().substring(0, 10);

const panda = {'id': 1, 'name': 'Panda', 'color': '#E53935', 'kind': 'tracker'};
const punto = {'id': 4, 'name': 'Punto', 'color': '#FFB300', 'kind': 'vehicle'};

/// Values of a widget as the backend computes them, by view
Map<String, dynamic> fakeResult(Map<String, dynamic> widget) {
  final base = {'status': 'ok', 'from': day(-6), 'to': day(0), 'devices': [panda, punto], 'unavailable': <int>[]};
  final metric = widget['metric'];
  if (metric == 'status') return base;
  if (metric == 'deadlines') {
    return {
      ...base,
      'items': [
        {'deviceId': 4, 'kind': 'service', 'title': '', 'remainingDays': null, 'remainingKm': -1000, 'state': 'due'},
        {'deviceId': 4, 'kind': 'other', 'title': 'Revisione gomme', 'remainingDays': 10, 'remainingKm': null, 'state': 'soon'},
        {'deviceId': 4, 'kind': 'tax', 'title': '', 'remainingDays': 200, 'remainingKm': null, 'state': 'ok'},
      ],
    };
  }
  return switch (widget['view']) {
    'number' => {...base, 'value': 60.5},
    'vehicles' || 'table' => {
        ...base,
        'values': [
          {'deviceId': 1, 'value': 40},
          {'deviceId': 4, 'value': null},
        ],
      },
    _ => {
        ...base,
        'bucket': metric == 'signal' ? '1 hour' : '1 day',
        'series': [
          {
            'deviceId': 1,
            'points': metric == 'signal'
                ? [
                    [iso(ago(const Duration(hours: 3))), -80],
                    [iso(ago(const Duration(hours: 2))), null],
                    [iso(ago(const Duration(hours: 1))), -90],
                  ]
                : [
                    [day(-2), 10],
                    [day(-1), null],
                    [day(0), 5],
                  ],
          },
          {
            'deviceId': 4,
            'points': [
              [day(-1), 3],
            ],
          },
        ],
      },
  };
}

/// Backend with dashboards kept in memory
FakeBackend dashboardBackend({List<Map<String, dynamic>>? initial, Map<String, dynamic>? Function(Map<String, dynamic>)? result}) {
  final saved = [...?initial];
  var next = 10;
  final backend = fullBackend()
    ..on('GET', '/api/devices', (_) => [ownerDevice(), viewerDevice(), vehicleDevice(), {...vehicleDevice(id: 5), 'name': 'Uno', 'archived': true}])
    ..on('GET', '/api/dashboards', (_) => saved)
    ..on('POST', '/api/dashboards', (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = {'id': next++, ...body};
      saved.add(created);
      return created;
    })
    ..on('POST', '/api/dashboards/data', (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return {
        'results': {
          for (final w in (body['widgets'] as List).cast<Map<String, dynamic>>())
            w['id']: ?(result ?? fakeResult)(w),
        },
      };
    });
  for (var id = 1; id < 20; id++) {
    backend
      ..on('PUT', '/api/dashboards/$id', (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final index = saved.indexWhere((item) => item['id'] == id);
        saved[index] = {'id': id, ...body};
        return saved[index];
      })
      ..on('DELETE', '/api/dashboards/$id', (_) {
        saved.removeWhere((item) => item['id'] == id);
        return {'ok': true};
      })
      ..on('PUT', '/api/dashboards/$id/current', (request) {
        final current = (jsonDecode(request.body) as Map<String, dynamic>)['current'] as bool;
        for (final item in saved) {
          item['current'] = item['id'] == id ? current : current ? false : item['current'];
        }
        return saved.firstWhere((item) => item['id'] == id);
      })
      ..on('POST', '/api/dashboards/$id/share', (_) => {'ok': true});
  }
  return backend;
}

Map<String, dynamic> dashboardJson(int id, String name, List<Map<String, dynamic>> widgets, {Object period = '30d'}) =>
    {'id': id, 'name': name, 'layout': {'version': 1, 'period': period, 'widgets': widgets}};

Map<String, dynamic> w(String id, String metric, String view, {Map<String, dynamic> extra = const {}}) =>
    {'id': id, 'metric': metric, 'view': view, 'devices': 'all', 'period': null, 'title': '', 'width': 1, 'height': 1, ...extra};

Future<void> openDashboards(WidgetTester tester, TestApp app) async {
  app.go(tester, '/dashboards');
  await settle(tester);
}

void main() {
  test('grid: each widget where its columns are lowest', () {
    DashWidget item(int width, int height) => DashWidget(id: 'x', metric: 'distance', view: 'number', width: width, height: height);
    final places = packGrid([item(1, 1), item(2, 2), item(1, 1), item(4, 1)], 3);
    expect([for (final p in places) (p.column, p.row, p.width)], [(0, 0, 1), (1, 0, 2), (0, 1, 1), (0, 2, 3)]);
    expect(gridColumns(360), 2);
    expect(gridColumns(1200), 6);
    expect(gridColumns(3000), 8);
    expect(template('nothing'), isEmpty);
    final widget = DashWidget.fromJson(w('a', 'extra', 'number', extra: {'key': 'rpm', 'devices': [1, 4], 'title': 'Giri'}));
    expect(widget.devices, [1, 4]);
    expect(widget.titleOf(it), 'Giri');
    expect(widget.copyWith().toJson()['key'], 'rpm');
    expect(periodLabel(it, {'from': '2026-01-01', 'to': '2026-01-31'}), '01/01/2026 – 31/01/2026');
    expect(periodLabel(it, 'later'), 'later');
    for (final m in metrics) {
      expect(m.label(it), isNotEmpty);
      expect(m.label(en), isNotEmpty);
      expect(m.format(it, 1234.5), isNotEmpty);
      expect(sourceGroup(en, m.source), isNotEmpty);
    }
    for (final v in ['number', 'line', 'bars', 'vehicles', 'table', 'list', 'map']) {
      expect(viewLabel(en, v), isNotEmpty);
    }
    for (final a in aggs) {
      expect(aggLabel(en, a), isNotEmpty);
    }
    for (final b in buckets) {
      expect(bucketLabel(en, b), isNotEmpty);
    }
  });

  testWidgets('first dashboard from a template: every view on the grid', (tester) async {
    final backend = dashboardBackend();
    final app = TestApp(backend);
    await app.start(tester);
    await tapAndSettle(tester, find.text(it.navDashboards));
    expect(find.text(it.dashboardEmpty), findsOneWidget);

    // The name proposed is the one of the template
    await tapAndSettle(tester, find.byKey(const Key('createOverview')));
    await tester.enterText(find.byKey(const Key('dashboardName')), '');
    await tapAndSettle(tester, find.byKey(const Key('dashboardNameOk')));
    expect(backend.calls('/api/dashboards', 'POST'), isEmpty);
    await tester.enterText(find.byKey(const Key('dashboardName')), 'Famiglia');
    await tapAndSettle(tester, find.byKey(const Key('dashboardNameOk')));
    final body = backend.lastBody('/api/dashboards', 'POST');
    expect(body['name'], 'Famiglia');
    expect((body['layout'] as Map)['widgets'], hasLength(8));

    expect(find.text('Famiglia'), findsOneWidget);
    expect(find.text('60,5 km'), findsOneWidget);
    expect(find.text('1 h 1 min'), findsOneWidget);
    expect(find.text(it.mDeadlines), findsOneWidget);
    expect(find.text('Punto · ${it.mkService}'), findsOneWidget);
    expect(find.text('Punto · Revisione gomme'), findsOneWidget);
    expect(find.byType(GroupedBars), findsOneWidget);
    expect(find.byType(Bars), findsOneWidget);
    expect(find.byType(DeviceMarker), findsWidgets);
    expect(find.text(it.widgetVehicles(2)), findsWidgets);

    // The deadlines open the page of the vehicle
    await tapAndSettle(tester, find.text('Punto · Revisione gomme'));
    expect(find.text(it.maintenance), findsWidgets);
  });

  testWidgets('dashboards: chosen, renamed, period, deleted, data errors', (tester) async {
    final backend = dashboardBackend(initial: [
      dashboardJson(1, 'Auto', [w('a', 'distance', 'table'), w('b', 'status', 'list'), w('c', 'signal', 'line')]),
      dashboardJson(2, 'Vuota', [], period: {'from': '2026-01-01', 'to': '2026-01-31'}),
    ]);
    final app = TestApp(backend);
    await app.start(tester, size: const Size(1280, 800));
    await openDashboards(tester, app);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('40,0 km'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining(it.filterParked), findsWidgets);
    expect(find.byType(TimeChart), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('dashboardPicker')));
    await tapAndSettle(tester, find.text('Vuota').last);
    expect(find.text(it.dashboardNoWidgets), findsOneWidget);
    expect(find.text('01/01/2026 – 31/01/2026'), findsOneWidget);

    // Period of the dashboard
    await tapAndSettle(tester, find.byKey(const Key('dashboardPeriod')));
    await tapAndSettle(tester, find.text(it.period12m));
    expect(((backend.lastBody('/api/dashboards/2', 'PUT')['layout']) as Map)['period'], '12m');
    await tapAndSettle(tester, find.byKey(const Key('dashboardPeriod')));
    await tapAndSettle(tester, find.text(it.periodCustom));
    await tapAndSettle(tester, find.text('Salva').last);
    final custom = (backend.lastBody('/api/dashboards/2', 'PUT')['layout'] as Map)['period'] as Map;
    expect(custom['to'], day(0));

    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardRename));
    await tester.enterText(find.byKey(const Key('dashboardName')), 'Nuovo nome');
    await tapAndSettle(tester, find.byKey(const Key('dashboardNameOk')));
    expect(backend.lastBody('/api/dashboards/2', 'PUT')['name'], 'Nuovo nome');
    expect(find.text('Nuovo nome'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardDelete));
    expect(find.text(it.dashboardDeleteBody('Nuovo nome')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('confirmDelete')));
    expect(backend.calls('/api/dashboards/2', 'DELETE'), hasLength(1));
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byKey(const Key('dashboardPicker')), findsNothing);

    // New dashboard from the sheet; a failure of the backend is shown
    await tapAndSettle(tester, find.byKey(const Key('dashboardNew')));
    await tapAndSettle(tester, find.byKey(const Key('template_diagnostics')));
    backend.on('POST', '/api/dashboards', (_) => Reply.error(400, 'too_many_dashboards'));
    await tapAndSettle(tester, find.byKey(const Key('dashboardNameOk')));
    expect(find.text(it.errTooManyDashboards), findsOneWidget);

    // The values can't be computed: each card says why
    backend.on('POST', '/api/dashboards/data', (_) => Reply.error(500, 'internal'));
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await settle(tester);
    expect(find.text(it.errGeneric(500)), findsWidgets);
  });

  testWidgets('widgets that can\'t show their values', (tester) async {
    final backend = dashboardBackend(
      initial: [
        dashboardJson(1, 'Auto', [
          w('a', 'signal', 'number', extra: {'period': '12m'}),
          w('b', 'distance', 'number', extra: {'devices': [1, 99]}),
          w('c', 'deadlines', 'list'),
          w('d', 'odometer', 'number'),
          w('e', 'extra', 'number', extra: {'key': 'rpm', 'agg': 'last'}),
          w('f', 'distance', 'number', extra: {'id': 'gone'}),
          w('g', 'distance', 'bars', extra: {'width': 2, 'height': 2}),
        ]),
      ],
      result: (widget) => switch (widget['id']) {
        'a' => {'status': 'error', 'error': 'period_too_long'},
        'b' => {'status': 'ok', 'from': day(-6), 'to': day(0), 'devices': [], 'unavailable': [1, 99], 'value': null},
        'c' => {'status': 'ok', 'devices': [punto], 'unavailable': [], 'items': []},
        'd' => {'status': 'error', 'error': 'other_error'},
        'e' => {'status': 'ok', 'devices': [panda], 'unavailable': [5], 'value': 3000},
        'gone' => null,
        'g' => {
            'status': 'ok',
            'from': day(-6),
            'to': day(0),
            'devices': [panda],
            'unavailable': [],
            'bucket': '1 month',
            'series': [
              {
                'deviceId': 1,
                'points': [
                  [day(0), 5],
                ],
              },
            ],
          },
        _ => fakeResult(widget),
      },
    );
    final app = TestApp(backend);
    await app.start(tester);
    await openDashboards(tester, app);
    expect(find.text(it.widgetPeriodTooLong), findsOneWidget);
    expect(find.text(it.widgetNoDevices), findsOneWidget);
    expect(find.byKey(const Key('unavailable_b')), findsOneWidget);
    expect(find.text(it.widgetUnavailable(2)), findsOneWidget);
    expect(find.text(it.widgetNoDeadlines), findsOneWidget);
    expect(find.text('other_error'), findsOneWidget);
    expect(find.text('${it.mExtra} · rpm'), findsOneWidget);
    expect(find.text('3.000'), findsOneWidget);
    expect(find.text('Panda · ${it.aggLast}'), findsOneWidget);
    expect(find.text(it.noData), findsOneWidget);
    expect(find.byType(GroupedBars), findsOneWidget);
  });

  testWidgets('edit mode: widgets added, changed, duplicated, removed, in order', (tester) async {
    final backend = dashboardBackend(initial: [
      dashboardJson(1, 'Auto', [w('a', 'distance', 'number'), w('b', 'trips', 'number')]),
    ]);
    final app = TestApp(backend);
    await app.start(tester);
    await openDashboards(tester, app);
    await tapAndSettle(tester, find.byKey(const Key('dashboardEdit')));
    expect(find.text('${it.dashboardEdit} · Auto'), findsOneWidget);
    expect(find.byKey(const Key('edit_a')), findsOneWidget);

    // A new widget: LTE signal, maximum per hour, of the tracker, last 7 days
    await tapAndSettle(tester, find.byKey(const Key('widgetAdd')));
    expect(find.text(it.widgetAdd), findsWidgets);
    expect(find.byKey(const Key('widgetPreview')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('widgetMetric')));
    await tapAndSettle(tester, find.text(it.mSignal));
    await tapAndSettle(tester, find.byKey(const ValueKey('widgetViewsignal')));
    await tapAndSettle(tester, find.text(it.viewLine).last);
    await tapAndSettle(tester, find.byKey(const Key('widgetAgg')));
    await tapAndSettle(tester, find.text(it.aggMax).last);
    await tapAndSettle(tester, find.byKey(const ValueKey('widgetBucketsignalline')));
    await tapAndSettle(tester, find.text(it.groupHour).last);
    await tapAndSettle(tester, find.byKey(const Key('widgetPeriod')));
    await tapAndSettle(tester, find.text(it.periodLast7d).last);
    await tapAndSettle(tester, find.byKey(const Key('widgetAll')));
    // Only the trackers of the user
    expect(find.byKey(const Key('device_2')), findsNothing);
    expect(find.byKey(const Key('device_4')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));
    expect(find.text(it.widgetDevicesNeeded), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('device_1')));
    await tester.enterText(find.byKey(const Key('widgetTitle')), 'Segnale');
    await tapAndSettle(tester, find.descendant(of: find.byKey(const Key('widgetWidth')), matching: find.text('2')));
    await tapAndSettle(tester, find.descendant(of: find.byKey(const Key('widgetHeight')), matching: find.text('2')));
    await reveal(tester, find.byKey(const Key('widgetPreview')));
    expect(find.byType(TimeChart), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));
    expect(find.text('Segnale'), findsOneWidget);

    // Changed: the value of the current state has no period, no aggregation
    await tapAndSettle(tester, find.byKey(const Key('edit_b')));
    await tapAndSettle(tester, find.byKey(const Key('widgetMetric')));
    await tapAndSettle(tester, find.text(it.mOdometer));
    expect(find.byKey(const Key('widgetPeriod')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));
    expect(find.text(it.mOdometer), findsOneWidget);

    // Duplicated and removed from the menu, dragged in order
    await tapAndSettle(tester, find.byKey(const Key('menu_a')));
    await tapAndSettle(tester, find.text(it.widgetDuplicate));
    expect(find.text(it.mDistance), findsNWidgets(2));
    await tapAndSettle(tester, find.byKey(const Key('menu_b')));
    await tapAndSettle(tester, find.text(it.widgetRemove));
    expect(find.text(it.mOdometer), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('menu_a')));
    await tapAndSettle(tester, find.text(it.widgetEdit));
    await tapAndSettle(tester, find.byType(CloseButton));
    final drag = await tester.startGesture(tester.getCenter(find.byKey(const Key('drag_a'))));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 4; i++) {
      await drag.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await settle(tester);

    await tapAndSettle(tester, find.byKey(const Key('editSave')));
    final widgets = ((backend.lastBody('/api/dashboards/1', 'PUT')['layout'] as Map)['widgets'] as List).cast<Map<String, dynamic>>();
    expect(widgets.map((item) => item['metric']), ['distance', 'distance', 'signal']);
    expect(widgets.first['id'], isNot('a'));
    final signal = widgets.last;
    expect(signal, containsPair('agg', 'max'));
    expect(signal, containsPair('bucket', 'hour'));
    expect(signal, containsPair('period', '7d'));
    expect(signal, containsPair('devices', [1]));
    expect(signal, containsPair('title', 'Segnale'));
    expect(signal['height'], 2);
    expect(find.text(it.dashboardSaved), findsOneWidget);
    expect(find.byKey(const Key('editSave')), findsNothing);
  });

  testWidgets('editor: extra data field, custom period, status of shared vehicles; changes discarded', (tester) async {
    final backend = dashboardBackend(initial: [dashboardJson(1, 'Auto', [w('a', 'distance', 'number')])]);
    final app = TestApp(backend);
    await app.start(tester);
    await openDashboards(tester, app);
    await tapAndSettle(tester, find.byKey(const Key('dashboardEdit')));
    // Nothing changed: no question
    await tapAndSettle(tester, find.byKey(const Key('editCancel')));
    expect(find.byKey(const Key('editSave')), findsNothing);

    await tapAndSettle(tester, find.byKey(const Key('dashboardEdit')));
    await tapAndSettle(tester, find.byKey(const Key('widgetAdd')));
    await tapAndSettle(tester, find.byKey(const Key('widgetMetric')));
    await tapAndSettle(tester, find.text(it.mExtra));
    expect(find.byKey(const Key('widgetPreview')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));
    expect(find.text(it.widgetKeyNeeded), findsOneWidget);
    await tester.enterText(find.byKey(const Key('widgetKey')), 'rpm');
    await tester.pump(const Duration(milliseconds: 700));
    await settle(tester);
    await reveal(tester, find.byKey(const Key('widgetPreview')));
    expect(find.text('${it.mExtra} · rpm'), findsOneWidget);
    // A period of chosen dates
    await tapAndSettle(tester, find.byKey(const Key('widgetPeriod')));
    await tapAndSettle(tester, find.text(it.periodCustom).last);
    await tapAndSettle(tester, find.text('Salva').last);
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));

    // Status: the shared vehicles too, archived ones marked
    await tapAndSettle(tester, find.byKey(const Key('widgetAdd')));
    await tapAndSettle(tester, find.byKey(const Key('widgetMetric')));
    await tapAndSettle(tester, find.text(it.mStatus));
    await tapAndSettle(tester, find.byKey(const Key('widgetAll')));
    expect(find.byKey(const Key('device_2')), findsOneWidget);
    expect(find.text('Uno · ${it.archived}'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('device_2')));
    await tapAndSettle(tester, find.byKey(const Key('device_2')));
    await tapAndSettle(tester, find.byKey(const Key('device_4')));
    await tapAndSettle(tester, find.byKey(const Key('widgetSave')));
    expect(find.text(it.mStatus), findsOneWidget);

    // Leaving with changes asks first
    await tapAndSettle(tester, find.byKey(const Key('editCancel')));
    expect(find.text(it.dashboardDiscard), findsOneWidget);
    await tapAndSettle(tester, find.text(it.cancel));
    expect(find.byKey(const Key('editSave')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('editCancel')));
    await tapAndSettle(tester, find.byKey(const Key('discard')));
    expect(find.byKey(const Key('editSave')), findsNothing);
    expect(backend.calls('/api/dashboards/1', 'PUT'), isEmpty);
    expect(find.text(it.mStatus), findsNothing);
  });

  testWidgets('the editor opened on its own returns nothing when closed', (tester) async {
    final app = TestApp(dashboardBackend());
    await app.start(tester);
    final context = tester.element(find.byType(Scaffold).first);
    DashWidget? result = DashWidget(id: 'x', metric: 'distance', view: 'number');
    editWidget(context, '30d').then((value) => result = value).ignore();
    await settle(tester);
    expect(find.byType(WidgetEditor), findsOneWidget);
    await tapAndSettle(tester, find.byType(CloseButton));
    expect(result, isNull);
  });
  testWidgets('current dashboard: opened first, marked and unmarked', (tester) async {
    final backend = dashboardBackend(initial: [
      dashboardJson(1, 'Auto', [w('a', 'distance', 'number')]),
      {...dashboardJson(2, 'Diagnostica', [w('b', 'trips', 'number')]), 'current': true},
    ]);
    final app = TestApp(backend);
    await app.start(tester);
    await openDashboards(tester, app);
    expect(find.text('Diagnostica'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);

    // Another one marked: the first one no longer
    await tapAndSettle(tester, find.byKey(const Key('dashboardPicker')));
    expect(find.byIcon(Icons.star), findsNWidgets(2));
    await tapAndSettle(tester, find.text('Auto').last);
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardSetCurrent));
    expect(backend.lastBody('/api/dashboards/1/current', 'PUT'), {'current': true});
    expect(find.text(it.dashboardCurrentSet('Auto')), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardUnsetCurrent));
    expect(backend.lastBody('/api/dashboards/1/current', 'PUT'), {'current': false});
    expect(find.text(it.dashboardCurrentUnset), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('analysis of a vehicle: the current dashboard on it, or the standard one', (tester) async {
    final backend = dashboardBackend(initial: [
      {...dashboardJson(1, 'Mia', [w('a', 'distance', 'number', extra: {'devices': [4]}), w('b', 'signal', 'line', extra: {'period': '7d'})]), 'current': true},
    ])
      ..on('GET', '/api/devices/4', (_) => vehicleDevice());
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.tabAnalysis));
    expect(find.text('Mia'), findsOneWidget);
    expect(find.byKey(const Key('widget_a')), findsOneWidget);
    expect(find.byKey(const Key('widget_b')), findsOneWidget);
    // Every widget on this vehicle, in the period of the screen (its own when it has one)
    final body = backend.lastBody('/api/dashboards/data', 'POST');
    final widgets = (body['widgets'] as List).cast<Map<String, dynamic>>();
    expect([for (final item in widgets) item['devices']], [[1], [1]]);
    expect(widgets[1]['period'], '7d');
    expect((body['period'] as Map)['to'], day(0));
    expect((body['period'] as Map)['from'], day(-1));

    // The standard analysis and back
    await tapAndSettle(tester, find.byKey(const Key('analysisSwitch')));
    expect(find.byKey(const Key('openTrends')), findsOneWidget);
    expect(find.text(it.analysisStandard), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('analysisSwitch')));
    expect(find.byKey(const Key('openTrends')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('analysisOpenDashboard')));
    expect(find.byKey(const Key('dashboardMenu')), findsOneWidget);

    // A vehicle without a tracker: only the widgets of its values
    app.go(tester, '/devices/4');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.tabAnalysis));
    expect(find.byKey(const Key('widget_a')), findsOneWidget);
    expect(find.byKey(const Key('widget_b')), findsNothing);
  });

  testWidgets('analysis of a vehicle: no current dashboard, none of its widgets', (tester) async {
    final backend = dashboardBackend(initial: [dashboardJson(1, 'Mia', [w('a', 'signal', 'number')])])
      ..on('GET', '/api/devices/4', (_) => vehicleDevice());
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/4');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.tabAnalysis));
    expect(find.byKey(const Key('analysisSwitch')), findsNothing);
    expect(find.byKey(const Key('openCosts')), findsOneWidget);

    // Marked as current in the dashboards: the analysis follows
    app.go(tester, '/dashboards');
    await settle(tester);
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardSetCurrent));
    app.go(tester, '/devices/4');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.tabAnalysis));
    expect(find.text(it.analysisNoWidgets), findsOneWidget);
  });

  testWidgets('layouts sent to friends, received, used on own vehicles or declined', (tester) async {
    final shares = [
      {'id': 30, 'from': 'Luca', 'name': 'Flotta', 'layout': {'version': 1, 'period': '30d', 'widgets': [w('a', 'distance', 'number'), w('b', 'signal', 'line')]}, 'createdAt': iso(DateTime.now())},
      {'id': 31, 'from': 'Mario', 'name': 'Prova', 'layout': {'version': 1, 'period': '30d', 'widgets': [w('c', 'trips', 'number')]}, 'createdAt': iso(DateTime.now())},
    ];
    final backend = dashboardBackend(initial: [dashboardJson(1, 'Auto', [w('a', 'distance', 'number')])])
      ..on('GET', '/api/dashboards/shares', (_) => shares)
      ..on('POST', '/api/dashboards/shares/30/accept', (request) {
        shares.removeWhere((item) => item['id'] == 30);
        return dashboardJson(2, (jsonDecode(request.body) as Map)['name'] as String, [w('a', 'distance', 'number')]);
      })
      ..on('DELETE', '/api/dashboards/shares/31', (_) {
        shares.removeWhere((item) => item['id'] == 31);
        return {'ok': true};
      });
    final app = TestApp(backend);
    await app.start(tester);
    await openDashboards(tester, app);

    // Sent: only to a friend chosen
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardShare));
    expect(find.text(it.dashboardShareHint), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('shareTo_7')));
    expect(backend.lastBody('/api/dashboards/1/share', 'POST'), {'friendId': 7});
    expect(find.text(it.dashboardShared('Mario')), findsOneWidget);
    backend.on('POST', '/api/dashboards/1/share', (_) => Reply.error(400, 'too_many_dashboard_shares'));
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardShare));
    await tapAndSettle(tester, find.byKey(const Key('shareTo_5')));
    expect(find.text(it.errTooManyDashboardShares), findsOneWidget);

    // Received: used on the vehicles chosen
    expect(find.text(it.dashboardReceived('Luca', 'Flotta')), findsOneWidget);
    expect(find.text(it.dashboardReceivedWidgets(2)), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('use_30')));
    await tapAndSettle(tester, find.byKey(const Key('useAll')));
    await tapAndSettle(tester, find.byKey(const Key('useOk')));
    expect(find.text(it.dashboardUseNoVehicles), findsOneWidget);
    expect(find.byKey(const Key('use_device_2')), findsNothing);
    expect(find.byKey(const Key('use_device_5')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('use_device_4')));
    await tapAndSettle(tester, find.byKey(const Key('use_device_1')));
    await tapAndSettle(tester, find.byKey(const Key('use_device_4')));
    await tapAndSettle(tester, find.byKey(const Key('use_device_4')));
    await tester.enterText(find.byKey(const Key('useName')), '');
    await tapAndSettle(tester, find.byKey(const Key('useOk')));
    expect(backend.calls('/api/dashboards/shares/30/accept'), isEmpty);
    await tester.enterText(find.byKey(const Key('useName')), 'Da Luca');
    await tapAndSettle(tester, find.byKey(const Key('useOk')));
    expect(backend.lastBody('/api/dashboards/shares/30/accept', 'POST'), {'name': 'Da Luca', 'devices': [1, 4]});
    expect(find.text(it.dashboardAdded('Da Luca')), findsOneWidget);
    expect(find.text(it.dashboardReceived('Luca', 'Flotta')), findsNothing);

    // Used again (gone meanwhile), declined
    backend.on('DELETE', '/api/dashboards/shares/31', (_) => Reply.error(404, 'not_found'));
    await tapAndSettle(tester, find.byKey(const Key('decline_31')));
    expect(find.text(it.dashboardReceived('Mario', 'Prova')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('use_31')));
    await tapAndSettle(tester, find.byKey(const Key('useOk')));
    expect(backend.lastBody('/api/dashboards/shares/31/accept', 'POST'), {'name': 'Prova', 'devices': 'all'});
    backend.on('DELETE', '/api/dashboards/shares/31', (_) {
      shares.clear();
      return {'ok': true};
    });
    await tapAndSettle(tester, find.byKey(const Key('decline_31')));
    expect(find.byKey(const Key('received_31')), findsNothing);
    expect(find.text('Auto'), findsOneWidget);

    // Cancelled dialogs, no friends
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardShare));
    await tapAndSettle(tester, find.text(it.cancel));
    backend.on('GET', '/api/friends', (_) => {'code': 'ABCDE12345', 'friends': []});
    await tapAndSettle(tester, find.byKey(const Key('dashboardMenu')));
    await tapAndSettle(tester, find.text(it.dashboardShare));
    expect(find.byKey(const Key('shareNoFriends')), findsOneWidget);
  });

  testWidgets('a layout received while elsewhere in the app; received with no dashboards yet', (tester) async {
    final shares = [
      {'id': 30, 'from': 'Luca', 'name': 'Flotta', 'layout': {'version': 1, 'period': '30d', 'widgets': [w('a', 'distance', 'number')]}, 'createdAt': iso(DateTime.now())},
    ];
    final backend = dashboardBackend()
      ..on('GET', '/api/dashboards/shares', (_) => shares)
      ..on('POST', '/api/dashboards/shares/30/accept', (_) => Reply.error(400, 'too_many_dashboards'));
    final app = TestApp(backend);
    await app.start(tester);
    app.socket.emit({'type': 'dashboardShare', 'name': 'Luca', 'dashboard': 'Flotta'});
    await settle(tester);
    expect(find.text(it.dashboardReceived('Luca', 'Flotta')), findsOneWidget);
    await tester.tap(find.text(it.open));
    await settle(tester);
    expect(find.text(it.dashboardEmpty), findsOneWidget);
    expect(find.byKey(const Key('received_30')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('use_30')));
    await tapAndSettle(tester, find.text(it.cancel));
    await tapAndSettle(tester, find.byKey(const Key('use_30')));
    await tapAndSettle(tester, find.byKey(const Key('useOk')));
    expect(find.text(it.errTooManyDashboards), findsOneWidget);
  });
}
