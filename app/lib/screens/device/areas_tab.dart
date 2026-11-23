import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/base_map.dart';

/// Radius steps of the editor, 50 m to 50 km as the backend accepts
const areaRadii = [50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000, 20000, 50000];

/// Short name of a day of the week, Monday = 1
String weekdayName(int day) => DateFormat('E').format(DateTime(2026, 11, 22 + day));

/// "Mon Tue 08:00–18:00", days in order
String scheduleText(AppLocalizations l, AreaSchedule schedule) {
  final days = ([...schedule.days]..sort()).map(weekdayName).join(' ');
  return '$days ${schedule.allDay ? l.areaAllDay : '${schedule.fromText}–${schedule.toText}'}';
}

/// Arrival areas of the logged user on this device (owned or shared): a notification
/// when the device enters ("almost there") and optionally when it leaves.
class AreasTab extends ConsumerWidget {
  const AreasTab({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final areas = ref.watch(geofencesProvider(device.id));

    Future<void> edit([Geofence? area]) async {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AreaEditor(device: device, area: area), fullscreenDialog: true),
      );
      if (saved == true) ref.invalidate(geofencesProvider(device.id));
    }

    Future<void> remove(Geofence area) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.deleteAreaTitle(area.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await ref.read(apiProvider).delete('/api/geofences/${area.id}');
        ref.invalidate(geofencesProvider(device.id));
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'area',
        onPressed: () => edit(),
        icon: const Icon(Icons.add_location_alt),
        label: Text(l.addArea),
      ),
      body: areas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(errorText(l, error))),
        data: (list) => Column(children: [
          SizedBox(
            height: 220,
            child: BaseMap(
              center: list.isEmpty ? device.lastPosition?.point : null,
              fit: [
                for (final area in list) area.center,
                if (device.lastPosition?.point != null) device.lastPosition!.point!,
              ],
              zoom: 14,
              layers: [
                CircleLayer(circles: [
                  for (final area in list)
                    if (area.polygon == null) _circle(area.center, area.radius, device.color),
                ]),
                PolygonLayer(polygons: [
                  for (final area in list)
                    if (area.polygon != null) _polygon(area.polygon!, device.color),
                ]),
                MarkerLayer(markers: deviceMarkers([device])),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Text(l.areasHint)),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(l.noAreas))
                : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                    for (final area in list)
                      ListTile(
                        leading: Icon(area.inside == true ? Icons.where_to_vote : Icons.place_outlined, color: device.color),
                        title: Text(area.name),
                        subtitle: Text([
                          area.polygon == null
                              ? l.areaSummary(formatMeters(area.radius), area.inside == true ? l.areaInside : l.areaOutside)
                              : l.areaPolygonSummary(area.polygon!.length, area.inside == true ? l.areaInside : l.areaOutside),
                          if (area.notifyEnter) l.notifyEnter,
                          if (area.notifyExit) l.notifyExit,
                          if (area.schedule != null) scheduleText(l, area.schedule!),
                        ].join(' · ')),
                        onTap: () => edit(area),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l.delete,
                          onPressed: () => remove(area),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

CircleMarker _circle(LatLng center, int radius, Color color) => CircleMarker(
      point: center,
      radius: radius.toDouble(),
      useRadiusInMeter: true,
      color: color.withValues(alpha: 0.18),
      borderColor: color,
      borderStrokeWidth: 2,
    );

Polygon _polygon(List<LatLng> points, Color color) => Polygon(
      points: points,
      color: color.withValues(alpha: 0.18),
      borderColor: color,
      borderStrokeWidth: 2,
    );

/// New or changed area: a circle (center chosen on the map, radius) or a polygon (vertices
/// tapped on the map), notifications
class AreaEditor extends ConsumerStatefulWidget {
  const AreaEditor({super.key, required this.device, this.area});

  final Device device;
  final Geofence? area;

  @override
  ConsumerState<AreaEditor> createState() => _AreaEditorState();
}

class _AreaEditorState extends ConsumerState<AreaEditor> {
  late final _name = TextEditingController(text: widget.area?.name);
  late LatLng _center = widget.area?.center ?? widget.device.lastPosition?.point ?? const LatLng(41.9, 12.5);
  late int _radius = widget.area?.radius ?? 500;
  late bool _drawn = widget.area?.polygon != null;
  late final List<LatLng> _vertices = [...?widget.area?.polygon];
  late bool _enter = widget.area?.notifyEnter ?? true;
  late bool _exit = widget.area?.notifyExit ?? false;
  late bool _scheduled = widget.area?.schedule != null;
  late AreaSchedule _schedule = widget.area?.schedule ??
      const AreaSchedule(days: [1, 2, 3, 4, 5], from: TimeOfDay(hour: 8, minute: 0), to: TimeOfDay(hour: 18, minute: 0));
  bool _busy = false;

  Future<void> _pickTime(bool start) async {
    final time = await showTimePicker(context: context, initialTime: start ? _schedule.from : _schedule.to);
    if (time == null) return;
    setState(() => _schedule = AreaSchedule(days: _schedule.days, from: start ? time : _schedule.from, to: start ? _schedule.to : time));
  }

  void _toggleDay(int day, bool selected) {
    final days = {..._schedule.days};
    selected ? days.add(day) : days.remove(day);
    // At least one day
    if (days.isEmpty) return;
    setState(() => _schedule = AreaSchedule(days: days.toList()..sort(), from: _schedule.from, to: _schedule.to));
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim().isEmpty ? l.areaDefaultName : _name.text.trim();
    if (_drawn && _vertices.length < 3) return showMessage(context, l.areaPolygonTooFew);
    final body = {
      'name': name,
      if (_drawn)
        'polygon': [
          for (final vertex in _vertices) [vertex.latitude, vertex.longitude],
        ]
      else ...{
        'lat': _center.latitude,
        'lon': _center.longitude,
        'radius': _radius,
        'polygon': null,
      },
      'notifyEnter': _enter,
      'notifyExit': _exit,
      'schedule': _scheduled ? _schedule.toJson() : null,
    };
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (widget.area == null) {
        await api.post('/api/devices/${widget.device.id}/geofences', body);
      } else {
        await api.patch('/api/geofences/${widget.area!.id}', body);
      }
      if (!mounted) return;
      showMessage(context, l.areaSaved);
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final step = areaRadii.indexWhere((value) => value >= _radius).clamp(0, areaRadii.length - 1);
    final color = widget.device.color;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.area == null ? l.addArea : l.editArea),
        actions: [TextButton(key: const Key('saveArea'), onPressed: _busy ? null : _save, child: Text(l.save))],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            BaseMap(
              center: _drawn && _vertices.isNotEmpty ? _vertices.first : _center,
              zoom: 14,
              onTap: (point) => setState(() => _drawn ? _vertices.add(point) : _center = point),
              layers: [
                if (!_drawn) CircleLayer(circles: [_circle(_center, _radius, color)]),
                if (_drawn && _vertices.length > 2) PolygonLayer(polygons: [_polygon(_vertices, color)]),
                if (_drawn && _vertices.length == 2) PolylineLayer(polylines: [Polyline(points: _vertices, color: color, strokeWidth: 2)]),
                MarkerLayer(markers: [
                  if (!_drawn) Marker(point: _center, width: 36, height: 36, child: Icon(Icons.place, size: 36, color: color)),
                  if (_drawn)
                    for (final vertex in _vertices)
                      Marker(point: vertex, width: 14, height: 14, child: Icon(Icons.circle, size: 14, color: color)),
                  ...deviceMarkers([widget.device]),
                ]),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_drawn ? l.tapMapToDraw : l.tapMapToPlace, textAlign: TextAlign.center),
                ),
              ),
            ),
          ]),
        ),
        Material(
          elevation: 4,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  key: const Key('areaName'),
                  controller: _name,
                  maxLength: 60,
                  decoration: InputDecoration(labelText: l.areaName, hintText: l.areaDefaultName),
                ),
                SegmentedButton<bool>(
                  key: const Key('areaShape'),
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.circle_outlined), label: Text(l.areaCircle)),
                    ButtonSegment(value: true, icon: const Icon(Icons.pentagon_outlined), label: Text(l.areaPolygon)),
                  ],
                  selected: {_drawn},
                  onSelectionChanged: (selection) => setState(() => _drawn = selection.first),
                ),
                const SizedBox(height: 8),
                if (_drawn)
                  Row(children: [
                    Expanded(child: Text(l.areaVertices(_vertices.length), key: const Key('areaVertices'))),
                    IconButton(
                      key: const Key('undoVertex'),
                      tooltip: l.undoVertex,
                      icon: const Icon(Icons.undo),
                      onPressed: _vertices.isEmpty ? null : () => setState(_vertices.removeLast),
                    ),
                    IconButton(
                      key: const Key('clearVertices'),
                      tooltip: l.clearVertices,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _vertices.isEmpty ? null : () => setState(_vertices.clear),
                    ),
                  ])
                else
                Row(children: [
                  Text(l.radius(formatMeters(_radius))),
                  Expanded(
                    child: Slider(
                      value: step.toDouble(),
                      max: (areaRadii.length - 1).toDouble(),
                      divisions: areaRadii.length - 1,
                      onChanged: (value) => setState(() => _radius = areaRadii[value.round()]),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.notifyEnter),
                  value: _enter,
                  onChanged: (value) => setState(() => _enter = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.notifyExit),
                  value: _exit,
                  onChanged: (value) => setState(() => _exit = value),
                ),
                SwitchListTile(
                  key: const Key('areaScheduled'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.areaSchedule),
                  subtitle: Text(l.areaScheduleHint),
                  value: _scheduled,
                  onChanged: (value) => setState(() => _scheduled = value),
                ),
                if (_scheduled) ...[
                  Wrap(spacing: 4, children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        key: Key('day$day'),
                        label: Text(weekdayName(day)),
                        selected: _schedule.days.contains(day),
                        onSelected: (selected) => _toggleDay(day, selected),
                      ),
                  ]),
                  Wrap(children: [
                    TextButton.icon(
                      key: const Key('areaFrom'),
                      icon: const Icon(Icons.schedule),
                      label: Text(l.areaFrom(_schedule.fromText)),
                      onPressed: () => _pickTime(true),
                    ),
                    TextButton.icon(
                      key: const Key('areaTo'),
                      icon: const Icon(Icons.schedule),
                      label: Text(l.areaTo(_schedule.toText)),
                      onPressed: () => _pickTime(false),
                    ),
                  ]),
                ],
              ]),
            ),
            ),
          ),
        ),
      ]),
    );
  }
}
