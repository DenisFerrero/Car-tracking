import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/base_map.dart';
import '../../widgets/charts.dart';
import '../../widgets/track_layers.dart';

double? _num(dynamic value) => value == null ? null : (value as num).toDouble();

/// Analysis of the period: trips and distances, driving data, quality of LTE signal
/// and GNSS fix (also on a coverage map), vehicle battery, data used on the SIM.
class AnalysisTab extends ConsumerWidget {
  const AnalysisTab({super.key, required this.device, required this.period});

  final Device device;
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(analysisProvider(('trips', period)));
    // Phones: only the trips; vehicles fed by a phone: also the statistics (no modem data)
    final empty = AsyncValue.data(const <String, dynamic>{});
    final stats = device.isPhone ? empty : ref.watch(analysisProvider(('stats', period)));
    final distribution = device.isTracker ? ref.watch(analysisProvider(('distribution', period))) : empty;
    final coverage = device.isTracker ? ref.watch(analysisProvider(('coverage', period))) : empty;
    final traffic = device.isTracker ? ref.watch(analysisProvider(('traffic', period))) : empty;

    Widget section(AsyncValue<Map<String, dynamic>> value, List<Widget> Function(Map<String, dynamic>) builder) =>
        value.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (error, _) => Padding(padding: const EdgeInsets.all(16), child: Text(errorText(context.l10n, error))),
          data: (data) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: builder(data)),
        );

    return RefreshIndicator(
      onRefresh: () async {
        for (final endpoint in ['stats', 'trips', 'distribution', 'coverage', 'traffic']) {
          ref.invalidate(analysisProvider((endpoint, period)));
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // Pages of the device: statistics over time, costs, deadlines (trackers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              ActionChip(
                key: const Key('openTrends'),
                avatar: const Icon(Icons.bar_chart, size: 18),
                label: Text(context.l10n.trends),
                onPressed: () => context.push('/devices/${device.id}/trends'),
              ),
              ActionChip(
                key: const Key('openCosts'),
                avatar: const Icon(Icons.euro, size: 18),
                label: Text(context.l10n.tripCosts),
                onPressed: () => context.push('/devices/${device.id}/costs'),
              ),
              if (!device.isPhone)
                ActionChip(
                  key: const Key('openRefuels'),
                  avatar: const Icon(Icons.local_gas_station, size: 18),
                  label: Text(context.l10n.refuels),
                  onPressed: () => context.push('/devices/${device.id}/refuels'),
                ),
              if (!device.isPhone)
                ActionChip(
                  key: const Key('openMaintenance'),
                  avatar: const Icon(Icons.build, size: 18),
                  label: Text(context.l10n.maintenance),
                  onPressed: () => context.push('/devices/${device.id}/maintenance'),
                ),
              if (device.isTracker)
                ActionChip(
                  key: const Key('openExtra'),
                  avatar: const Icon(Icons.data_object, size: 18),
                  label: Text(context.l10n.extraData),
                  onPressed: () => context.push('/devices/${device.id}/extra'),
                ),
            ]),
          ),
          _ExportBar(period: period),
          section(trips, (data) => _trips(context, ref, data)),
          if (!device.isPhone) section(stats, (data) => _series(context, data)),
          if (device.isTracker) ...[
            section(distribution, (data) => _quality(context, data)),
            section(coverage, (data) => [_coverage(context, data)]),
            section(traffic, (data) => _traffic(context, data)),
          ],
        ],
      ),
    );
  }

  // --- Trips: totals, distance and driving time per day, list
  List<Widget> _trips(BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final l = context.l10n;
    final totals = data['totals'] as Map<String, dynamic>;
    final days = (data['days'] as List).cast<Map<String, dynamic>>();
    final trips = (data['trips'] as List).cast<Map<String, dynamic>>();
    final cost = totals['cost'] as Map<String, dynamic>?;
    return [
      _KpiGrid(children: [
        _Kpi(icon: Icons.route, label: l.kpiDistance, value: '${formatDecimal(_num(totals['distanceKm'])!, 1)} km'),
        _Kpi(icon: Icons.timer, label: l.kpiDriving, value: formatDuration(l, totals['drivingMin'] as int)),
        _Kpi(icon: Icons.speed, label: l.kpiMaxSpeed, value: '${totals['maxSpeed']} km/h'),
        _Kpi(icon: Icons.flag, label: l.kpiTrips, value: '${totals['trips']}'),
        // Costs when the owner entered consumption or wear
        if (cost?['cost'] != null)
          _Kpi(icon: Icons.euro, label: l.kpiCost, value: formatEuro(cost!['cost'] as num))
        else if (cost?['fuelL'] != null)
          _Kpi(icon: Icons.local_gas_station, label: l.kpiFuel, value: '${formatDecimal((cost!['fuelL'] as num).toDouble(), 1)} l'),
      ]),
      if (days.length > 1)
        ChartCard(
          title: l.kmPerDay,
          child: Bars(
            labels: [for (final d in days) (d['day'] as String).substring(5).split('-').reversed.join('/')],
            values: [for (final d in days) _num(d['distanceKm'])!],
            unit: ' km',
          ),
        ),
      if (days.length > 1)
        ChartCard(
          title: l.drivingPerDay,
          child: Bars(
            labels: [for (final d in days) (d['day'] as String).substring(5).split('-').reversed.join('/')],
            values: [for (final d in days) (d['drivingMin'] as int).toDouble()],
            unit: ' min',
            color: Colors.teal,
          ),
        ),
      if (trips.isNotEmpty)
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.list),
            title: Text(l.tripsList(trips.length)),
            children: [
              for (final trip in trips.reversed.take(100))
                ListTile(
                  dense: true,
                  leading: IconButton(
                    key: Key('tag${trip['start']}'),
                    tooltip: l.tripPurpose,
                    icon: Icon(switch (trip['purpose']) {
                      'business' => Icons.work,
                      'personal' => Icons.home,
                      _ => Icons.label_outline,
                    }),
                    onPressed: () => _tag(context, ref, trip),
                  ),
                  trailing: const Icon(Icons.map_outlined),
                  onTap: () => showTripMap(context, device, DateTime.parse(trip['start'] as String), DateTime.parse(trip['end'] as String)),
                  title: Text('${formatDayTime(DateTime.parse(trip['start'] as String).toLocal())} → '
                      '${formatTime(DateTime.parse(trip['end'] as String).toLocal())}'),
                  subtitle: Text([
                    l.tripDetail(
                      formatDecimal(_num(trip['distanceKm'])!, 1),
                      formatDuration(l, trip['durationMin'] as int),
                      '${trip['avgSpeed']}',
                      '${trip['maxSpeed']}',
                    ),
                    if (trip['cost'] != null) costText(l, trip['cost'] as Map<String, dynamic>),
                    if ((trip['note'] as String? ?? '').isNotEmpty) trip['note'] as String,
                  ].join('\n')),
                ),
            ],
          ),
        ),
    ];
  }

  /// Trip log: business or personal, with a note
  Future<void> _tag(BuildContext context, WidgetRef ref, Map<String, dynamic> trip) async {
    final result = await showDialog<({String? purpose, String note})>(
      context: context,
      builder: (_) => _TagDialog(purpose: trip['purpose'] as String?, note: trip['note'] as String? ?? ''),
    );
    if (result == null) return;
    try {
      await ref.read(apiProvider).put('/api/devices/${device.id}/trips/tag', {
        'start': trip['start'],
        'purpose': result.purpose,
        'note': result.note,
      });
      ref.invalidate(analysisProvider(('trips', period)));
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  // --- Time series
  List<Widget> _series(BuildContext context, Map<String, dynamic> data) {
    final l = context.l10n;
    final rows = (data['series'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [Card(child: Padding(padding: const EdgeInsets.all(24), child: Text(l.noData)))];
    double x(Map<String, dynamic> row) => DateTime.parse(row['bucket'] as String).millisecondsSinceEpoch.toDouble();
    List<FlSpot> spots(String key) => [
          for (final row in rows) row[key] == null ? FlSpot.nullSpot : FlSpot(x(row), _num(row[key])!),
        ];
    final bucket = {
          '2 minutes': l.bucket2m,
          '10 minutes': l.bucket10m,
          '1 hour': l.bucket1h,
          '6 hours': l.bucket6h,
          '1 day': l.bucket1d,
        }[data['bucket']] ??
        data['bucket'] as String;
    final from = period.from, to = period.to;
    final hasClimate = rows.any((row) => row['temperature'] != null);
    final hasVoltage = rows.any((row) => row['voltage'] != null);

    return [
      ChartCard(
        title: l.chartSpeed,
        subtitle: l.chartSpeedSub(bucket),
        child: TimeChart(from: from, to: to, unit: ' km/h', minY: 0, series: [
          Series(l.seriesMax, Colors.red, spots('max_speed')),
          Series(l.seriesAvgMoving, Colors.blue, spots('avg_speed'), area: true),
        ]),
      ),
      ChartCard(
        title: l.chartSignal,
        subtitle: l.chartSignalSub,
        child: TimeChart(
          from: from,
          to: to,
          unit: ' dBm',
          series: [
            Series(l.seriesAvg, Colors.indigo, spots('avg_signal')),
            Series(l.seriesMin, Colors.orange, spots('min_signal'), dashed: true),
          ],
          thresholds: [(y: -105, label: l.thresholdPoor, color: Colors.red)],
        ),
      ),
      ChartCard(
        title: l.chartSatellites,
        subtitle: l.chartSatellitesSub,
        child: TimeChart(
          from: from,
          to: to,
          minY: 0,
          series: [
            Series(l.seriesAvg, Colors.green, spots('avg_satellites')),
            Series(l.seriesMin, Colors.orange, spots('min_satellites'), dashed: true),
          ],
          thresholds: [(y: 6, label: l.thresholdWeakFix, color: Colors.orange)],
        ),
      ),
      ChartCard(
        title: l.chartAltitude,
        child: TimeChart(from: from, to: to, unit: ' m', series: [Series(l.chartAltitude, Colors.brown, spots('altitude'), area: true)]),
      ),
      if (hasVoltage)
        ChartCard(
          title: l.chartBattery,
          subtitle: l.chartBatterySub,
          child: TimeChart(
            from: from,
            to: to,
            unit: ' V',
            series: [
              Series(l.seriesAvg, Colors.teal, spots('voltage')),
              Series(l.seriesMin, Colors.red, spots('min_voltage'), dashed: true),
            ],
            thresholds: const [(y: 11.8, label: '11.8 V', color: Colors.red)],
          ),
        ),
      if (hasClimate)
        ChartCard(
          title: l.chartTemperature,
          child: TimeChart(from: from, to: to, unit: ' °C', series: [Series(l.chartTemperature, Colors.deepOrange, spots('temperature'))]),
        ),
      if (rows.any((row) => row['pressure'] != null))
        ChartCard(
          title: l.chartPressure,
          child: TimeChart(from: from, to: to, unit: ' hPa', series: [Series(l.chartPressure, Colors.blueGrey, spots('pressure'))]),
        ),
      ChartCard(
        title: l.chartPoints,
        subtitle: l.chartPointsSub,
        child: TimeChart(from: from, to: to, minY: 0, series: [
          Series(l.seriesPoints, Colors.blue, spots('points'), area: true),
          Series(l.seriesNoFix, Colors.red, spots('stale_points')),
        ]),
      ),
    ];
  }

  // --- Distributions and fix quality
  List<Widget> _quality(BuildContext context, Map<String, dynamic> data) {
    final l = context.l10n;
    final quality = data['quality'] as Map<String, dynamic>;
    final total = (quality['total'] as int).toDouble();
    if (total == 0) return const [];
    final stale = (quality['stale'] as int).toDouble();
    final weakFix = (quality['weak_fix'] as int).toDouble();
    final signal = (data['signal'] as List).cast<Map<String, dynamic>>();
    final satellites = (data['satellites'] as List).cast<Map<String, dynamic>>();
    final speed = (data['speed'] as List).cast<Map<String, dynamic>>();
    return [
      ChartCard(
        title: l.chartFixQuality,
        height: 150,
        child: Donut(items: [
          (label: l.fixGood, value: total - stale - weakFix, color: Colors.green),
          (label: l.fixWeak, value: weakFix, color: Colors.orange),
          (label: l.seriesNoFix, value: stale, color: Colors.red),
        ]),
      ),
      ChartCard(
        title: l.chartSignalDistribution,
        subtitle: l.weakSignalShare((quality['weak_signal'] as int) * 100 ~/ total),
        child: Bars(
          labels: [for (final row in signal) '${row['value']}'],
          values: [for (final row in signal) (row['count'] as int).toDouble()],
          colors: [for (final row in signal) signalQuality(l, row['value'] as int).color],
        ),
      ),
      ChartCard(
        title: l.chartSatelliteDistribution,
        child: Bars(
          labels: [for (final row in satellites) '${row['value']}'],
          values: [for (final row in satellites) (row['count'] as int).toDouble()],
          colors: [for (final row in satellites) satelliteQuality(l, row['value'] as int).color],
        ),
      ),
      if (speed.isNotEmpty)
        ChartCard(
          title: l.chartSpeedDistribution,
          subtitle: l.chartSpeedDistributionSub,
          child: Bars(
            labels: [for (final row in speed) '${row['value']}'],
            values: [for (final row in speed) (row['count'] as int).toDouble()],
            color: Colors.blue,
          ),
        ),
    ];
  }

  // --- Coverage map: grid of about 100 m colored by the average signal
  Widget _coverage(BuildContext context, Map<String, dynamic> data) {
    final l = context.l10n;
    final cells = (data['cells'] as List).cast<Map<String, dynamic>>();
    if (cells.isEmpty) return const SizedBox.shrink();
    return ChartCard(
      title: l.chartCoverage,
      subtitle: l.chartCoverageSub,
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BaseMap(
          fit: [for (final c in cells) LatLng(_num(c['lat'])!, _num(c['lon'])!)],
          layers: [
            CircleLayer(circles: [
              for (final c in cells)
                CircleMarker(
                  point: LatLng(_num(c['lat'])!, _num(c['lon'])!),
                  radius: 60,
                  useRadiusInMeter: true,
                  color: (c['avg_signal'] == null
                          ? Colors.grey
                          : signalQuality(l, c['avg_signal'] as int).color)
                      .withValues(alpha: 0.55),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  // --- Data on the SIM: per day and projection of the month against the plan
  List<Widget> _traffic(BuildContext context, Map<String, dynamic> data) {
    final l = context.l10n;
    final daily = (data['daily'] as List).cast<Map<String, dynamic>>();
    final budget = _num(data['budgetBytes'])!;
    final month = data['month'] as Map<String, dynamic>;
    final used = _num(month['estimatedBytes'])!;
    final projected = _num(month['projectedBytes'])!;
    final ratio = budget > 0 ? projected / budget : 0.0;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.simMonth, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (used / budget).clamp(0, 1),
              minHeight: 10,
              color: ratio > 1 ? Colors.red : (ratio > 0.8 ? Colors.orange : Colors.green),
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 8),
            Text(l.simUsed(formatBytes(used), formatBytes(budget), formatBytes(projected), (ratio * 100).round())),
            Text(l.simEstimate, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      if (daily.isNotEmpty)
        ChartCard(
          title: l.dataPerDay,
          subtitle: l.dataPerDaySub,
          child: Bars(
            labels: [for (final d in daily) (d['day'] as String).substring(5).split('-').reversed.join('/')],
            values: [for (final d in daily) _num(d['estimatedBytes'])! / 1024],
            unit: ' KB',
            color: Colors.purple,
            limit: budget / 30 / 1024,
            limitLabel: l.budget,
          ),
        ),
    ];
  }
}

/// Tiles in 2 or more columns that fill the width
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 6);
        return Wrap(children: [
          for (final child in children) SizedBox(width: constraints.maxWidth / columns, child: child),
        ]);
      });
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(value, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(label),
      ),
    );
  }
}

/// Files of the period: GPX (a track per trip, for maps and navigation apps) or CSV
/// (every point, for spreadsheets)
class _ExportBar extends ConsumerStatefulWidget {
  const _ExportBar({required this.period});

  final Period period;

  @override
  ConsumerState<_ExportBar> createState() => _ExportBarState();
}

class _ExportBarState extends ConsumerState<_ExportBar> {
  bool _busy = false;

  Future<void> _export(String format) async {
    setState(() => _busy = true);
    try {
      if (format == 'logbook') {
        // Month of the end of the period
        final to = widget.period.to.toLocal();
        await downloadFile(ref, '/api/devices/${widget.period.deviceId}/logbook', 'text/csv',
            {'month': '${to.year}-${to.month.toString().padLeft(2, '0')}'});
        return;
      }
      await downloadFile(ref, '/api/devices/${widget.period.deviceId}/export', format == 'gpx' ? 'application/gpx+xml' : 'text/csv',
          {...periodQuery(widget.period), 'format': format});
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.download),
          title: Text(l.exportPeriod),
          subtitle: Text(l.exportHint),
          trailing: Wrap(spacing: 4, children: [
            OutlinedButton(onPressed: _busy ? null : () => _export('gpx'), child: const Text('GPX')),
            OutlinedButton(onPressed: _busy ? null : () => _export('csv'), child: const Text('CSV')),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long),
          title: Text(l.logbook),
          subtitle: Text(l.logbookHint),
          trailing: OutlinedButton(
            key: const Key('exportLogbook'),
            onPressed: _busy ? null : () => _export('logbook'),
            child: const Text('CSV'),
          ),
        ),
      ]),
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.purpose, required this.note});

  final String? purpose;
  final String note;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late String? _purpose = widget.purpose;
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.tripPurpose),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          key: const Key('purpose'),
          segments: [
            ButtonSegment(value: 'business', label: Text(l.purposeBusiness), icon: const Icon(Icons.work)),
            ButtonSegment(value: 'personal', label: Text(l.purposePersonal), icon: const Icon(Icons.home)),
            ButtonSegment(value: 'none', label: Text(l.purposeNone)),
          ],
          selected: {_purpose ?? 'none'},
          onSelectionChanged: (selection) => setState(() => _purpose = selection.first == 'none' ? null : selection.first),
        ),
        TextField(
          key: const Key('tripNote'),
          controller: _note,
          maxLength: 200,
          decoration: InputDecoration(labelText: l.tripNote),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          key: const Key('tagSave'),
          onPressed: () => Navigator.pop(context, (purpose: _purpose, note: _note.text.trim())),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Track of a trip on a map, in a sheet
void showTripMap(BuildContext context, Device device, DateTime start, DateTime end) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: _TripMap(period: (deviceId: device.id, from: start, to: end), color: device.color),
    ),
  );
}

class _TripMap extends ConsumerWidget {
  const _TripMap({required this.period, required this.color});

  final Period period;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ref.watch(positionsProvider(period)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(errorText(l, error))),
          data: (data) {
            final points = [for (final p in data.positions) if (p.point != null) p.point!];
            if (points.isEmpty) return Center(child: Text(l.noPositions));
            return Column(children: [
              ListTile(
                title: Text('${formatDayTime(period.from.toLocal())} → ${formatTime(period.to.toLocal())}'),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ),
              Expanded(
                child: BaseMap(
                  fit: points,
                  center: points.length == 1 ? points.first : null,
                  layers: [
                    PolylineLayer(polylines: trackPolylines(data.positions, TrackColoring.plain, color)),
                    MarkerLayer(markers: [
                      Marker(point: points.first, child: const Icon(Icons.trip_origin, color: Colors.green)),
                      Marker(point: points.last, child: const Icon(Icons.flag, color: Colors.red)),
                    ]),
                  ],
                ),
              ),
            ]);
          },
        );
  }
}
