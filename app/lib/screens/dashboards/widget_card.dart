import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/base_map.dart';
import '../../widgets/charts.dart';
import 'catalog.dart';

/// Values of some widgets, by widget id: the key is the JSON of the request
final dashboardDataProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, body) async {
  final data = await ref.watch(apiProvider).post('/api/dashboards/data', jsonDecode(body)) as Map<String, dynamic>;
  return data['results'] as Map<String, dynamic>;
});

String dataRequest(Object period, List<DashWidget> widgets) =>
    jsonEncode({'period': period, 'widgets': [for (final w in widgets) w.toJson()]});

/// Height of a row of the grid
const rowHeight = 150.0;
const gap = 8.0;

/// Positions of the widgets on a grid of some columns: each one in order, where its
/// columns are lowest (skyline), so the grid has no holes left by wide widgets
List<({int column, int row, int width, int height})> packGrid(List<DashWidget> widgets, int columns) {
  final heights = List.filled(columns, 0);
  return [
    for (final w in widgets)
      () {
        final width = math.min(w.width, columns);
        var best = 0, top = 1 << 30;
        for (var c = 0; c + width <= columns; c++) {
          final row = heights.sublist(c, c + width).reduce(math.max);
          if (row < top) (best, top) = (c, row);
        }
        for (var c = best; c < best + width; c++) {
          heights[c] = top + w.height;
        }
        return (column: best, row: top, width: width, height: w.height);
      }(),
  ];
}

/// Columns of the grid for a width: 2 on a phone, up to 8 on a wide screen
int gridColumns(double width) => (width / 190).floor().clamp(2, 8);

/// The widgets of a dashboard on a grid that follows the width of the screen
class DashboardGrid extends ConsumerWidget {
  const DashboardGrid({super.key, required this.period, required this.widgets});

  final Object period;
  final List<DashWidget> widgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider(dataRequest(period, widgets)));
    return LayoutBuilder(builder: (context, constraints) {
      final columns = gridColumns(constraints.maxWidth);
      final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final places = packGrid(widgets, columns);
      final rows = places.fold(0, (max, p) => math.max(max, p.row + p.height));
      return SizedBox(
        height: rows * (rowHeight + gap),
        child: Stack(children: [
          for (var i = 0; i < widgets.length; i++)
            Positioned(
              left: places[i].column * (cell + gap),
              top: places[i].row * (rowHeight + gap),
              width: places[i].width * cell + (places[i].width - 1) * gap,
              height: places[i].height * rowHeight + (places[i].height - 1) * gap,
              child: WidgetCard(
                widget: widgets[i],
                result: data.whenData((results) => results[widgets[i].id] as Map<String, dynamic>?),
              ),
            ),
        ]),
      );
    });
  }
}

/// A widget: title, values of the result, devices no longer available
class WidgetCard extends ConsumerWidget {
  const WidgetCard({super.key, required this.widget, required this.result});

  final DashWidget widget;
  final AsyncValue<Map<String, dynamic>?> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final value = result.value;
    final devices = (value?['devices'] as List? ?? const []).cast<Map<String, dynamic>>();
    final unavailable = (value?['unavailable'] as List? ?? const []).length;
    final subtitle = [
      if (devices.length == 1) devices.first['name'] as String else if (devices.length > 1) l.widgetVehicles(devices.length),
      if (widget.info.sampled) aggLabel(l, widget.agg ?? 'avg'),
      if (widget.period != null && widget.info.hasPeriod) periodLabel(l, widget.period!),
    ].join(' · ');

