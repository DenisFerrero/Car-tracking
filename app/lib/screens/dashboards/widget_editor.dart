import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'catalog.dart';
import 'widget_card.dart';

/// Opens the editor of a widget: the widget changed, or null when cancelled
Future<DashWidget?> editWidget(BuildContext context, Object dashboardPeriod, [DashWidget? widget]) =>
    Navigator.of(context).push<DashWidget>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WidgetEditor(dashboardPeriod: dashboardPeriod, widget: widget),
    ));

String _iso(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A widget step by step: value, vehicles, view, period and size, with the preview of the
/// real values
class WidgetEditor extends ConsumerStatefulWidget {
  const WidgetEditor({super.key, required this.dashboardPeriod, this.widget});

  final Object dashboardPeriod;
  final DashWidget? widget;

  @override
  ConsumerState<WidgetEditor> createState() => _WidgetEditorState();
}

class _WidgetEditorState extends ConsumerState<WidgetEditor> {
  late final String _id = widget.widget?.id ?? newWidgetId();
  late String _metric = widget.widget?.metric ?? 'distance';
  late String _view = widget.widget?.view ?? 'number';
  late String? _agg = widget.widget?.agg;
  late String? _bucket = widget.widget?.bucket;
  late bool _all = widget.widget?.devices == 'all' || widget.widget == null;
  late final Set<int> _devices = {...?(widget.widget?.devices is List ? widget.widget!.devices as List<int> : null)};
  late Object? _period = widget.widget?.period;
  late int _width = widget.widget?.width ?? 1;
  late int _height = widget.widget?.height ?? 1;
  late final _key = TextEditingController(text: widget.widget?.key ?? '');
  late final _title = TextEditingController(text: widget.widget?.title ?? '');

  /// Field of the extra data in the preview: applied after a pause in the typing
  late String _previewKey = _key.text.trim();
  Timer? _typing;
  String? _error;

  MetricInfo get _info => metricByKey[_metric]!;

  @override
  void dispose() {
    _typing?.cancel();
    _key.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Another value: the options it doesn't have are reset
  void _setMetric(String metric) => setState(() {
        _metric = metric;
        if (!_info.views.contains(_view)) _view = _info.views.first;
        if (!_info.sampled) _agg = null;
        _fixBucket();
      });

  void _fixBucket() {
    if (!overTime(_view) || (_bucket == 'hour' && !_info.sampled)) _bucket = null;
  }

  /// Devices of the user with this value: owned (shared ones only for the status)
  List<Device> _choices(List<Device> devices) =>
      [for (final d in devices) if (_info.kinds.contains(d.kind) && (d.isOwner || !_info.ownerOnly)) d];

  DashWidget _build(String key) => DashWidget(
        id: _id,
        metric: _metric,
        view: _view,
        key: _info.source == Source.extra ? key : null,
        agg: _info.sampled ? _agg : null,
        bucket: overTime(_view) ? _bucket : null,
        devices: _all ? 'all' : (_devices.toList()..sort()),
        period: _info.hasPeriod ? _period : null,
        title: _title.text.trim(),
        width: _width,
        height: _height,
      );

  void _save() {
    final l = context.l10n;
    final available = {for (final d in _choices(ref.read(devicesProvider).value ?? const [])) d.id};
    _devices.retainWhere(available.contains);
    if (!_all && _devices.isEmpty) return setState(() => _error = l.widgetDevicesNeeded);
    if (_info.source == Source.extra && _key.text.trim().isEmpty) return setState(() => _error = l.widgetKeyNeeded);
    Navigator.pop(context, _build(_key.text.trim()));
  }

  Future<void> _pickPeriod(String? choice) async {
    if (choice != 'custom') return setState(() => _period = choice == 'dashboard' ? null : choice);
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (range == null || !mounted) return;
    setState(() => _period = {'from': _iso(range.start), 'to': _iso(range.end)});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final devices = _choices(ref.watch(devicesProvider).value ?? const []);
    final info = _info;
    final ready = !(info.source == Source.extra && _previewKey.isEmpty) && (_all || _devices.isNotEmpty);
    final preview = ready ? _build(_previewKey) : null;

    DropdownMenuItem<String> header(String text) => DropdownMenuItem(
          enabled: false,
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.widget == null ? l.widgetAdd : l.widgetEdit),
        actions: [TextButton(key: const Key('widgetSave'), onPressed: _save, child: Text(l.save))],
      ),
      body: ListView(padding: readable(context, const EdgeInsets.all(16)), children: [
        DropdownButtonFormField<String>(
          key: const Key('widgetMetric'),
          initialValue: _metric,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.widgetMetric),
          items: [
            for (final source in Source.values) ...[
              if (source != Source.extra && source.index <= Source.odometer.index) header(sourceGroup(l, source)),
              for (final m in metrics)
                if (m.source == source)
                  DropdownMenuItem(
                    value: m.key,
                    child: Row(children: [Icon(m.icon, size: 18), const SizedBox(width: 8), Flexible(child: Text(m.label(l), overflow: TextOverflow.ellipsis))]),
                  ),
            ],
          ],
          onChanged: (value) => _setMetric(value!),
        ),
        if (info.source == Source.extra)
          TextField(
            key: const Key('widgetKey'),
            controller: _key,
            maxLength: 64,
            decoration: InputDecoration(labelText: l.widgetExtraKey, helperText: l.widgetExtraKeyHint),
            onChanged: (value) {
              _typing?.cancel();
              _typing = Timer(const Duration(milliseconds: 600), () {
                if (mounted) setState(() => _previewKey = value.trim());
              });
            },
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('widgetView$_metric'),
          initialValue: _view,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.widgetView),
          items: [for (final v in info.views) DropdownMenuItem(value: v, child: Text(viewLabel(l, v)))],
          onChanged: (value) => setState(() {
            _view = value!;
            _fixBucket();
          }),
        ),
        if (info.sampled) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('widgetAgg'),
            initialValue: _agg ?? 'avg',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.widgetAgg),
            items: [for (final a in aggs) DropdownMenuItem(value: a, child: Text(aggLabel(l, a)))],
            onChanged: (value) => setState(() => _agg = value),
          ),
        ],
        if (overTime(_view) && info.hasPeriod) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('widgetBucket$_metric$_view'),
            initialValue: _bucket ?? 'auto',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.widgetBucket),
            items: [
              for (final b in buckets)
                if (b != 'hour' || info.sampled) DropdownMenuItem(value: b, child: Text(bucketLabel(l, b))),
            ],
            onChanged: (value) => setState(() => _bucket = value == 'auto' ? null : value),
          ),
        ],
        if (info.hasPeriod) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('widgetPeriod'),
            initialValue: _period == null ? 'dashboard' : (_period is Map ? 'range' : _period as String),
            isExpanded: true,
            decoration: InputDecoration(labelText: l.widgetPeriod),
            items: [
              DropdownMenuItem(value: 'dashboard', child: Text('${l.widgetPeriodDashboard} (${periodLabel(l, widget.dashboardPeriod)})')),
              for (final p in periodPresets) DropdownMenuItem(value: p, child: Text(periodLabel(l, p))),
              if (_period is Map) DropdownMenuItem(value: 'range', child: Text(periodLabel(l, _period!))),
              DropdownMenuItem(value: 'custom', child: Text(l.periodCustom)),
            ],
            onChanged: _pickPeriod,
          ),
        ],
        const SizedBox(height: 16),
        Text(l.widgetDevices, style: Theme.of(context).textTheme.titleSmall),
        SwitchListTile(
          key: const Key('widgetAll'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.widgetAllDevices),
          subtitle: Text(l.widgetAllDevicesSub),
          value: _all,
          onChanged: (value) => setState(() => _all = value),
        ),
        if (!_all)
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final d in devices)
              FilterChip(
                key: Key('device_${d.id}'),
                avatar: Icon(Icons.circle, size: 14, color: d.color),
                label: Text(d.archived ? '${d.name} · ${l.archived}' : d.name),
                selected: _devices.contains(d.id),
                onSelected: (selected) => setState(() => selected ? _devices.add(d.id) : _devices.remove(d.id)),
              ),
          ]),
        const SizedBox(height: 12),
        TextField(key: const Key('widgetTitle'), controller: _title, maxLength: 60, decoration: InputDecoration(labelText: l.widgetTitle)),
        Row(children: [
          Expanded(child: Text(l.widgetWidth)),
          SegmentedButton<int>(
            key: const Key('widgetWidth'),
            segments: [for (final w in [1, 2, 3, 4]) ButtonSegment(value: w, label: Text('$w'))],
            selected: {_width},
            onSelectionChanged: (value) => setState(() => _width = value.first),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(l.widgetHeight)),
          SegmentedButton<int>(
            key: const Key('widgetHeight'),
            segments: [for (final h in [1, 2]) ButtonSegment(value: h, label: Text('$h'))],
            selected: {_height},
            onSelectionChanged: (value) => setState(() => _height = value.first),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 16),
        Text(l.widgetPreview, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (preview != null)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: const Key('widgetPreview'),
              width: math.min(200.0 * _width + gap * (_width - 1), MediaQuery.sizeOf(context).width - 32),
              height: rowHeight * _height + gap * (_height - 1),
              child: WidgetCard(
                widget: preview,
                result: ref
                    .watch(dashboardDataProvider(dataRequest(widget.dashboardPeriod, [preview])))
                    .whenData((results) => results[preview.id] as Map<String, dynamic>?),
              ),
            ),
          ),
      ]),
    );
  }
}
