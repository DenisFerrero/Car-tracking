import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/base_map.dart';
import '../../widgets/track_layers.dart';

/// Track of the period, colored by speed, LTE signal or satellites (coverage of the
/// road network), with a slider to replay the points.
class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key, required this.device, required this.period});

  final Device device;
  final Period period;

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> with AutomaticKeepAliveClientMixin {
  TrackColoring _coloring = TrackColoring.plain;
  int? _index;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _index = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final data = ref.watch(positionsProvider(widget.period));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(errorText(l, error))),
      data: (result) {
        final positions = result.positions;
        if (positions.isEmpty) return Center(child: Text(l.noPositions));
        final located = [for (final p in positions) if (p.point != null) p];
        final selected = _index == null ? null : positions[_index!.clamp(0, positions.length - 1)];
        return Column(children: [
          Expanded(
            child: Stack(children: [
              BaseMap(
                // New period or coloring: new map framed on the track
                key: ValueKey(widget.period),
                fit: [for (final p in located) p.point!],
                zoom: 15,
                layers: [
                  PolylineLayer(polylines: trackPolylines(positions, _coloring, widget.device.color)),
                  MarkerLayer(markers: [
                    ...eventMarkers(positions, (p) => setState(() => _index = positions.indexOf(p))),
                    if (selected?.point != null)
                      Marker(
                        point: selected!.point!,
                        width: 40,
                        height: 40,
                        child: DeviceMarker(device: widget.device, position: selected),
                      ),
                  ]),
                ],
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<TrackColoring>(
                      segments: [
                        for (final c in TrackColoring.values) ButtonSegment(value: c, label: Text(c.label(l))),
                      ],
                      selected: {_coloring},
                      onSelectionChanged: (value) => setState(() => _coloring = value.first),
                      style: SegmentedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surface),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ColoringLegend(coloring: _coloring),
                  if (result.truncated)
                    Card(child: Padding(padding: const EdgeInsets.all(8), child: Text(l.truncated))),
                ]),
              ),
            ]),
          ),
          _scrubber(context, positions, selected),
        ]);
      },
    );
  }

  Widget _scrubber(BuildContext context, List<Position> positions, Position? selected) {
    final l = context.l10n;
    final p = selected ?? positions.last;
    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [
                formatFull(p.time),
                statusLabel(l, p.status),
                if (p.speed != null) '${p.speed} km/h',
                if (p.signal != null) '${p.signal} dBm',
                if (p.satellites != null) '${p.satellites} sat',
                if (p.stale) l.noFixShort,
                if (p.events != 0) eventLabels(l, p.events).join(', '),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (positions.length > 1)
              Slider(
                value: (_index ?? positions.length - 1).toDouble(),
                max: (positions.length - 1).toDouble(),
                divisions: positions.length - 1,
                onChanged: (value) => setState(() => _index = value.round()),
              ),
            Text(l.pointsRange(positions.length, formatDayTime(positions.first.time), formatDayTime(positions.last.time)),
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}
