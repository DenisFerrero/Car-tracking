import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../l10n/app_localizations.dart';

/// What colors the track: one color, speed, LTE signal or satellites (coverage)
enum TrackColoring {
  plain,
  speed,
  signal,
  satellites;

  String label(AppLocalizations l) => switch (this) {
        plain => l.coloringPlain,
        speed => l.coloringSpeed,
        signal => l.coloringSignal,
        satellites => l.coloringSatellites,
      };
}

Color colorForPosition(Position p, TrackColoring coloring, Color base) {
  switch (coloring) {
    case TrackColoring.plain:
      return base;
    case TrackColoring.speed:
      return p.speed == null ? Colors.grey : scaleColor(p.speed!.toDouble(), 30, 130);
    case TrackColoring.signal:
      return p.signal == null ? Colors.grey : scaleColor(-p.signal!.toDouble(), 70, 110);
    case TrackColoring.satellites:
      if (p.stale) return Colors.red;
      return p.satellites == null ? Colors.grey : scaleColor(-p.satellites!.toDouble(), -10, -4);
  }
}

/// Track split in segments of the same color. Points without fix are skipped: the
/// line jumps them (dashed segments for long gaps).
List<Polyline> trackPolylines(List<Position> positions, TrackColoring coloring, Color base) {
  final lines = <Polyline>[];
  List<LatLng> current = [];
  Color? currentColor;
  Position? previous;

  void flush() {
    if (current.length > 1) lines.add(Polyline(points: current, color: currentColor!, strokeWidth: 4));
  }

  for (final p in positions) {
    if (p.lat == null || p.lon == null || (p.stale && coloring != TrackColoring.satellites)) continue;
    final point = LatLng(p.lat!, p.lon!);
    final color = colorForPosition(p, coloring, base);
    final gap = previous != null && p.time.difference(previous.time).inMinutes > 10;
    if (gap) {
      flush();
      lines.add(Polyline(
        points: [LatLng(previous.lat!, previous.lon!), point],
        color: Colors.grey,
        strokeWidth: 2,
        pattern: StrokePattern.dashed(segments: const [6, 6]),
      ));
      current = [point];
      currentColor = color;
    } else if (color != currentColor) {
      // The new segment starts from the last point: no holes between colors
      flush();
      current = [if (current.isNotEmpty) current.last, point];
      currentColor = color;
    } else {
      current.add(point);
    }
    previous = p;
  }
  flush();
  return lines;
}

/// Points with events (alarms) and stops, as small markers
List<Marker> eventMarkers(List<Position> positions, void Function(Position) onTap) => [
      for (final p in positions)
        if (p.point != null && (p.events != 0 || p.status == TrackStatus.engineOff))
          Marker(
            point: p.point!,
            width: 26,
            height: 26,
            child: GestureDetector(
              onTap: () => onTap(p),
              child: CircleAvatar(
                backgroundColor: p.events != 0 ? Colors.red : Colors.blueGrey,
                child: Icon(p.events != 0 ? Icons.warning_amber : Icons.local_parking, size: 15, color: Colors.white),
              ),
            ),
          ),
    ];

class ColoringLegend extends StatelessWidget {
  const ColoringLegend({super.key, required this.coloring});

  final TrackColoring coloring;

  @override
  Widget build(BuildContext context) {
    final (low, high) = switch (coloring) {
      TrackColoring.speed => ('30 km/h', '130 km/h'),
      TrackColoring.signal => ('-70 dBm', '-110 dBm'),
      TrackColoring.satellites => ('10+ sat', context.l10n.legendNoFix),
      TrackColoring.plain => ('', ''),
    };
    if (coloring == TrackColoring.plain) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(low, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Container(
            width: 80,
            height: 8,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.green, Colors.amber, Colors.red])),
          ),
          const SizedBox(width: 6),
          Text(high, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }
}
