import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart' show parseColor;
import '../core/providers.dart';

/// Summary of a month (YYYY-MM) of the devices of the user
final summaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, month) async => await ref.watch(apiProvider).get('/api/summary/$month') as Map<String, dynamic>,
);

/// The month before / after YYYY-MM
String shiftMonth(String month, int months) {
  final date = DateTime(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)) + months);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

/// Month just ended, the default of the summary
String lastMonth([DateTime? now]) {
  final today = now ?? DateTime.now();
  return shiftMonth('${today.year}-${today.month.toString().padLeft(2, '0')}', -1);
}

/// "ottobre 2026"
String monthName(String month) => DateFormat('MMMM y').format(DateTime(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7))));

/// Change from the month before: "+12%", null when there is nothing to compare
String? _change(num now, num? before) {
  if (before == null || before == 0) return null;
  final percent = ((now - before) / before * 100).round();
  return '${percent > 0 ? '+' : ''}$percent%';
}

/// Summary of a month: totals with the change from the month before, each vehicle (km,
/// driving, trips, costs, refuels, SIM), deadlines coming up. Opened from the notification
/// of the start of the month or from the account; arrows move between the months.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, this.month});

  final String? month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final current = month ?? lastMonth();
    final thisMonth = shiftMonth(lastMonth(), 1);
    final data = ref.watch(summaryProvider(current));
    void go(String to) => context.replace('/account/summary?month=$to');
    // On the bar: the colors of its title
    final bar = Theme.of(context).appBarTheme.foregroundColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.monthlySummary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: const Key('summaryPrevious'),
              tooltip: l.previousMonth,
              color: bar,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => go(shiftMonth(current, -1)),
            ),
            Text(monthName(current), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: bar)),
            IconButton(
              key: const Key('summaryNext'),
              color: bar,
              disabledColor: bar?.withValues(alpha: 0.4),
              tooltip: l.nextMonth,
              icon: const Icon(Icons.chevron_right),
              onPressed: current.compareTo(thisMonth) >= 0 ? null : () => go(shiftMonth(current, 1)),
            ),
          ]),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(errorText(l, error))),
        data: (summary) => _Summary(summary: summary),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final totals = summary['totals'] as Map<String, dynamic>;
    final previous = summary['previous'] as Map<String, dynamic>;
    final devices = (summary['devices'] as List).cast<Map<String, dynamic>>();
    final deadlines = (summary['deadlines'] as List).cast<Map<String, dynamic>>();
    final names = {for (final device in devices) device['id']: device['name'] as String};

    Widget tile(Key key, IconData icon, String label, String value, String? change) => Card(
          key: key,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Expanded(child: Text(label, style: theme.textTheme.labelMedium))]),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.titleLarge),
              // Same height with or without the comparison
              Text(change == null ? '' : l.comparedToBefore(change), style: theme.textTheme.bodySmall),
            ]),
          ),
        );

    return ListView(padding: readable(context, const EdgeInsets.all(8)), children: [
      if (summary['complete'] != true)
        Padding(padding: const EdgeInsets.all(8), child: Text(l.summaryPartial, key: const Key('summaryPartial'))),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 600 ? 4 : 2;
          return Wrap(children: [
            for (final child in [
          tile(const Key('summaryKm'), Icons.route, l.mDistance, '${formatInt((totals['distanceKm'] as num).round())} km',
              _change(totals['distanceKm'] as num, previous['distanceKm'] as num)),
          tile(const Key('summaryTrips'), Icons.flag, l.mTrips, formatInt(totals['trips'] as int), _change(totals['trips'] as num, previous['trips'] as num)),
          tile(const Key('summaryDriving'), Icons.timer, l.mDriving, formatDuration(l, totals['drivingMin'] as int),
              _change(totals['drivingMin'] as num, previous['drivingMin'] as num)),
          tile(const Key('summaryCost'), Icons.euro, l.mCost, totals['cost'] == null ? '-' : formatEuro(totals['cost'] as num),
              totals['cost'] == null ? null : _change(totals['cost'] as num, previous['cost'] as num?)),
          if (totals['reimbursement'] != null)
            tile(const Key('summaryAllowance'), Icons.work, l.mReimbursement, formatEuro(totals['reimbursement'] as num),
                _change(totals['reimbursement'] as num, previous['reimbursement'] as num?)),
            ])
              SizedBox(width: constraints.maxWidth / columns, child: child),
          ]);
        },
      ),
      if (devices.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.summaryEmpty))),
      for (final device in devices) _DeviceMonth(device: device),
      if (deadlines.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 4), child: Text(l.maintenance, style: theme.textTheme.titleMedium)),
        for (final item in deadlines)
          ListTile(
            leading: Icon(Icons.build, color: item['state'] == 'due' ? theme.colorScheme.error : Colors.orange),
            title: Text('${names[item['deviceId']] ?? ''}: ${(item['title'] as String).isNotEmpty ? item['title'] : maintenanceKindLabel(l, item['kind'] as String)}'),
            subtitle: Text(remainingText(l, item['remainingDays'] as int?, item['remainingKm'] as int?, item['expectedDate'] as String?)),
            onTap: () => context.push('/devices/${item['deviceId']}/maintenance'),
          ),
      ],
    ]);
  }
}

