import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';

/// Card with a title and a chart
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.child, this.subtitle, this.height = 200});

  final String title;
  final String? subtitle;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ]),
      ),
    );
  }
}

class Series {
  const Series(this.label, this.color, this.points, {this.dashed = false, this.area = false});

  final String label;
  final Color color;

  /// x = milliseconds since epoch
  final List<FlSpot> points;
  final bool dashed;
  final bool area;
}

/// Line chart over time; the gaps (null values) break the line
class TimeChart extends StatelessWidget {
  const TimeChart({
    super.key,
    required this.series,
    required this.from,
    required this.to,
    this.unit = '',
    this.minY,
    this.maxY,
    this.thresholds = const [],
  });

  final List<Series> series;
  final DateTime from;
  final DateTime to;
  final String unit;
  final double? minY;
  final double? maxY;

  /// Reference lines, e.g. the minimum battery voltage
  final List<({double y, String label, Color color})> thresholds;

  @override
  Widget build(BuildContext context) {
    final values = [for (final s in series) for (final p in s.points) if (!p.isNull()) p.y];
    if (values.isEmpty) return Center(child: Text(context.l10n.noData));
    final span = to.difference(from);
    final format = span.inHours <= 26 ? DateFormat('HH:mm', 'it') : DateFormat('d/M', 'it');
    final low = minY ?? values.reduce(math.min);
    final high = maxY ?? values.reduce(math.max);
    final pad = (high - low).abs() < 1e-6 ? 1.0 : (high - low) * 0.1;
    final theme = Theme.of(context);

    return Column(children: [
      Expanded(
        child: LineChart(LineChartData(
          minX: from.millisecondsSinceEpoch.toDouble(),
          maxX: to.millisecondsSinceEpoch.toDouble(),
          minY: minY ?? low - pad,
          maxY: maxY ?? high + pad,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor.withValues(alpha: 0.3), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            for (final t in thresholds)
              HorizontalLine(
                y: t.y,
                color: t.color,
                strokeWidth: 1,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: TextStyle(color: t.color, fontSize: 10),
                  labelResolver: (_) => t.label,
                ),
              ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              axisNameWidget: unit.trim().isEmpty ? null : Text(unit.trim(), style: const TextStyle(fontSize: 10)),
              axisNameSize: unit.trim().isEmpty ? 0 : 14,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: _axisLabel,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                // Days on the axis: at least one day apart, or the same day comes back
                interval: math.max(span.inMilliseconds / 5, span.inHours <= 26 ? 60000 : 86400000).toDouble(),
                getTitlesWidget: (value, meta) => value == meta.min || value == meta.max
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(format.format(DateTime.fromMillisecondsSinceEpoch(value.round())),
                            style: const TextStyle(fontSize: 10)),
                      ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${series[spot.barIndex].label}: ${_number(spot.y)}$unit\n'
                    '${DateFormat('d/M HH:mm', 'it').format(DateTime.fromMillisecondsSinceEpoch(spot.x.round()))}',
                    TextStyle(color: series[spot.barIndex].color, fontSize: 11),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: s.points,
                color: s.color,
                barWidth: 2,
                isCurved: false,
                dotData: FlDotData(show: s.points.where((p) => !p.isNull()).length < 3),
                dashArray: s.dashed ? [4, 3] : null,
                belowBarData: BarAreaData(show: s.area, color: s.color.withValues(alpha: 0.15)),
              ),
          ],
        )),
      ),
      if (series.length > 1) Legend(items: [for (final s in series) (label: s.label, color: s.color)]),
    ]);
  }
}

/// Value on the Y axis, the unit is the axis name. The min and max of the data are
/// left out when they are not on the grid (e.g. 59.4 over 40 and 20)
Widget _axisLabel(double value, TitleMeta meta) {
  final onGrid = (value / meta.appliedInterval - (value / meta.appliedInterval).round()).abs() < 1e-6;
  if (!onGrid && (value == meta.min || value == meta.max)) return const SizedBox.shrink();
  final interval = meta.appliedInterval;
  final text = interval >= 1 ? _number(value) : formatDecimal(value, interval >= 0.1 ? 1 : 2);
  return SideTitleWidget(meta: meta, child: Text(text, style: const TextStyle(fontSize: 10)));
}

String _number(double value) {
  if (value.abs() >= 100 || value == value.roundToDouble()) return value.round().toString();
  return formatDecimal(value, 1);
}

class Legend extends StatelessWidget {
  const Legend({super.key, required this.items});

  final List<({String label, Color color})> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 16, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final item in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: item.color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(item.label, style: const TextStyle(fontSize: 11)),
          ]),
      ]),
    );
  }
}

