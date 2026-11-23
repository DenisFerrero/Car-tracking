import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../vehicle_dialog.dart' show deviceIcon;
import '../../l10n/app_localizations.dart';
import '../add_device.dart' show deviceColors;
import 'alerts.dart';
import 'firmware_section.dart';
import 'live_links.dart';
import 'parking.dart';

/// Quick durations of a share, in hours (null = permanent)
const shareDurations = <int?>[1, 3, 8, 24, 72, 168, null];

/// Share chosen in the dialog: the friend (new shares) and the end: permanent, a quick
/// duration or a date and time
typedef ShareChoice = ({DateTime? end, int? friendId});

Future<ShareChoice?> pickShareEnd(BuildContext context, {String? title, List<Friend>? friends}) {
  return showDialog<ShareChoice>(
    context: context,
    builder: (context) => _ShareDialog(title: title, friends: friends),
  );
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({this.title, this.friends});

  final String? title;

  /// New share: the friends to choose from
  final List<Friend>? friends;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  int? _hours = 24;
  DateTime? _custom;
  late int? _friend = widget.friends?.firstOrNull?.id;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null) return;
    setState(() => _custom = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  String _label(AppLocalizations l, int? hours) =>
      hours == null ? l.permanent : (hours < 24 || hours % 24 != 0 ? l.hoursShort(hours) : l.daysShort(hours ~/ 24));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    DateTime? end() => _custom ?? (_hours == null ? null : DateTime.now().add(Duration(hours: _hours!)));
    return AlertDialog(
      title: Text(widget.title ?? l.shareTitle),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.friends != null) ...[
            DropdownButtonFormField<int>(
              key: const Key('shareFriend'),
              initialValue: _friend,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.shareFriend),
              items: [for (final friend in widget.friends!) DropdownMenuItem(value: friend.id, child: Text(friend.name))],
              onChanged: (value) => setState(() => _friend = value),
            ),
            const SizedBox(height: 8),
            Text(l.sharingHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
          ],
          Text(l.shareDuration, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final hours in shareDurations)
              ChoiceChip(
                label: Text(_label(l, hours)),
                selected: _custom == null && _hours == hours,
                onSelected: (_) => setState(() {
                  _hours = hours;
                  _custom = null;
                }),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.event, size: 18),
              label: Text(_custom == null ? l.customEnd : formatDate(_custom!)),
              selected: _custom != null,
              onSelected: (_) => _pickCustom(),
            ),
          ]),
          const SizedBox(height: 12),
          Text(end() == null ? l.permanent : l.endsAt(formatDate(end()!)), style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: widget.friends != null && _friend == null ? null : () => Navigator.pop(context, (end: end(), friendId: _friend)),
          child: Text(widget.friends != null ? l.share : l.save),
        ),
      ],
    );
  }
}

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key, required this.device});

  final Device device;

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  // Alarms are of the trackers: phones and vehicles fed by a phone have none
  late Future<Map<String, dynamic>>? _kinds = device.isTracker ? _loadKinds() : null;

  Device get device => widget.device;
  ApiClient get api => ref.read(apiProvider);

  Future<Map<String, dynamic>> _loadKinds() async =>
      await api.get('/api/devices/${device.id}/notification-settings') as Map<String, dynamic>;

  Future<void> _guard(Future<void> Function() action, [String? done]) async {
    try {
      await action();
      if (mounted && done != null) showMessage(context, done);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _rename() async {
    final l = context.l10n;
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deviceName),
        content: TextField(key: const Key('deviceName'), controller: controller, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(l.save)),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _guard(() async {
      await api.patch('/api/devices/${device.id}', {'name': name});
      setState(() => device.name = name);
      ref.invalidate(devicesProvider);
    });
  }

  Future<void> _setColor(Color color) => _guard(() async {
        await api.patch('/api/devices/${device.id}', {'color': colorToHex(color)});
        setState(() => device.color = color);
        ref.invalidate(devicesProvider);
      });

  Future<void> _toggleKind(List<String> current, String kind, bool enabled) => _guard(() async {
        final kinds = {...current};
        enabled ? kinds.add(kind) : kinds.remove(kind);
        await api.put('/api/devices/${device.id}/notification-settings', {'kinds': kinds.toList()});
        final reload = _loadKinds();
        setState(() {
          _kinds = reload;
        });
      });

  /// Only with friends: without any, the user is sent to add one
  Future<void> _share() async {
    final l = context.l10n;
    final List<Friend> friends;
    try {
      friends = (await ref.read(friendsProvider.future)).friends;
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    if (friends.isEmpty) {
      final go = await _confirm(l.shareWith, l.noFriendsToShare, action: l.goToFriends);
      if (go && mounted) context.go('/account/friends');
      return;
    }
    final choice = await pickShareEnd(context, friends: friends);
    if (choice == null) return;
    await _guard(() async {
      await api.post('/api/devices/${device.id}/shares', {
        'userId': choice.friendId,
        'expiresAt': choice.end?.toUtc().toIso8601String(),
      });
      ref.invalidate(sharesProvider(device.id));
    }, l.shared);
  }

  Future<void> _changeEnd(Share share) async {
    final choice = await pickShareEnd(context, title: share.name);
    if (choice == null) return;
    await _guard(() async {
      await api.patch('/api/devices/${device.id}/shares/${share.userId}', {'expiresAt': choice.end?.toUtc().toIso8601String()});
      ref.invalidate(sharesProvider(device.id));
    });
  }

  Future<void> _revoke(Share share) async {
    final l = context.l10n;
    if (!await _confirm(l.revokeTitle(share.name), l.revokeBody)) return;
    await _guard(() async {
      await api.delete('/api/devices/${device.id}/shares/${share.userId}');
      ref.invalidate(sharesProvider(device.id));
    }, l.shareRevoked);
  }

  Future<void> _release() async {
    final l = context.l10n;
    final (title, body) = switch (device.kind) {
      'phone' => (l.removePhoneTitle, l.removePhoneBody),
      'vehicle' => (l.removeVehicleTitle, l.removeVehicleBody),
      _ => (l.removeTrackerTitle, l.removeTrackerBody),
    };
    if (!await _confirm(title, body)) return;
    await _guard(() async {
      await api.delete('/api/devices/${device.id}');
      // This phone: it stops sending; from this vehicle: the person again
      final tracker = ref.read(phoneTrackerProvider);
      if (tracker.deviceId == device.id) await tracker.forget();
      if (tracker.vehicleId == device.id) await tracker.drive(null);
      ref.invalidate(devicesProvider);
      if (mounted) context.go('/devices');
    });
  }

  /// To another vehicle of the user without a tracker, or to a new one
  Future<void> _move() async {
    final l = context.l10n;
    final vehicles = [for (final d in await ref.read(devicesProvider.future)) if (d.isVehicle && d.isOwner) d];
    if (!mounted) return;
    final choice = await showDialog<({int? vehicleId, String name, bool archive})>(
      context: context,
      builder: (context) => _MoveDialog(vehicles: vehicles),
    );
    if (choice == null) return;
    await _guard(() async {
      final result = await api.post('/api/devices/${device.id}/tracker/move', {
        if (choice.vehicleId != null) 'vehicleId': choice.vehicleId else 'vehicle': {'name': choice.name},
        'archive': choice.archive,
      }) as Map<String, dynamic>;
      ref.invalidate(devicesProvider);
      ref.invalidate(deviceProvider(device.id));
      if (mounted) context.go('/devices/${result['id']}');
    }, l.trackerMoved(choice.vehicleId == null ? choice.name : vehicles.firstWhere((v) => v.id == choice.vehicleId).name));
  }

  Future<void> _detach() async {
    final l = context.l10n;
    if (!await _confirm(l.detachTrackerTitle, l.detachTrackerBody)) return;
    await _guard(() async {
      await api.delete('/api/devices/${device.id}/tracker');
      ref.invalidate(devicesProvider);
      ref.invalidate(deviceProvider(device.id));
    }, l.trackerDetached);
  }

  Future<void> _archive(bool archived) => _guard(() async {
        await api.patch('/api/devices/${device.id}', {'archived': archived});
        ref.invalidate(devicesProvider);
        ref.invalidate(deviceProvider(device.id));
      });

  Future<bool> _confirm(String title, String body, {String? action}) async {
    final l = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action ?? l.confirm)),
            ],
          ),
        ) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final shares = ref.watch(sharesProvider(device.id));
    return ListView(padding: readable(context, const EdgeInsets.symmetric(vertical: 8)), children: [
      _header(context, l.device),
      ListTile(
        leading: CircleAvatar(
          backgroundColor: device.color,
          child: Icon(deviceIcon(device), color: Colors.white),
        ),
        title: Text(device.name),
        subtitle: Text(device.isVehicle ? '${l.vehicleKind} · ${l.tapToRename}' : l.tapToRename),
        onTap: _rename,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [
          for (final color in deviceColors)
            InkWell(
              onTap: () => _setColor(color),
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: color,
                child: device.color.toARGB32() == color.toARGB32() ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
            ),
        ]),
      ),
      if (device.isTracker) ...[
      ListTile(leading: const Icon(Icons.qr_code), title: Text(l.imei), subtitle: SelectableText(device.imei)),
      ListTile(
        leading: const Icon(Icons.memory),
        title: Text(l.modemFirmware),
        subtitle: Text([
          if (device.model.isNotEmpty) '${device.manufacturer} ${device.model}'.trim(),
          if (device.firmware.isNotEmpty) l.firmwareVersion(device.firmware),
          device.registeredAt == null ? l.neverConnected : l.connectedSince(formatDay(device.registeredAt!)),
        ].join(' · ')),
      ),
      if (device.registeredAt != null) FirmwareSection(deviceId: device.id),
      _header(context, l.alarmNotifications),
      FutureBuilder(
        future: _kinds,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final enabled = (snapshot.data!['kinds'] as List).cast<String>();
          return Column(children: [
            for (final kind in (snapshot.data!['available'] as List).cast<String>())
              SwitchListTile(
                title: Text(kindLabel(l, kind)),
                value: enabled.contains(kind),
                onChanged: (value) => _toggleKind(enabled, kind, value),
              ),
          ]);
        },
      ),
      ],
      if (!device.isPhone) ...[
        _header(context, l.trackerSection),
        if (device.isTracker) ...[
          ListTile(
            key: const Key('moveTracker'),
            leading: const Icon(Icons.swap_horiz),
            title: Text(l.moveTracker),
            subtitle: Text(l.moveTrackerSub),
            onTap: _move,
          ),
          ListTile(
            key: const Key('detachTracker'),
            leading: const Icon(Icons.link_off),
            title: Text(l.detachTracker),
            subtitle: Text(l.detachTrackerSub),
            onTap: _detach,
          ),
        ] else
          SwitchListTile(
            key: const Key('archive'),
            secondary: const Icon(Icons.inventory_2_outlined),
            title: Text(l.archived),
            subtitle: Text(l.archiveSub),
            value: device.archived,
            onChanged: _archive,
          ),
        for (final item in device.installations)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text('${l.installations}: ${item.imei}'),
            subtitle: Text(item.removedAt == null
                ? l.installedSince(formatDay(item.installedAt))
                : l.installedRange(formatDay(item.installedAt), formatDay(item.removedAt!))),
          ),
      ],
      _header(context, l.stopAlert),
      ListTile(
        key: const Key('stopAlert'),
        leading: const Icon(Icons.timer),
        title: Text(stopAlertText(l, device.stopAlertHours)),
        subtitle: Text(l.stopAlertHint),
        onTap: () async {
          if (await chooseStopAlert(context, ref, device)) setState(() {});
        },
      ),
      if (!device.isPhone) ...[
        _header(context, l.parking),
        if (device.isTracker) ParkingPromptSwitch(deviceId: device.id),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l.parkingHint, style: Theme.of(context).textTheme.bodySmall)),
      ],
      _header(context, l.sharing),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l.sharingHint, style: Theme.of(context).textTheme.bodySmall)),
      ...shares.when(
        loading: () => [const LinearProgressIndicator()],
        error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
        data: (list) => [
          if (list.isEmpty) ListTile(title: Text(l.noShares)),
          for (final share in list)
            ListTile(
              leading: const Icon(Icons.visibility),
              title: Text(share.name),
              subtitle: Text(share.expiresAt == null ? l.sharePermanent : l.shareUntil(formatDate(share.expiresAt!))),
              onTap: () => _changeEnd(share),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: l.changeEnd, icon: const Icon(Icons.schedule), onPressed: () => _changeEnd(share)),
                IconButton(tooltip: l.revoke, icon: const Icon(Icons.person_remove), onPressed: () => _revoke(share)),
              ]),
            ),
        ],
      ),
      ListTile(leading: const Icon(Icons.person_add), title: Text(l.shareWith), onTap: _share),
      _header(context, l.liveLinks),
      LiveLinksSection(deviceId: device.id),
      _header(context, l.dangerZone),
      ListTile(
        leading: const Icon(Icons.delete_forever, color: Colors.red),
        title: Text(switch (device.kind) { 'phone' => l.removePhone, 'vehicle' => l.removeVehicle, _ => l.removeTracker },
            style: const TextStyle(color: Colors.red)),
        subtitle: Text(switch (device.kind) { 'phone' => l.removePhoneSub, 'vehicle' => l.removeVehicleSub, _ => l.removeTrackerSub }),
        onTap: _release,
      ),
    ]);
  }

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Target of the tracker: a vehicle without a tracker or a new one; this vehicle archived
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.vehicles});

  final List<Device> vehicles;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late int? _target = widget.vehicles.firstOrNull?.id;
  final _name = TextEditingController();
  bool _archive = true;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ready = _target != null || _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l.moveTrackerTitle),
      content: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          DropdownButtonFormField<int?>(
            key: const Key('moveTarget'),
            initialValue: _target,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.moveTarget),
            items: [
              for (final vehicle in widget.vehicles) DropdownMenuItem(value: vehicle.id, child: Text(vehicle.name)),
              DropdownMenuItem(value: null, child: Text(l.pairNewVehicle)),
            ],
            onChanged: (value) => setState(() => _target = value),
          ),
          if (_target == null)
            TextField(
              key: const Key('moveName'),
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(labelText: l.vehicleName),
              onChanged: (_) => setState(() {}),
            ),
          CheckboxListTile(
            key: const Key('moveArchive'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.archivePrevious),
            subtitle: Text(l.archiveSub),
            value: _archive,
            onChanged: (value) => setState(() => _archive = value!),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          key: const Key('moveConfirm'),
          onPressed: ready ? () => Navigator.pop(context, (vehicleId: _target, name: _name.text.trim(), archive: _archive)) : null,
          child: Text(l.move),
        ),
      ],
    );
  }
}