/// One vehicle of the month
class _DeviceMonth extends StatelessWidget {
  const _DeviceMonth({required this.device});

  final Map<String, dynamic> device;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cost = device['cost'] as Map<String, dynamic>?;
    final refuels = device['refuels'] as Map<String, dynamic>;
    final traffic = device['trafficBytes'] as num?;
    final energy = device['energyUnit'] as String? ?? 'l';
    final lines = [
      l.summaryDriven(formatInt((device['distanceKm'] as num).round()), device['trips'] as int, formatDuration(l, device['drivingMin'] as int)),
      if ((device['businessKm'] as num) > 0) l.summaryBusiness(formatInt((device['businessKm'] as num).round())),
      if (cost != null && cost['cost'] != null) l.summaryCost(costText(l, cost)),
      if (device['reimbursement'] != null) l.summaryReimbursement(formatEuro(device['reimbursement'] as num)),
      if ((refuels['count'] as int) > 0)
        (energy == 'kWh' ? l.summaryCharges : l.summaryRefuels)(refuels['count'] as int,
            refuels['cost'] == null ? '${formatDecimal((refuels['litres'] as num).toDouble(), 1)} $energy' : formatEuro(refuels['cost'] as num)),
      if (refuels['consumption'] != null) l.realConsumption('${formatDecimal((refuels['consumption'] as num).toDouble(), 1)} $energy/100 km'),
      if (traffic != null) l.summarySim(formatBytes(traffic)),
      if ((device['alarms'] as int) > 0) l.summaryAlarms(device['alarms'] as int),
    ];
    return Card(
      key: Key('summaryDevice_${device['id']}'),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: parseColor(device['color'] as String?), child: const Icon(Icons.directions_car, color: Colors.white)),
        title: Text(device['name'] as String),
        subtitle: Text(lines.join('\n')),
        onTap: () => context.push('/devices/${device['id']}?tab=2'),
      ),
    );
  }
}

/// Switch of a preference of the account: the notification of the start of the month, the
/// alerts of new errors (administrators)
class AccountSwitch extends ConsumerStatefulWidget {
  const AccountSwitch({
    super.key,
    required this.field,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  /// Field of PATCH /api/account
  final String field;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  ConsumerState<AccountSwitch> createState() => _AccountSwitchState();
}

class _AccountSwitchState extends ConsumerState<AccountSwitch> {
  late bool _value = widget.enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: Key(widget.field),
      secondary: Icon(widget.icon),
      title: Text(widget.title),
      subtitle: Text(widget.subtitle),
      value: _value,
      onChanged: (value) async {
        setState(() => _value = value);
        try {
          await ref.read(apiProvider).patch('/api/account', {widget.field: value});
          widget.onChanged();
        } on ApiException catch (error) {
          setState(() => _value = !value);
          if (context.mounted) showError(context, error);
        }
      },
    );
  }
}
