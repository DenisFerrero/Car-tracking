import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/live.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme.dart';
import '../../widgets/base_map.dart';

/// Realtime map. For the owner, opening it asks the tracker for live tracking (one
/// point every few seconds) while it stays open; a parked tracker receives the request
/// when it wakes up. Viewers see the points the tracker sends anyway (no extra data on
/// the SIM of the owner). A phone sends its position by itself: no commands.
class LiveTab extends ConsumerStatefulWidget {
  const LiveTab({super.key, required this.device});

  final Device device;

  @override
  ConsumerState<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends ConsumerState<LiveTab> with AutomaticKeepAliveClientMixin {
  final _map = MapController();
  final _trail = <Position>[];
  StreamSubscription<Map<String, dynamic>>? _events;
  late final LiveChannel _live;
  bool _follow = true;
  bool _busy = false;
  bool _mapReady = false;

  Device get device => widget.device;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _live = ref.read(liveProvider);
    _live.watch(device.id);
    _events = _live.device(device.id).listen(_onEvent);
    _loadTrail();
  }

  @override
  void dispose() {
    _events?.cancel();
    _live.unwatch(device.id);
    super.dispose();
  }

  /// Last two hours as the trail behind the marker (viewers: since the share started)
  Future<void> _loadTrail() async {
    final now = DateTime.now();
    try {
      final data = await ref.read(apiProvider).get('/api/devices/${device.id}/positions', {
        'from': now.subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
        'to': now.add(const Duration(minutes: 1)).toUtc().toIso8601String(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _trail
          ..clear()
          ..addAll((data['positions'] as List).map((item) => Position.fromJson(item as Map<String, dynamic>)));
      });
    } on ApiException catch (_) {
      // The trail is optional
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'position':
        final position = Position.fromJson(event['position'] as Map<String, dynamic>);
        setState(() {
          _trail.add(position);
          _trail.sort((a, b) => a.time.compareTo(b.time));
          if (device.lastPosition == null || !position.time.isBefore(device.lastPosition!.time)) device.lastPosition = position;
          device.lastSeenAt = DateTime.now();
        });
        if (_follow && _mapReady && position.point != null) _map.move(position.point!, _map.camera.zoom);
      case 'device':
        setState(() => device.applyEvent(event));
      case 'command':
        ref.invalidate(deviceProvider(device.id));
    }
  }

  Future<void> _command(String type, [int seconds = 0]) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/api/devices/${device.id}/commands', {'type': type, 'seconds': seconds});
      if (mounted) showMessage(context, device.connected ? l.commandSent : l.commandQueued);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final p = device.lastPosition;
    final trail = [for (final item in _trail) if (item.lat != null && !item.stale) LatLng(item.lat!, item.lon!)];
    return Stack(children: [
      BaseMap(
        controller: _map,
        center: p?.point,
        zoom: 16,
        onReady: () => _mapReady = true,
        layers: [
          if (trail.length > 1) PolylineLayer(polylines: [Polyline(points: trail, color: device.color, strokeWidth: 4)]),
          if (p?.fromCell == true && p?.cellAccuracy != null)
            CircleLayer(circles: [
              CircleMarker(
                point: p!.point!,
                radius: p.cellAccuracy!.toDouble(),
                useRadiusInMeter: true,
                color: device.color.withValues(alpha: 0.15),
                borderColor: device.color,
                borderStrokeWidth: 1,
              ),
            ]),
          if (p?.point != null)
            MarkerLayer(markers: [Marker(point: p!.point!, width: 44, height: 44, child: DeviceMarker(device: device))]),
        ],
      ),
      Positioned(
        right: 12,
        top: 12,
        child: FloatingActionButton.small(
          heroTag: 'follow',
          tooltip: _follow ? l.followOn : l.followOff,
          onPressed: () {
            setState(() => _follow = !_follow);
            if (_follow && _mapReady && p?.point != null) _map.move(p!.point!, _map.camera.zoom);
          },
          child: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
        ),
      ),
      Positioned(
        left: 8,
        right: 8,
        bottom: 8,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _panel(context, p)),
        ),
      ),
    ]);
  }

  Widget _panel(BuildContext context, Position? p) {
    final l = context.l10n;
    final signal = signalQuality(l, p?.signal);
    final satellites = satelliteQuality(l, p?.satellites);
    final theme = Theme.of(context);
    // Walking directions to the car or to a friend (not to one's own phone)
    final walk = p?.point == null || (device.isPhone && device.isOwner)
        ? null
        : ActionChip(
            key: const Key('walkTo'),
            avatar: const Icon(Icons.directions_walk, size: 18),
            label: Text(l.walkTo),
            onPressed: () => _walkTo(p!.point!),
          );
    return AccentCard(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!device.isOwner) ...[
            Text(
              l.viewerNotice(
                device.ownerName ?? '',
                device.shareExpiresAt == null ? '' : l.viewerUntil(formatDate(device.shareExpiresAt!)),
              ),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
          ],
          Row(children: [
            Icon(Icons.circle, size: 12, color: device.connected ? Colors.green : Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [
                  if (device.isPaused)
                    l.phonePausedUntil(formatTime(device.pausedUntil!))
                  else
                    device.connected
                        ? (device.isPhone ? l.sharingActive : device.isVehicle ? l.vehicleDriving : (device.isLive ? l.liveUntil(formatTime(device.liveUntil!)) : l.connected))
                        : l.notConnected(formatAgo(l, device.lastSeenAt)),
                  if (device.battery != null) l.battery(device.battery!),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (p?.speed != null && p?.status == TrackStatus.moving) Text('${p!.speed} km/h', style: theme.textTheme.titleLarge),
          ]),
          const SizedBox(height: 6),
          Text(
            p == null
                ? l.noPositionReceived
                : [
                    statusLabel(l, p.status),
                    formatDayTime(p.time),
                    if (p.stale) p.fromCell ? l.cellEstimate('${p.cellAccuracy ?? '?'}') : l.noFix,
                  ].join(' · '),
          ),
          if (p != null && !device.isTracker && device.isOwner) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (p.accuracy != null) _chip(Icons.gps_fixed, l.accuracyMeters('${p.accuracy}'), null),
              if (p.altitude != null) _chip(Icons.terrain, '${p.altitude} m', null),
            ]),
          ],
          if (p != null && device.isOwner && device.isTracker) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _chip(Icons.signal_cellular_alt, p.signal == null ? signal.label : '${p.signal} dBm', signal.color),
              _chip(Icons.satellite_alt, p.satellites == null ? satellites.label : '${p.satellites} sat', satellites.color),
              if (p.voltage != null) _chip(Icons.battery_std, '${formatDecimal(p.voltage!, 1)} V', p.voltage! < 11.8 ? Colors.red : null),
              if (p.temperature != null) _chip(Icons.thermostat, '${formatDecimal(p.temperature!, 1)} °C', null),
              if (p.altitude != null) _chip(Icons.terrain, '${p.altitude} m', null),
              for (final event in eventLabels(l, p.events)) _chip(Icons.warning_amber, event, Colors.red),
            ]),
          ],
          if (walk != null && !(device.isOwner && device.isTracker)) ...[
            const SizedBox(height: 8),
            walk,
          ],
          if (device.isOwner && device.isTracker) ...[
            const Divider(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ?walk,
              ActionChip(
                avatar: const Icon(Icons.play_arrow, size: 18),
                label: Text(l.live30),
                onPressed: _busy ? null : () => _command('live', 1800),
              ),
              if (device.isLive)
                ActionChip(
                  avatar: const Icon(Icons.stop, size: 18),
                  label: Text(l.stopLive),
                  onPressed: _busy ? null : () => _command('live', 0),
                ),
              ActionChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: Text(l.locate),
                onPressed: _busy ? null : () => _command('locate'),
              ),
              _antitheftChip(),
            ]),
          ],
        ]),
      ),
    );
  }

  /// Google Maps (app or browser) with the walking route from here to the position
  Future<void> _walkTo(LatLng point) => openLink(
        context,
        ref,
        Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': '${point.latitude},${point.longitude}',
          'travelmode': 'walking',
        }),
      );

  Widget _antitheftChip() {
    final l = context.l10n;
    final paused = device.antitheftPausedUntil != null && device.antitheftPausedUntil!.isAfter(DateTime.now());
    if (paused) {
      return ActionChip(
        avatar: const Icon(Icons.shield, size: 18),
        label: Text(l.resumeAntitheft(formatDayTime(device.antitheftPausedUntil!))),
        onPressed: _busy ? null : () => _command('antitheft', 0),
      );
    }
    return PopupMenuButton<int>(
      enabled: !_busy,
      tooltip: l.pauseAntitheftTooltip,
      onSelected: (seconds) => _command('antitheft', seconds),
      itemBuilder: (context) => [
        PopupMenuItem(value: 3600, child: Text(l.pause1h)),
        PopupMenuItem(value: 86400, child: Text(l.pause24h)),
        PopupMenuItem(value: 7 * 86400, child: Text(l.pause7d)),
      ],
      child: Chip(avatar: const Icon(Icons.shield_outlined, size: 18), label: Text(l.pauseAntitheft)),
    );
  }

  Widget _chip(IconData icon, String label, Color? color) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
}