    return Card(
      key: Key('widget_${widget.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.info.icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.titleOf(l), style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Expanded(
            child: result.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(errorText(l, error), textAlign: TextAlign.center)),
              data: (data) => _body(context, ref, data, devices),
            ),
          ),
          if (unavailable > 0)
            Text(
              l.widgetUnavailable(unavailable),
              key: Key('unavailable_${widget.id}'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Map<String, dynamic>? data, List<Map<String, dynamic>> devices) {
    final l = context.l10n;
    Widget message(String text) => Center(child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall));
    if (data == null) return message(l.noData);
    if (data['status'] == 'error') {
      return message(data['error'] == 'period_too_long' ? l.widgetPeriodTooLong : data['error'] as String);
    }
    if (devices.isEmpty) return message(l.widgetNoDevices);
    final info = widget.info;
    final names = {for (final d in devices) d['id'] as int: d['name'] as String};
    final colors = {for (final d in devices) d['id'] as int: parseColor(d['color'] as String?)};
    String format(num? value) => value == null ? '—' : info.format(l, value.toDouble());

    switch (info.source) {
      case Source.status:
        return _Status(ids: [for (final d in devices) d['id'] as int], map: widget.view == 'map');
      case Source.deadlines:
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        if (items.isEmpty) return message(l.widgetNoDeadlines);
        return ListView(padding: EdgeInsets.zero, children: [
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 12, color: switch (item['state']) {
                'due' => Colors.red,
                'soon' => Colors.orange,
                _ => Colors.green,
              }),
              title: Text('${names[item['deviceId']]} · ${(item['title'] as String).isEmpty ? maintenanceKindLabel(l, item['kind'] as String) : item['title']}'),
              subtitle: Text(remainingText(l, item['remainingDays'] as int?, item['remainingKm'] as int?)),
              onTap: () => context.push('/devices/${item['deviceId']}/maintenance'),
            ),
        ]);
      default:
        break;
    }

    switch (widget.view) {
      case 'number':
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(format(data['value'] as num?), style: Theme.of(context).textTheme.headlineMedium),
          ),
        );
      case 'table':
        final values = (data['values'] as List).cast<Map<String, dynamic>>();
        return ListView(padding: EdgeInsets.zero, children: [
          for (final item in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: colors[item['deviceId']]),
                const SizedBox(width: 6),
                Expanded(child: Text(names[item['deviceId']]!, overflow: TextOverflow.ellipsis)),
                Text(format(item['value'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ]);
      case 'vehicles':
        final values = (data['values'] as List).cast<Map<String, dynamic>>();
        return Bars(
          labels: [for (final item in values) names[item['deviceId']]!],
          values: [for (final item in values) ((item['value'] as num?) ?? 0) / info.chartScale],
          colors: [for (final item in values) colors[item['deviceId']]!],
          unit: info.chartUnit,
        );
      default:
        return _overTime(context, data, names, colors);
    }
  }

  /// Line or bars over time, a series per device
  Widget _overTime(BuildContext context, Map<String, dynamic> data, Map<int, String> names, Map<int, Color> colors) {
    final info = widget.info;
    final series = (data['series'] as List).cast<Map<String, dynamic>>();
    double? valueOf(dynamic point) => (point as List)[1] == null ? null : (point[1] as num) / info.chartScale;
    DateTime timeOf(dynamic point) => DateTime.parse((point as List)[0] as String).toLocal();
    if (widget.view == 'line') {
      final from = DateTime.parse(data['from'] as String);
      final end = DateTime.parse(data['to'] as String).add(const Duration(days: 1));
      return TimeChart(
        from: from,
        to: end.isAfter(DateTime.now()) ? DateTime.now() : end,
        unit: info.chartUnit,
        series: [
          for (final s in series)
            Series(names[s['deviceId']]!, colors[s['deviceId']]!, [
              for (final p in s['points'] as List)
                valueOf(p) == null ? FlSpot.nullSpot : FlSpot(timeOf(p).millisecondsSinceEpoch.toDouble(), valueOf(p)!),
            ]),
        ],
      );
    }
    final times = <DateTime>{for (final s in series) for (final p in s['points'] as List) timeOf(p)}.toList()..sort();
    final label = switch (data['bucket']) {
      '1 month' => DateFormat('MMM yy'),
      '1 day' || '1 week' => DateFormat('d/M'),
      '1 hour' || '6 hours' => DateFormat('d/M HH'),
      _ => DateFormat('HH:mm'),
    };
    return GroupedBars(
      labels: [for (final t in times) label.format(t)],
      unit: info.chartUnit,
      series: [
        for (final s in series)
          (
            label: names[s['deviceId']]!,
            color: colors[s['deviceId']]!,
            values: () {
              final byTime = {for (final p in s['points'] as List) timeOf(p): valueOf(p)};
              return [for (final t in times) byTime[t]];
            }(),
          ),
      ],
    );
  }
}

/// Position and state of the devices, from the list of the devices of the user
class _Status extends ConsumerWidget {
  const _Status({required this.ids, required this.map});

  final List<int> ids;
  final bool map;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final all = ref.watch(devicesProvider).value ?? const <Device>[];
    final devices = [for (final d in all) if (ids.contains(d.id)) d];
    final offlineAfter = Duration(minutes: ((ref.read(sessionProvider).config?.offlineAfterHours ?? 9) * 60).round());
    if (map) {
      final located = [for (final d in devices) if (d.lastPosition?.point != null) d];
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BaseMap(
          fit: [for (final d in located) d.lastPosition!.point!],
          center: located.length == 1 ? located.first.lastPosition!.point : null,
          layers: [
            MarkerLayer(markers: [
              for (final d in located)
                Marker(
                  point: d.lastPosition!.point!,
                  width: 40,
                  height: 40,
                  child: DeviceMarker(device: d, onTap: () => context.go('/devices/${d.id}')),
                ),
            ]),
          ],
        ),
      );
    }
    final now = DateTime.now();
    return ListView(padding: EdgeInsets.zero, children: [
      for (final d in devices)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.circle, size: 12, color: d.color),
          title: Text(d.name),
          subtitle: Text('${switch (d.stateAt(now, offlineAfter)) {
            DeviceState.moving => l.filterMoving,
            DeviceState.parked => l.filterParked,
            DeviceState.offline => l.filterOffline,
          }} · ${formatAgo(l, d.lastSeenAt, now)}'),
          onTap: () => context.go('/devices/${d.id}'),
        ),
    ]);
  }
}
