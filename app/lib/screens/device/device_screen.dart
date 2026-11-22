import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../dashboards/vehicle_analysis.dart';
import 'alerts.dart';
import 'areas_tab.dart';
import 'history_tab.dart';
import 'live_tab.dart';
import 'settings_tab.dart';

/// Period of history and analysis: last 24 hours, 7 or 30 days, or a custom range
class PeriodChoice {
  const PeriodChoice(this.label, this.from, this.to);

  factory PeriodChoice.last(String label, Duration duration, [DateTime? now]) {
    final end = now ?? DateTime.now();
    return PeriodChoice(label, end.subtract(duration), end.add(const Duration(minutes: 1)));
  }

  final String label;
  final DateTime from;
  final DateTime to;
}

/// A device: the owner has live map, history, analysis, areas and settings; a viewer
/// (shared device) only the live map and their arrival areas.
class DeviceScreen extends ConsumerWidget {
  const DeviceScreen({super.key, required this.deviceId, this.initialTab = 0});

  final int deviceId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final device = ref.watch(deviceProvider(deviceId));
    return device.when(
      loading: () => Scaffold(appBar: AppBar(title: Text(l.device)), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(title: Text(l.device)), body: Center(child: Text(errorText(l, error)))),
      // A different role (share revoked, tracker claimed) is a different set of tabs
      data: (device) => _DeviceView(key: ValueKey((device.id, device.role)), device: device, initialTab: initialTab),
    );
  }
}

class _DeviceView extends ConsumerStatefulWidget {
  const _DeviceView({super.key, required this.device, required this.initialTab});

  final Device device;
  final int initialTab;

  @override
  ConsumerState<_DeviceView> createState() => _DeviceViewState();
}

/// Pages of a device: viewers see the position and their areas; the analysis of a phone
/// has only trips and export (no signal, satellites or battery)
enum _Page { live, history, analysis, areas, settings }

class _DeviceViewState extends ConsumerState<_DeviceView> with SingleTickerProviderStateMixin {
  late final List<_Page> _pages = [
    _Page.live,
    if (widget.device.isOwner) _Page.history,
    if (widget.device.isOwner) _Page.analysis,
    _Page.areas,
    if (widget.device.isOwner) _Page.settings,
  ];
  late final int _count = _pages.length;
  late final TabController _tabs = TabController(length: _count, vsync: this, initialIndex: widget.initialTab.clamp(0, _count - 1));
  PeriodChoice? _period;

  Device get device => widget.device;

  PeriodChoice _currentPeriod(BuildContext context) =>
      _period ??= PeriodChoice.last(context.l10n.last24h, const Duration(hours: 24));

  // A link to another tab of the same device (e.g. from a notification) reuses this screen
  @override
  void didUpdateWidget(_DeviceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _tabs.animateTo(widget.initialTab.clamp(0, _count - 1));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _choosePeriod() async {
    final l = context.l10n;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (label, duration) in [
            (l.periodLast24h, const Duration(hours: 24)),
            (l.periodLast7d, const Duration(days: 7)),
            (l.periodLast30d, const Duration(days: 30)),
            (l.periodLast90d, const Duration(days: 90)),
          ])
            ListTile(title: Text(label), onTap: () => Navigator.pop(context, PeriodChoice.last(label, duration))),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: Text(l.periodCustom),
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is PeriodChoice) return setState(() => _period = choice);
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (range == null || !mounted) return;
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    if (end.difference(range.start).inDays > 92) return showMessage(context, l.errPeriodTooLong);
    setState(() => _period = PeriodChoice('${formatDay(range.start)} – ${formatDay(range.end)}', range.start, end));
  }

  Future<void> _leave() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.leaveShareTitle(device.name)),
        content: Text(l.leaveShareBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.leaveShare)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).delete('/api/devices/${device.id}/access');
      ref.invalidate(devicesProvider);
      if (mounted) context.go('/devices');
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final period = _currentPeriod(context);
    final key = (deviceId: device.id, from: period.from, to: period.to);
    final owner = device.isOwner;
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          if (owner)
            ListenableBuilder(
              listenable: _tabs,
              builder: (context, _) => _pages[_tabs.index] == _Page.history || _pages[_tabs.index] == _Page.analysis
                  ? TextButton.icon(onPressed: _choosePeriod, icon: const Icon(Icons.date_range), label: Text(period.label))
                  : const SizedBox.shrink(),
            )
          else
            // Viewer: own alerts on the device, end of the share
            PopupMenuButton<String>(
              key: const Key('viewerMenu'),
              onSelected: (value) async {
                if (value == 'leave') return _leave();
                final changed = value == 'stop' ? await chooseStopAlert(context, ref, device) : await chooseBatteryAlert(context, ref, device);
                if (changed && mounted) setState(() {});
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'stop', child: Text('${l.stopAlert}: ${stopAlertText(l, device.stopAlertHours)}')),
                if (device.isPhone) PopupMenuItem(value: 'battery', child: Text('${l.batteryAlert}: ${batteryAlertText(l, device.batteryAlert)}')),
                PopupMenuItem(value: 'leave', child: Text(l.leaveShare)),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: owner,
          tabAlignment: owner ? TabAlignment.center : null,
          tabs: [
            for (final page in _pages)
              switch (page) {
                _Page.live => Tab(icon: const Icon(Icons.my_location), text: l.tabLive),
                _Page.history => Tab(icon: const Icon(Icons.history), text: l.tabHistory),
                _Page.analysis => Tab(icon: const Icon(Icons.insights), text: l.tabAnalysis),
                _Page.areas => Tab(icon: const Icon(Icons.place), text: l.tabAreas),
                _Page.settings => Tab(icon: const Icon(Icons.settings), text: l.tabSettings),
              },
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final page in _pages)
            switch (page) {
              _Page.live => LiveTab(device: device),
              _Page.history => HistoryTab(device: device, period: key),
              _Page.analysis => VehicleAnalysis(device: device, period: key),
              _Page.areas => AreasTab(device: device),
              _Page.settings => SettingsTab(device: device),
            },
        ],
      ),
    );
  }
}
