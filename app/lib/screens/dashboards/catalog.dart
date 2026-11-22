import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../l10n/app_localizations.dart';

/// Catalog of the metrics of the dashboards, the same as the backend
/// (src/services/metrics.ts): a new value of the platform (sensor, daily total, cost)
/// gets its entry in both, with its texts and tests.

enum Source { days, costs, positions, extra, odometer, deadlines, status }

const _all = {'tracker', 'vehicle', 'phone'};
const _cars = {'tracker', 'vehicle'};
const _trackers = {'tracker'};

class MetricInfo {
  const MetricInfo(this.key, this.source, this.kinds, this.icon, this.label, this.format, {this.chartUnit = '', this.chartScale = 1});

  final String key;
  final Source source;

  /// Kinds of device with this value
  final Set<String> kinds;
  final IconData icon;
  final String Function(AppLocalizations l) label;

  /// Value with its unit
  final String Function(AppLocalizations l, double value) format;

  /// Unit and divisor on the axes of the charts
  final String chartUnit;
  final double chartScale;

  bool get sampled => source == Source.positions || source == Source.extra;
  bool get daily => source == Source.days || source == Source.costs;

  /// Values of a period (not the current state)
  bool get hasPeriod => sampled || daily;

  List<String> get views => switch (source) {
        Source.odometer => const ['number', 'vehicles', 'table'],
        Source.deadlines => const ['list'],
        Source.status => const ['map', 'list'],
        _ => const ['number', 'line', 'bars', 'vehicles', 'table'],
      };

  /// Viewers of a share see only the status
  bool get ownerOnly => source != Source.status;
}

String _km(AppLocalizations l, double v) => '${formatDecimal(v, v >= 100 ? 0 : 1)} km';
String _euro(AppLocalizations l, double v) => formatEuro(v);
String _plain(AppLocalizations l, double v) => v == v.roundToDouble() ? formatInt(v.round()) : formatDecimal(v, 2);
String Function(AppLocalizations, double) _unit(String unit, [int digits = 0]) =>
    (l, v) => '${digits == 0 ? formatInt(v.round()) : formatDecimal(v, digits)} $unit';

