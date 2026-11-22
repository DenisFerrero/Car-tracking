import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';

/// Tracker with its label, or this phone (Android app only)
Future<void> chooseNewDevice(BuildContext context) async {
  final l = context.l10n;
  if (!ProviderScope.containerOf(context, listen: false).read(phoneTrackerProvider).supported) {
    context.go('/devices/add');
    return;
  }
  final route = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(l.addChooseTitle, style: Theme.of(context).textTheme.titleMedium)),
        ListTile(
          leading: const Icon(Icons.directions_car),
          title: Text(l.addTrackerOption),
          subtitle: Text(l.addTrackerOptionSub),
          onTap: () => Navigator.pop(context, '/devices/add'),
        ),
        ListTile(
          leading: const Icon(Icons.smartphone),
          title: Text(l.phoneOption),
          subtitle: Text(l.phoneOptionSub),
          onTap: () => Navigator.pop(context, '/devices/phone'),
        ),
      ]),
    ),
  );
  if (route != null && context.mounted) context.go(route);
}

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final devices = ref.watch(devicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.devicesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => chooseNewDevice(context),
        icon: const Icon(Icons.add),
        label: Text(l.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(devicesProvider.future),
        child: devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorText(l, error)))]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  Padding(padding: const EdgeInsets.all(32), child: Text(l.noDevices, textAlign: TextAlign.center)),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => DeviceTile(device: list[index]),
                ),
        ),
      ),
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = device.lastPosition;
    final signal = signalQuality(l, p?.signal);
    final satellites = satelliteQuality(l, p?.satellites);
    return ListTile(
      leading: Badge(
        backgroundColor: device.connected ? Colors.green : Colors.grey,
        smallSize: 12,
        child: CircleAvatar(
          backgroundColor: device.color,
          child: Icon(device.isPhone ? Icons.smartphone : (device.isOwner ? Icons.directions_car : Icons.visibility), color: Colors.white),
        ),
      ),
      title: Text(device.name),
      subtitle: Text(
        device.waitingFirstContact
            ? l.waitingFirstContact
            : [
                p == null ? l.noPosition : statusLabel(l, p.status),
                formatAgo(l, device.lastSeenAt),
                if (p?.accuracy != null) l.accuracyMeters('${p!.accuracy}'),
                if (device.isPaused) l.phonePausedUntil(formatTime(device.pausedUntil!)),
                if (device.battery != null) l.battery(device.battery!),
                if (!device.isOwner) l.sharedBy(device.ownerName ?? ''),
              ].join(' · '),
      ),
      // Signal and satellites: only the owner receives them
      trailing: p == null || !device.isOwner || device.isPhone
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Tooltip(
                message: l.signalTooltip('${signal.label}${p.signal != null ? ' (${p.signal} dBm)' : ''}'),
                child: Icon(Icons.signal_cellular_alt, color: signal.color),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: l.satellitesTooltip('${satellites.label}${p.satellites != null ? ' (${p.satellites})' : ''}'),
                child: Icon(Icons.satellite_alt, color: satellites.color),
              ),
            ]),
      onTap: () => context.go('/devices/${device.id}'),
    );
  }
}
