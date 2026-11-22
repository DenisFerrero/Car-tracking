import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../widgets/charts.dart';

final trendsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/trends') as Map<String, dynamic>,
);

double _num(dynamic value) => (value as num).toDouble();

/// Trend of a device over months or weeks: km (business / personal from the trip log),
/// driving hours, trips; trackers also health of the car battery, data on the SIM, alarms.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  bool _weeks = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.trends)),
      body: ref.watch(trendsProvider(widget.deviceId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(errorText(l, error))),
            data: (data) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(trendsProvider(widget.deviceId)),
              child: _content(context, data),
            ),
          ),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final l = context.l10n;
    final rows = (data[_weeks ? 'weeks' : 'months'] as List).cast<Map<String, dynamic>>();
    final battery = data['battery'] as Map<String, dynamic>?;
    final budget = data['simBudgetBytes'] as num?;
    final labels = [
      for (final row in rows)
        _weeks
            ? (row['period'] as String).substring(5).split('-').reversed.join('/')
            : DateFormat('MMM yy').format(DateTime.parse('${row['period']}-01')),
    ];
    List<double> values(String key, [double scale = 1]) => [for (final row in rows) _num(row[key]) / scale];
    final business = rows.fold<double>(0, (sum, row) => sum + _num(row['businessKm']));
    final personal = rows.fold<double>(0, (sum, row) => sum + _num(row['personalKm']));

    return ListView(padding: readable(context, const EdgeInsets.all(8)), children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<bool>(
          key: const Key('trendsPeriod'),
          segments: [
            ButtonSegment(value: false, label: Text(l.trendsMonths)),
            ButtonSegment(value: true, label: Text(l.trendsWeeks)),
          ],
          selected: {_weeks},
          onSelectionChanged: (selection) => setState(() => _weeks = selection.first),
        ),
      ),
      if (battery != null) _BatteryCard(battery: battery),
      ChartCard(
        title: l.trendsKm,
        subtitle: business + personal > 0 ? l.trendsKmSplit(business.toStringAsFixed(0), personal.toStringAsFixed(0)) : null,
        child: Bars(labels: labels, values: values('distanceKm'), unit: ' km'),
      ),
      ChartCard(
        title: l.trendsDriving,
        child: Bars(labels: labels, values: values('drivingMin', 60), unit: ' h', color: Colors.teal),
      ),
      ChartCard(
        title: l.trendsTrips,
        child: Bars(labels: labels, values: values('trips'), color: Colors.indigo),
      ),
      if (budget != null) ...[
        ChartCard(
          title: l.trendsSim,
          child: Bars(
            labels: labels,
            values: values('trafficBytes', 1024 * 1024),
            unit: ' MB',
            color: Colors.purple,
            // Weeks: a quarter of the monthly plan, about
            limit: _weeks ? budget / 1024 / 1024 * 7 / 30 : budget / 1024 / 1024,
            limitLabel: l.budget,
          ),
        ),
        ChartCard(
          title: l.trendsAlarms,
          child: Bars(labels: labels, values: values('alarms'), color: Colors.red),
        ),
      ],
    ]);
  }
}

/// State of the car battery from the resting voltage, chart of the last 90 days
class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.battery});

  final Map<String, dynamic> battery;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final average = battery['average'] as num?;
    final trend = battery['trendPerMonth'] as num?;
    final value = average == null ? '' : formatDecimal(average.toDouble(), 2);
    final (text, color, icon) = switch (battery['state']) {
      'good' => (l.batteryGood(value), Colors.green, Icons.battery_full),
      'fair' => (l.batteryFair(value), Colors.orange, Icons.battery_4_bar),
      'low' => (l.batteryLow(value), Colors.red, Icons.battery_1_bar),
      _ => (l.batteryUnknown, Colors.grey, Icons.battery_unknown),
    };
    final days = (battery['days'] as List).cast<Map<String, dynamic>>();
    final spots = [
      for (final day in days)
        if (day['restVoltage'] != null) FlSpot(DateTime.parse(day['day'] as String).millisecondsSinceEpoch.toDouble(), _num(day['restVoltage'])),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: ListTile(
          key: const Key('batteryHealth'),
          leading: Icon(icon, color: color),
          title: Text(l.batteryHealth),
          subtitle: Text([text, if (trend != null) l.batteryTrend(formatDecimal(trend.toDouble(), 2))].join('\n')),
        ),
      ),
      if (spots.length > 1)
        ChartCard(
          title: l.trendsVoltage,
          subtitle: l.trendsVoltageSub,
          child: TimeChart(
            from: DateTime.parse(days.first['day'] as String),
            to: DateTime.parse(days.last['day'] as String),
            unit: ' V',
            series: [Series(l.trendsVoltage, Colors.teal, spots)],
            thresholds: [
              (y: _num(battery['good']), label: '${battery['good']} V', color: Colors.green),
              (y: _num(battery['low']), label: '${battery['low']} V', color: Colors.red),
            ],
          ),
        ),
    ]);
  }
}