final metrics = <MetricInfo>[
  MetricInfo('distance', Source.days, _all, Icons.route, (l) => l.mDistance, _km, chartUnit: ' km'),
  MetricInfo('businessKm', Source.days, _all, Icons.work, (l) => l.mBusinessKm, _km, chartUnit: ' km'),
  MetricInfo('personalKm', Source.days, _all, Icons.home, (l) => l.mPersonalKm, _km, chartUnit: ' km'),
  MetricInfo('driving', Source.days, _all, Icons.timer, (l) => l.mDriving, (l, v) => formatDuration(l, v.round()),
      chartUnit: ' h', chartScale: 60),
  MetricInfo('trips', Source.days, _all, Icons.flag, (l) => l.mTrips, _plain),
  MetricInfo('maxSpeed', Source.days, _all, Icons.speed, (l) => l.mMaxSpeed, _unit('km/h'), chartUnit: ' km/h'),
  MetricInfo('alarms', Source.days, _trackers, Icons.warning_amber, (l) => l.mAlarms, _plain),
  MetricInfo('traffic', Source.days, _trackers, Icons.sim_card, (l) => l.mTraffic, (l, v) => formatBytes(v),
      chartUnit: ' MB', chartScale: 1024 * 1024),
  MetricInfo('restVoltage', Source.days, _trackers, Icons.battery_charging_full, (l) => l.mRestVoltage, _unit('V', 2),
      chartUnit: ' V'),
  MetricInfo('cost', Source.costs, _all, Icons.euro, (l) => l.mCost, _euro, chartUnit: ' €'),
  MetricInfo('fuelCost', Source.costs, _all, Icons.local_gas_station, (l) => l.mFuelCost, _euro, chartUnit: ' €'),
  MetricInfo('wearCost', Source.costs, _all, Icons.tire_repair, (l) => l.mWearCost, _euro, chartUnit: ' €'),
  MetricInfo('fuel', Source.costs, _all, Icons.water_drop, (l) => l.mFuel, _unit('l', 1), chartUnit: ' l'),
  MetricInfo('speed', Source.positions, _all, Icons.speed, (l) => l.mSpeed, _unit('km/h'), chartUnit: ' km/h'),
  MetricInfo('altitude', Source.positions, _all, Icons.terrain, (l) => l.mAltitude, _unit('m'), chartUnit: ' m'),
  MetricInfo('signal', Source.positions, _trackers, Icons.signal_cellular_alt, (l) => l.mSignal, _unit('dBm'),
      chartUnit: ' dBm'),
  MetricInfo('satellites', Source.positions, _trackers, Icons.satellite_alt, (l) => l.mSatellites,
      (l, v) => formatDecimal(v, 1)),
  MetricInfo('voltage', Source.positions, _trackers, Icons.bolt, (l) => l.mVoltage, _unit('V', 2), chartUnit: ' V'),
  MetricInfo('temperature', Source.positions, _trackers, Icons.thermostat, (l) => l.mTemperature, _unit('°C', 1),
      chartUnit: ' °C'),
  MetricInfo('pressure', Source.positions, _trackers, Icons.compress, (l) => l.mPressure, _unit('hPa', 1),
      chartUnit: ' hPa'),
  MetricInfo('extra', Source.extra, _trackers, Icons.data_object, (l) => l.mExtra, _plain),
  MetricInfo('odometer', Source.odometer, _cars, Icons.av_timer, (l) => l.mOdometer, _unit('km')),
  MetricInfo('deadlines', Source.deadlines, _cars, Icons.build, (l) => l.mDeadlines, _plain),
  MetricInfo('status', Source.status, _all, Icons.place, (l) => l.mStatus, _plain),
];

final metricByKey = {for (final m in metrics) m.key: m};

/// Groups of the metrics in the editor
String sourceGroup(AppLocalizations l, Source source) => switch (source) {
      Source.days => l.groupTrips,
      Source.costs => l.groupCosts,
      Source.positions || Source.extra => l.groupTracker,
      _ => l.groupState,
    };

String viewLabel(AppLocalizations l, String view) => switch (view) {
      'number' => l.viewNumber,
      'line' => l.viewLine,
      'bars' => l.viewBars,
      'vehicles' => l.viewVehicles,
      'table' => l.viewTable,
      'list' => l.viewList,
      _ => l.viewMap,
    };

/// Charts over time: grouping and buckets
bool overTime(String view) => view == 'line' || view == 'bars';

const aggs = ['avg', 'min', 'max', 'last'];

String aggLabel(AppLocalizations l, String agg) => switch (agg) {
      'min' => l.aggMin,
      'max' => l.aggMax,
      'last' => l.aggLast,
      _ => l.aggAvg,
    };

const buckets = ['auto', 'hour', 'day', 'week', 'month'];

String bucketLabel(AppLocalizations l, String bucket) => switch (bucket) {
      'hour' => l.groupHour,
      'day' => l.groupDay,
      'week' => l.groupWeek,
      'month' => l.groupMonth,
      _ => l.groupAuto,
    };

const periodPresets = ['today', '7d', '30d', '90d', '12m', 'ytd'];

/// A preset or {from, to} (YYYY-MM-DD)
String periodLabel(AppLocalizations l, Object period) => switch (period) {
      'today' => l.periodToday,
      '7d' => l.periodLast7d,
      '30d' => l.periodLast30d,
      '90d' => l.periodLast90d,
      '12m' => l.period12m,
      'ytd' => l.periodYtd,
      Map() => '${_day(period['from'] as String)} – ${_day(period['to'] as String)}',
      _ => '$period',
    };

String _day(String iso) => iso.split('-').reversed.join('/');

