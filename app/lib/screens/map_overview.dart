import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../theme.dart';
import 'vehicle_dialog.dart' show deviceIcon;
import '../widgets/base_map.dart';
import 'devices.dart' show chooseNewDevice;

/// Filters of the map: ownership, state, kind, owner of the shared devices, name
class DeviceFilter {
  const DeviceFilter({
    this.mine = true,
    this.shared = true,
    this.states = const {DeviceState.moving, DeviceState.parked, DeviceState.offline},
    this.trackers = true,
    this.phones = true,
    this.owner,
    this.query = '',
  });

  final bool mine;
  final bool shared;
  final Set<DeviceState> states;
  final bool trackers;
  final bool phones;

  /// Name of the owner of the shared devices, null = everybody
  final String? owner;
  final String query;

  bool get isDefault => mine && shared && states.length == DeviceState.values.length && trackers && phones && owner == null && query.isEmpty;

  DeviceFilter copyWith({bool? mine, bool? shared, Set<DeviceState>? states, bool? trackers, bool? phones, String? Function()? owner, String? query}) =>
      DeviceFilter(
        mine: mine ?? this.mine,
        shared: shared ?? this.shared,
        states: states ?? this.states,
        trackers: trackers ?? this.trackers,
        phones: phones ?? this.phones,
        owner: owner == null ? this.owner : owner(),
        query: query ?? this.query,
      );

  bool matches(Device device, DateTime now, Duration offlineAfter) {
    if (!(device.isOwner ? mine : shared)) return false;
    if (!(device.isPhone ? phones : trackers)) return false;
    if (owner != null && (device.isOwner || device.ownerName != owner)) return false;
    if (query.isNotEmpty && !device.name.toLowerCase().contains(query.toLowerCase())) return false;
    return states.contains(device.stateAt(now, offlineAfter));
  }
}

/// All the devices on a map (owned and shared with the user), positions updated in
/// realtime, with filters
class MapOverviewScreen extends ConsumerStatefulWidget {
  const MapOverviewScreen({super.key});

  @override
  ConsumerState<MapOverviewScreen> createState() => _MapOverviewScreenState();
}

class _MapOverviewScreenState extends ConsumerState<MapOverviewScreen> {
  final _controller = MapController();
  final _search = TextEditingController();
  Device? _selected;
  DeviceFilter _filter = const DeviceFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(DeviceFilter filter) => setState(() {
        _filter = filter;
        _selected = null;
      });

