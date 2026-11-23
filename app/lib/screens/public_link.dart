import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart' show parseColor;
import '../core/providers.dart';
import '../theme.dart';
import '../widgets/base_map.dart';

/// How often the page reads the position again
const publicLinkRefresh = Duration(seconds: 15);

/// Page of a temporary link (web, `/#/l/<token>`), without an account: name and latest position
/// of the device until the link ends. Expired, revoked and unknown links look the same.
class PublicLinkScreen extends ConsumerStatefulWidget {
  const PublicLinkScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<PublicLinkScreen> createState() => _PublicLinkScreenState();
}

class _PublicLinkScreenState extends ConsumerState<PublicLinkScreen> {
  final _map = MapController();
  Timer? _timer;
  Map<String, dynamic>? _data;
  Object? _error;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(publicLinkRefresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(apiProvider).get('/api/public/links/${widget.token}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      final point = _point(data);
      if (point != null && _mapReady) _map.move(point, _map.camera.zoom);
    } on ApiException catch (error) {
      if (!mounted) return;
      // Ended: nothing more to read
      if (error.status == 404) _timer?.cancel();
      setState(() => _error = error);
    }
  }

  static LatLng? _point(Map<String, dynamic> data) {
    final position = data['position'] as Map<String, dynamic>?;
    return position == null ? null : LatLng((position['lat'] as num).toDouble(), (position['lon'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final error = _error;
    if (error is ApiException && error.status == 404) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.link_off, size: 56),
              const SizedBox(height: 12),
              Text(l.publicLinkGone, key: const Key('publicLinkGone'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l.publicLinkGoneHint, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
    }
    final data = _data;
    if (data == null) {
      return Scaffold(body: Center(child: error == null ? const CircularProgressIndicator() : Text(errorText(l, error))));
    }
    final point = _point(data);
    final position = data['position'] as Map<String, dynamic>?;
    final color = parseColor(data['color'] as String?);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(data['name'] as String)),
      body: Stack(children: [
        BaseMap(
          controller: _map,
          center: point,
          zoom: 15,
          onReady: () => _mapReady = true,
          layers: [
            if (point != null)
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  child: CircleAvatar(
                    backgroundColor: color,
                    child: Icon(data['kind'] == 'phone' ? Icons.person : Icons.directions_car, color: Colors.white, size: 22),
                  ),
                ),
              ]),
          ],
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AccentCard(
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      position == null
                          ? l.publicLinkNoPosition
                          : [
                              l.publicLinkUpdated(formatDayTime(DateTime.parse(position['time'] as String).toLocal())),
                              if (position['speed'] != null) l.publicLinkMoving('${position['speed']}'),
                            ].join(' · '),
                      key: const Key('publicLinkPosition'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(l.publicLinkUntil(formatDayTime(DateTime.parse(data['expiresAt'] as String).toLocal())),
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