/// A widget of a dashboard: a metric of the catalog, a view, the devices, a period
class DashWidget {
  DashWidget({
    required this.id,
    required this.metric,
    required this.view,
    this.key,
    this.agg,
    this.bucket,
    this.devices = 'all',
    this.period,
    this.title = '',
    this.width = 1,
    this.height = 1,
  });

  factory DashWidget.fromJson(Map<String, dynamic> json) => DashWidget(
        id: json['id'] as String,
        metric: json['metric'] as String,
        view: json['view'] as String,
        key: json['key'] as String?,
        agg: json['agg'] as String?,
        bucket: json['bucket'] as String?,
        devices: json['devices'] is List ? (json['devices'] as List).cast<int>() : 'all',
        period: json['period'],
        title: json['title'] as String? ?? '',
        width: json['width'] as int? ?? 1,
        height: json['height'] as int? ?? 1,
      );

  final String id;
  final String metric;
  final String view;

  /// Field of the extra data
  final String? key;
  final String? agg;
  final String? bucket;

  /// 'all' or the ids
  final Object devices;

  /// null: the period of the dashboard
  final Object? period;
  final String title;
  final int width;
  final int height;

  MetricInfo get info => metricByKey[metric]!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'metric': metric,
        'view': view,
        if (key != null) 'key': key,
        if (agg != null) 'agg': agg,
        if (bucket != null) 'bucket': bucket,
        'devices': devices,
        'period': period,
        'title': title,
        'width': width,
        'height': height,
      };

  DashWidget copyWith({String? id, Object? devices}) =>
      DashWidget.fromJson({...toJson(), 'id': id ?? this.id, 'devices': devices ?? this.devices});

  /// Title of the card: the one of the user, or the metric (with the field of the extra data)
  String titleOf(AppLocalizations l) {
    if (title.isNotEmpty) return title;
    return key == null ? info.label(l) : '${info.label(l)} · $key';
  }
}

var _sequence = 0;

/// Id of a new widget, unique in the dashboard
String newWidgetId() => 'w${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_sequence++).toRadixString(36)}';

class Dashboard {
  Dashboard({required this.id, required this.name, required this.period, required this.widgets, this.current = false});

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final layout = json['layout'] as Map<String, dynamic>;
    return Dashboard(
      id: json['id'] as int,
      name: json['name'] as String,
      current: json['current'] == true,
      period: layout['period'] as Object,
      widgets: [for (final item in (layout['widgets'] as List).cast<Map<String, dynamic>>()) DashWidget.fromJson(item)],
    );
  }

  final int id;
  final String name;
  final Object period;
  final List<DashWidget> widgets;

  /// Shown in the analysis of every vehicle instead of the standard one
  final bool current;

  static Map<String, dynamic> layout(Object period, List<DashWidget> widgets) =>
      {'version': 1, 'period': period, 'widgets': [for (final w in widgets) w.toJson()]};
}

/// Ready-made dashboards: a starting point, every widget can be changed
List<DashWidget> template(String name) {
  DashWidget w(String metric, String view, {int width = 1, int height = 1, Object? period, String? agg}) =>
      DashWidget(id: newWidgetId(), metric: metric, view: view, width: width, height: height, period: period, agg: agg);
  return switch (name) {
    'overview' => [
        w('distance', 'number'),
        w('driving', 'number'),
        w('trips', 'number'),
        w('cost', 'number'),
        w('distance', 'bars', width: 2, height: 2),
        w('distance', 'vehicles', width: 2, height: 2),
        w('status', 'map', width: 2, height: 2),
        w('deadlines', 'list', width: 2, height: 2),
      ],
    'diagnostics' => [
        w('voltage', 'number', agg: 'last'),
        w('signal', 'number', agg: 'avg'),
        w('satellites', 'number', agg: 'avg'),
        w('traffic', 'number'),
        w('restVoltage', 'line', width: 2, height: 2, period: '90d'),
        w('signal', 'line', width: 2, height: 2),
        w('traffic', 'bars', width: 2, height: 2),
        w('alarms', 'bars', width: 2, height: 2),
      ],
    _ => [],
  };
}