  /// Close devices: zoomed in, or listed when they're in the same place
  void _openCluster(List<Device> devices) {
    final points = [for (final device in devices) device.lastPosition!.point!];
    final bounds = LatLngBounds.fromPoints(points);
    if (_controller.camera.zoom < 17 && (bounds.north - bounds.south) + (bounds.east - bounds.west) > 1e-6) {
      _controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80), maxZoom: 18));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final device in devices)
            ListTile(
              leading: CircleAvatar(backgroundColor: device.color, child: Icon(deviceIcon(device), color: Colors.white)),
              title: Text(device.name),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selected = device);
              },
            ),
        ]),
      ),
    );
  }

  void _frame(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller.move(points.first, 15);
      return;
    }
    // Room for the filters on top and the buttons at the bottom
    _controller.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.fromLTRB(48, 160, 64, 120),
      maxZoom: 16,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final devices = ref.watch(devicesProvider);
    final offlineAfter = Duration(minutes: ((ref.read(sessionProvider).config?.offlineAfterHours ?? 9) * 60).round());
    // New positions update the markers without reloading the list
    ref.listen(liveEventsProvider, (previous, next) {
      final event = next.value;
      if (event?['type'] != 'position') return;
      final device = devices.value?.where((item) => item.id == event!['deviceId']).firstOrNull;
      if (device == null) return;
      setState(() => device.lastPosition = Position.fromJson(event!['position'] as Map<String, dynamic>));
    });

    return Scaffold(
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorText(l, error)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => ref.invalidate(devicesProvider), child: Text(l.retry)),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.directions_car, size: 64),
                const SizedBox(height: 12),
                Text(l.noDevicesShort),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => chooseNewDevice(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(l.add),
                ),
              ]),
            );
          }
          final now = DateTime.now();
          final shown = [for (final d in list) if (_filter.matches(d, now, offlineAfter)) d];
          final points = [for (final d in shown) if (d.lastPosition?.point != null) d.lastPosition!.point!];
          final owners = {for (final d in list) if (!d.isOwner && d.ownerName != null) d.ownerName!}.toList()..sort();
          return Stack(children: [
            BaseMap(
              controller: _controller,
              fit: points,
              center: points.length == 1 ? points.first : null,
              zoom: 15,
              layers: [
                DeviceClusterLayer(devices: shown, onTap: (device) => setState(() => _selected = device), onCluster: _openCluster),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(child: _FilterBar(filter: _filter, owners: owners, search: _search, onChanged: _set)),
            ),
            Positioned(
              right: 12,
              bottom: _selected == null ? 12 : 100,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(l.shownCount(shown.length, list.length)),
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'fit',
                  tooltip: l.fitAll,
                  onPressed: () => _frame(points),
                  child: const Icon(Icons.fit_screen),
                ),
              ]),
            ),
            if (shown.isEmpty)
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.noMatch),
                      TextButton(
                        onPressed: () {
                          _search.clear();
                          _set(const DeviceFilter());
                        },
                        child: Text(l.resetFilters),
                      ),
                    ]),
                  ),
                ),
              ),
            if (_selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _DeviceCard(device: _selected!, onClose: () => setState(() => _selected = null)),
              ),
          ]);
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.owners, required this.search, required this.onChanged});

  final DeviceFilter filter;
  final List<String> owners;
  final TextEditingController search;
  final ValueChanged<DeviceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget chip(String label, bool selected, ValueChanged<bool> onSelected, {Key? key}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(key: key, label: Text(label), selected: selected, onSelected: onSelected),
        );
    Widget state(DeviceState value, String label) => chip(
          label,
          filter.states.contains(value),
          (on) => onChanged(filter.copyWith(states: on ? {...filter.states, value} : ({...filter.states}..remove(value)))),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: Container(
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: amber, width: 4))),
          child: TextField(
            key: const Key('searchDevices'),
            controller: search,
            onChanged: (value) => onChanged(filter.copyWith(query: value.trim())),
            decoration: InputDecoration(
              hintText: l.searchDevices,
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          chip(l.filterMine, filter.mine, (on) => onChanged(filter.copyWith(mine: on))),
          chip(l.filterShared, filter.shared, (on) => onChanged(filter.copyWith(shared: on))),
          if (owners.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                key: const Key('ownerFilter'),
                tooltip: l.filterAllOwners,
                onSelected: (value) => onChanged(filter.copyWith(owner: () => value.isEmpty ? null : value)),
                itemBuilder: (context) => [
                  PopupMenuItem(value: '', child: Text(l.filterAllOwners)),
                  for (final owner in owners) PopupMenuItem(value: owner, child: Text(l.filterOwner(owner))),
                ],
                child: Chip(
                  avatar: const Icon(Icons.person, size: 18),
                  label: Text(filter.owner == null ? l.filterAllOwners : l.filterOwner(filter.owner!)),
                ),
              ),
            ),
          state(DeviceState.moving, l.filterMoving),
          state(DeviceState.parked, l.filterParked),
          state(DeviceState.offline, l.filterOffline),
          chip(l.filterTrackers, filter.trackers, (on) => onChanged(filter.copyWith(trackers: on))),
          chip(l.filterPhones, filter.phones, (on) => onChanged(filter.copyWith(phones: on))),
        ]),
      ),
    ]);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onClose});

  final Device device;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = device.lastPosition;
    return Card(
      elevation: 6,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.color,
          child: Icon(deviceIcon(device), color: Colors.white),
        ),
        title: Text(device.name),
        subtitle: Text(p == null
            ? l.noPosition
            : [
                statusLabel(l, p.status),
                if (p.speed != null && p.status == TrackStatus.moving) '${p.speed} km/h',
                formatAgo(l, p.time),
                if (p.accuracy != null) l.accuracyMeters('${p.accuracy}'),
                if (p.stale) p.fromCell ? l.fromCell : l.lastKnown,
                if (!device.isOwner) l.sharedBy(device.ownerName ?? ''),
              ].join(' · ')),
        onTap: () => context.go('/devices/${device.id}'),
        trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ),
    );
  }
}
