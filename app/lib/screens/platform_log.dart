import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/providers.dart';

/// Log of the platform of a kind over some days: groups of equal entries
final platformLogProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, int)>((ref, query) async {
  final (kind, days) = query;
  return await ref.watch(apiProvider).get('/api/admin/logs', {'kind': kind, 'days': '$days'}) as Map<String, dynamic>;
});

/// Milliseconds as "850 ms" or "2,4 s"
String formatMs(num ms) => ms < 1000 ? '${ms.round()} ms' : '${formatDecimal(ms / 1000, 1)} s';

/// Administration: errors, warnings, slow requests and slow queries of the platform,
/// grouped, the most frequent first; the details of the latest one can be copied.
class PlatformLogScreen extends ConsumerStatefulWidget {
  const PlatformLogScreen({super.key});

  @override
  ConsumerState<PlatformLogScreen> createState() => _PlatformLogScreenState();
}

class _PlatformLogScreenState extends ConsumerState<PlatformLogScreen> {
  String _kind = 'error';
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final data = ref.watch(platformLogProvider((_kind, _days)));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.platformLog),
        actions: [
          PopupMenuButton<int>(
            key: const Key('logDays'),
            icon: const Icon(Icons.date_range),
            tooltip: l.dashboardPeriod,
            onSelected: (days) => setState(() => _days = days),
            itemBuilder: (_) => [
              for (final (days, label) in [(1, l.periodLast24h), (7, l.periodLast7d), (30, l.periodLast30d)])
                CheckedPopupMenuItem(value: days, checked: days == _days, child: Text(label)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(platformLogProvider),
        child: ListView(padding: readable(context, const EdgeInsets.fromLTRB(8, 8, 8, 24)), children: [
          // Chips on more rows: the four kinds fit a phone too
          Wrap(key: const Key('logKind'), spacing: 8, runSpacing: 4, children: [
            for (final (kind, label, icon) in [
              ('error', l.logErrors, Icons.error_outline),
              ('warning', l.logWarnings, Icons.warning_amber),
              ('slow_request', l.logSlowRequests, Icons.timer_outlined),
              ('slow_query', l.logSlowQueries, Icons.storage),
            ])
              ChoiceChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: _kind == kind,
                showCheckmark: false,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ]),
          ...data.when(
            loading: () => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
            error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
            data: (log) => _entries(context, log),
          ),
        ]),
      ),
    );
  }

  List<Widget> _entries(BuildContext context, Map<String, dynamic> log) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final days = log['retentionDays'] as int;
    final groups = (log['groups'] as List).cast<Map<String, dynamic>>();
    final hint = switch (_kind) {
      'slow_request' => l.logRequestsHint(log['slowRequestMs'] as int, days),
      'slow_query' => l.logQueriesHint(log['slowQueryMs'] as int, days),
      _ => l.logErrorsHint(days),
    };
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: Text(hint, style: theme.textTheme.bodySmall),
      ),
      if (_kind == 'slow_query' && log['slowQueries'] != true)
        Card(
          key: const Key('logQueriesOff'),
          child: ListTile(leading: const Icon(Icons.info_outline), title: Text(l.logQueriesOff)),
        ),
      if (groups.isEmpty)
        Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l.logEmpty, key: const Key('logEmpty'))))
      else
        for (final (index, group) in groups.indexed) _Group(key: Key('logGroup$index'), kind: _kind, group: group),
    ];
  }
}

class _Group extends StatelessWidget {
  const _Group({super.key, required this.kind, required this.group});

  final String kind;
  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final details = (group['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    final stack = details['stack'] as String?;
    final last = DateTime.parse(group['last'] as String).toLocal();
    final maxMs = group['maxMs'] as num?;
    final avgMs = group['avgMs'] as num?;
    final calls = group['calls'] as int?;
    final subtitle = [
      group['source'] as String,
      l.logTimes(group['count'] as int),
      if (calls != null) l.logCalls(calls),
      if (maxMs != null) l.logDurations(formatMs(avgMs ?? maxMs), formatMs(maxMs)),
      l.logLast(formatAgo(l, last)),
    ].join(' · ');
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final fields = [for (final entry in details.entries) if (entry.key != 'stack') '${entry.key}: ${entry.value}'];
    return Card(
      child: ExpansionTile(
        leading: Icon(switch (kind) {
          'error' => Icons.error_outline,
          'warning' => Icons.warning_amber,
          'slow_request' => Icons.timer_outlined,
          _ => Icons.storage,
        }, color: kind == 'error' ? theme.colorScheme.error : theme.colorScheme.secondary),
        title: Text(group['message'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: kind == 'slow_query' ? mono : null),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.logFirst(formatFull(DateTime.parse(group['first'] as String).toLocal())), style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          if (kind == 'slow_query') SelectableText(group['message'] as String, style: mono),
          if (fields.isNotEmpty) SelectableText(fields.join('\n'), style: mono),
          if (stack != null) ...[
            const SizedBox(height: 8),
            SelectableText(stack, key: const Key('logStack'), style: mono),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('logCopy'),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(group)));
                showMessage(context, l.logCopied);
              },
            ),
          ),
        ],
      ),
    );
  }
}
