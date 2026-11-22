import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../device/analysis_tab.dart';
import 'dashboards_screen.dart';
import 'widget_card.dart';

String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Analysis tab of a vehicle: the current dashboard of the user on this vehicle (its
/// widgets of the kinds of the vehicle, in the period of the screen), or the standard
/// analysis when there is none or the user switches to it.
class VehicleAnalysis extends ConsumerStatefulWidget {
  const VehicleAnalysis({super.key, required this.device, required this.period});

  final Device device;
  final Period period;

  @override
  ConsumerState<VehicleAnalysis> createState() => _VehicleAnalysisState();
}

class _VehicleAnalysisState extends ConsumerState<VehicleAnalysis> {
  bool _standard = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dashboards = ref.watch(dashboardsProvider);
    if (dashboards.isLoading && !dashboards.hasValue) return const Center(child: CircularProgressIndicator());
    // Without dashboards (or when they can't be read) the standard analysis
    final current = dashboards.value?.where((d) => d.current).firstOrNull;
    if (current == null) return AnalysisTab(device: widget.device, period: widget.period);

    final theme = Theme.of(context);
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(children: [
        Icon(_standard ? Icons.insights : Icons.star, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_standard ? l.analysisStandard : current.name,
              style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          key: const Key('analysisSwitch'),
          onPressed: () => setState(() => _standard = !_standard),
          child: Text(_standard ? l.dashboardCurrent : l.analysisStandard),
        ),
        if (!_standard)
          IconButton(
            key: const Key('analysisOpenDashboard'),
            tooltip: l.analysisOpenDashboard,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => context.go('/dashboards'),
          ),
      ]),
    );
    if (_standard) return Column(children: [bar, Expanded(child: AnalysisTab(device: widget.device, period: widget.period))]);

    final widgets = [
      for (final w in current.widgets)
        if (w.info.kinds.contains(widget.device.kind)) w.copyWith(devices: [widget.device.id]),
    ];
    final period = {'from': _day(widget.period.from), 'to': _day(widget.period.to)};
    return Column(children: [
      bar,
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardDataProvider),
          child: ListView(padding: const EdgeInsets.all(8), children: [
            if (widgets.isEmpty)
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l.analysisNoWidgets, textAlign: TextAlign.center)))
            else
              DashboardGrid(period: period, widgets: widgets),
          ]),
        ),
      ),
    ]);
  }
}
