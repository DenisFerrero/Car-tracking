import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../theme.dart';
import '../screens/vehicle_dialog.dart' show deviceIcon;

/// Map with the tiles configured on the server (OpenStreetMap by default)
class BaseMap extends ConsumerWidget {
  const BaseMap({
    super.key,
    required this.layers,
    this.controller,
    this.center,
    this.zoom = 13,
    this.fit,
    this.onTap,
    this.onReady,
  });

  /// Tiles from the network; the tests replace them
  static TileProvider Function() tileProvider = NetworkTileProvider.new;

  final List<Widget> layers;
  final MapController? controller;
  final LatLng? center;
  final double zoom;

  /// Points to frame at the start
  final List<LatLng>? fit;
  final void Function(LatLng point)? onTap;

  /// The controller can move the camera from now on
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionProvider).config;
    final points = fit ?? const <LatLng>[];
    final filter = Theme.of(context).brightness == Brightness.dark ? darkMapFilter : lightMapFilter;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center ?? (points.isNotEmpty ? points.first : const LatLng(41.9, 12.5)),
        initialZoom: center == null && points.isEmpty ? 5 : zoom,
        initialCameraFit: points.length > 1
            ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(48), maxZoom: 16)
            : null,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onTap: onTap == null ? null : (_, point) => onTap!(point),
        onMapReady: onReady,
      ),
      children: [
        TileLayer(
          urlTemplate: config?.mapTileUrl ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.cartracking.app',
          tileProvider: tileProvider(),
          maxNativeZoom: 19,
          tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: filter, child: tile),
        ),
        ...layers,
        RichAttributionWidget(
          attributions: [TextSourceAttribution(config?.mapAttribution ?? '© OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

/// Marker of a device: diamond in its color (a road sign), arrow while driving, faded when
/// the position is old or estimated from the cell
class DeviceMarker extends StatelessWidget {
  const DeviceMarker({super.key, required this.device, this.position, this.onTap});

  final Device device;
  final Position? position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = position ?? device.lastPosition;
    final moving = p?.status == TrackStatus.moving;
    final uncertain = p == null || p.stale;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: device.name,
        child: Stack(alignment: Alignment.center, children: [
          FractionallySizedBox(
            widthFactor: 0.7,
            heightFactor: 0.7,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: device.color.withValues(alpha: uncertain ? 0.55 : 1),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
                ),
              ),
            ),
          ),
          Icon(moving ? Icons.navigation : deviceIcon(device), color: Colors.white, size: 18),
        ]),
      ),
    );
  }
}

/// Web Mercator pixels of a point at a zoom level (256 px tiles)
Offset mercatorPixels(LatLng point, double zoom) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  final lat = point.latitude.clamp(-85.05, 85.05) * math.pi / 180;
  return Offset((point.longitude + 180) / 360 * scale, (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * scale);
}

/// Devices closer than [radius] pixels at [zoom] in the same group, the first device of a
/// group is its reference (groups in the order of the devices)
List<List<Device>> clusterDevices(Iterable<Device> devices, double zoom, {double radius = 44}) {
  final groups = <({Offset at, List<Device> members})>[];
  for (final device in devices) {
    final point = device.lastPosition?.point;
    if (point == null) continue;
    final at = mercatorPixels(point, zoom);
    final group = groups.where((group) => (group.at - at).distance < radius).firstOrNull;
    if (group == null) {
      groups.add((at: at, members: [device]));
    } else {
      group.members.add(device);
    }
  }
  return [for (final group in groups) group.members];
}

/// Markers of the devices; the ones too close to tell apart at the current zoom become one
/// marker with their number: [onCluster] frames them or lists them
class DeviceClusterLayer extends StatelessWidget {
  const DeviceClusterLayer({super.key, required this.devices, required this.onCluster, this.onTap});

  final List<Device> devices;
  final void Function(List<Device> devices) onCluster;
  final void Function(Device device)? onTap;

  @override
  Widget build(BuildContext context) {
    final groups = clusterDevices(devices, MapCamera.of(context).zoom);
    final theme = Theme.of(context);
    return MarkerLayer(markers: [
      for (final group in groups)
        if (group.length == 1)
          ...deviceMarkers(group, onTap: onTap)
        else
          Marker(
            point: LatLng(
              group.map((device) => device.lastPosition!.point!.latitude).reduce((a, b) => a + b) / group.length,
              group.map((device) => device.lastPosition!.point!.longitude).reduce((a, b) => a + b) / group.length,
            ),
            width: 44,
            height: 44,
            child: GestureDetector(
              key: Key('cluster${group.first.id}'),
              onTap: () => onCluster(group),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: petrol,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: amber, width: 2.5),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
                ),
                child: Text('${group.length}', style: theme.textTheme.titleMedium?.copyWith(color: amber, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
    ]);
  }
}

/// Marker list for the devices with a known position
List<Marker> deviceMarkers(Iterable<Device> devices, {void Function(Device)? onTap}) => [
      for (final device in devices)
        if (device.lastPosition?.point != null)
          Marker(
            point: device.lastPosition!.point!,
            width: 40,
            height: 40,
            child: DeviceMarker(device: device, onTap: onTap == null ? null : () => onTap(device)),
          ),
    ];
