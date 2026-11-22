import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'catalog.dart';

/// A dashboard sent by a friend: only the widgets (all on "all"), never its vehicles
class SharedDashboard {
  SharedDashboard({required this.id, required this.from, required this.name, required this.widgets});

  factory SharedDashboard.fromJson(Map<String, dynamic> json) => SharedDashboard(
        id: json['id'] as int,
        from: json['from'] as String,
        name: json['name'] as String,
        widgets: ((json['layout'] as Map<String, dynamic>)['widgets'] as List).length,
      );

  final int id;
  final String from;
  final String name;
  final int widgets;
}

/// Dashboards received from friends and not used or declined yet
final sharedDashboardsProvider = FutureProvider.autoDispose<List<SharedDashboard>>((ref) async {
  final list = await ref.watch(apiProvider).get('/api/dashboards/shares') as List;
  return [for (final item in list.cast<Map<String, dynamic>>()) SharedDashboard.fromJson(item)];
});

/// Sends the layout of a dashboard to a friend chosen from the list
Future<void> shareDashboard(BuildContext context, WidgetRef ref, Dashboard dashboard) async {
  final l = context.l10n;
  final friend = await showDialog<Friend>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final list = ref.watch(friendsProvider);
        return AlertDialog(
          title: Text(l.dashboardShare),
          content: SizedBox(
            width: 360,
            child: list.when(
              loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
              error: (error, _) => Text(errorText(l, error)),
              data: (data) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.dashboardShareHint, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (data.friends.isEmpty)
                  Text(l.dashboardShareNoFriends, key: const Key('shareNoFriends'))
                else
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final friend in data.friends)
                        ListTile(
                          key: Key('shareTo_${friend.id}'),
                          leading: const Icon(Icons.person_outline),
                          title: Text(friend.name),
                          onTap: () => Navigator.pop(context, friend),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel))],
        );
      },
    ),
  );
  if (friend == null || !context.mounted) return;
  try {
    await ref.read(apiProvider).post('/api/dashboards/${dashboard.id}/share', {'friendId': friend.id});
    if (context.mounted) showMessage(context, l.dashboardShared(friend.name));
  } on ApiException catch (error) {
    if (context.mounted) showError(context, error);
  }
}

/// The dashboards received, each one with Use (on the vehicles chosen) and Decline
class ReceivedDashboards extends ConsumerWidget {
  const ReceivedDashboards({super.key, required this.onAdded});

  /// Id of the dashboard created from a layout received
  final void Function(int id) onAdded;

  Future<void> _use(BuildContext context, WidgetRef ref, SharedDashboard shared) async {
    final l = context.l10n;
    final choice = await showDialog<({String name, Object devices})>(
      context: context,
      builder: (context) => _UseDialog(shared: shared),
    );
    if (choice == null || !context.mounted) return;
    try {
      final created = await ref.read(apiProvider).post('/api/dashboards/shares/${shared.id}/accept', {
        'name': choice.name,
        'devices': choice.devices,
      }) as Map<String, dynamic>;
      onAdded(created['id'] as int);
      ref.invalidate(sharedDashboardsProvider);
      if (context.mounted) showMessage(context, l.dashboardAdded(choice.name));
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _decline(BuildContext context, WidgetRef ref, SharedDashboard shared) async {
    try {
      await ref.read(apiProvider).delete('/api/dashboards/shares/${shared.id}');
      ref.invalidate(sharedDashboardsProvider);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final list = ref.watch(sharedDashboardsProvider).value ?? const <SharedDashboard>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final shared in list)
        Card(
          key: Key('received_${shared.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.dashboard_customize_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.dashboardReceived(shared.from, shared.name), style: Theme.of(context).textTheme.titleSmall),
                    Text(l.dashboardReceivedWidgets(shared.widgets), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: [
                  TextButton(key: Key('decline_${shared.id}'), onPressed: () => _decline(context, ref, shared), child: Text(l.dashboardDecline)),
                  FilledButton(key: Key('use_${shared.id}'), onPressed: () => _use(context, ref, shared), child: Text(l.dashboardUse)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Name of the new dashboard and the vehicles of the user it shows
class _UseDialog extends ConsumerStatefulWidget {
  const _UseDialog({required this.shared});

  final SharedDashboard shared;

  @override
  ConsumerState<_UseDialog> createState() => _UseDialogState();
}

class _UseDialogState extends ConsumerState<_UseDialog> {
  late final _name = TextEditingController(text: widget.shared.name);
  bool _all = true;
  final _chosen = <int>{};
  bool _missing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (!_all && _chosen.isEmpty) return setState(() => _missing = true);
    Navigator.pop(context, (name: name, devices: _all ? 'all' : (_chosen.toList()..sort())));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final devices = [for (final d in ref.watch(devicesProvider).value ?? const <Device>[]) if (d.isOwner && !d.archived) d];
    return AlertDialog(
      title: Text('${l.dashboardUse} «${widget.shared.name}»'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: const Key('useName'),
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(labelText: l.dashboardName),
            ),
            Text(l.dashboardUseHint, style: Theme.of(context).textTheme.bodySmall),
            SwitchListTile(
              key: const Key('useAll'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.widgetAllDevices),
              subtitle: Text(l.widgetAllDevicesSub),
              value: _all,
              onChanged: (value) => setState(() => _all = value),
            ),
            if (!_all)
              for (final d in devices)
                CheckboxListTile(
                  key: Key('use_device_${d.id}'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.circle, color: d.color, size: 14),
                  title: Text(d.name),
                  value: _chosen.contains(d.id),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      _chosen.add(d.id);
                    } else {
                      _chosen.remove(d.id);
                    }
                    _missing = false;
                  }),
                ),
            if (_missing)
              Text(l.dashboardUseNoVehicles, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('useOk'), onPressed: _confirm, child: Text(l.dashboardUse)),
      ],
    );
  }
}