/// Vertical bars: histograms and daily totals
class Bars extends StatelessWidget {
  const Bars({
    super.key,
    required this.labels,
    required this.values,
    this.colors,
    this.color,
    this.unit = '',
    this.limit,
    this.limitLabel,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color>? colors;
  final Color? color;
  final String unit;

  /// Horizontal reference, e.g. the daily SIM budget
  final double? limit;
  final String? limitLabel;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return Center(child: Text(context.l10n.noData));
    final theme = Theme.of(context);
    final high = math.max(values.reduce(math.max), limit ?? 0);
    final step = math.max(1, (labels.length / 8).ceil());
    return BarChart(BarChartData(
      maxY: high <= 0 ? 1 : high * 1.15,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor.withValues(alpha: 0.3), strokeWidth: 1),
      ),
      extraLinesData: limit == null
          ? null
          : ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: limit!,
                color: Colors.red,
                strokeWidth: 1,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: limitLabel != null,
                  alignment: Alignment.topRight,
                  style: const TextStyle(color: Colors.red, fontSize: 10),
                  labelResolver: (_) => limitLabel ?? '',
                ),
              ),
            ]),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          axisNameWidget: unit.trim().isEmpty ? null : Text(unit.trim(), style: const TextStyle(fontSize: 10)),
          axisNameSize: unit.trim().isEmpty ? 0 : 14,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: _axisLabel,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 || index >= labels.length || index % step != 0) return const SizedBox.shrink();
              return SideTitleWidget(meta: meta, child: Text(labels[index], style: const TextStyle(fontSize: 10)));
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            '${labels[group.x]}: ${_number(rod.toY)}$unit',
            const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: values[i],
              color: colors?[i] ?? color ?? theme.colorScheme.primary,
              width: math.max(4, math.min(24, 240 / values.length)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]),
      ],
    ));
  }
}

/// Bars of more series side by side (a series per vehicle), with a legend
class GroupedBars extends StatelessWidget {
  const GroupedBars({super.key, required this.labels, required this.series, this.unit = ''});

  final List<String> labels;

  /// Values aligned with the labels, null = no value
  final List<({String label, Color color, List<double?> values})> series;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = [for (final s in series) for (final v in s.values) ?v];
    if (values.isEmpty) return Center(child: Text(context.l10n.noData));
    final theme = Theme.of(context);
    final high = values.reduce(math.max);
    final step = math.max(1, (labels.length / 8).ceil());
    final width = math.max(2.0, math.min(16.0, 200 / labels.length / series.length));
    return Column(children: [
      Expanded(
        child: BarChart(BarChartData(
          maxY: high <= 0 ? 1 : high * 1.15,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor.withValues(alpha: 0.3), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              axisNameWidget: unit.trim().isEmpty ? null : Text(unit.trim(), style: const TextStyle(fontSize: 10)),
              axisNameSize: unit.trim().isEmpty ? 0 : 14,
              sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: _axisLabel),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= labels.length || index % step != 0) return const SizedBox.shrink();
                  return SideTitleWidget(meta: meta, child: Text(labels[index], style: const TextStyle(fontSize: 10)));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${series[rodIndex].label} · ${labels[group.x]}: ${_number(rod.toY)}$unit',
                const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < labels.length; i++)
              BarChartGroupData(x: i, barsSpace: 1, barRods: [
                for (final s in series)
                  BarChartRodData(
                    toY: s.values[i] ?? 0,
                    color: s.color,
                    width: width,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
              ]),
          ],
        )),
      ),
      if (series.length > 1) Legend(items: [for (final s in series) (label: s.label, color: s.color)]),
    ]);
  }
}

/// Donut with the shares and a legend
class Donut extends StatelessWidget {
  const Donut({super.key, required this.items});

  final List<({String label, double value, Color color})> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.value);
    if (total <= 0) return Center(child: Text(context.l10n.noData));
    return Row(children: [
      Expanded(
        child: PieChart(PieChartData(
          centerSpaceRadius: 36,
          sectionsSpace: 2,
          sections: [
            for (final item in items)
              if (item.value > 0)
                PieChartSectionData(
                  value: item.value,
                  color: item.color,
                  radius: 36,
                  title: '${(item.value / total * 100).round()}%',
                  titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                ),
          ],
        )),
      ),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Container(width: 12, height: 12, color: item.color),
              const SizedBox(width: 6),
              Text('${item.label} (${item.value.round()})', style: const TextStyle(fontSize: 12)),
            ]),
          ),
      ]),
    ]);
  }
}
