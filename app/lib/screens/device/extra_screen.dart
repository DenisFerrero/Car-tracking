import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';

final extraProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/extra') as Map<String, dynamic>,
);

/// Value of a field as text: numbers in the language of the app, lists and objects as JSON
String extraValue(Object? value) => switch (value) {
      null => '—',
      String() => value,
      int() => formatInt(value),
      double() => formatDecimal(value, value == value.roundToDouble() ? 0 : 2),
      bool() => value ? '✓' : '✗',
      _ => jsonEncode(value),
    };

/// Extra data of a tracker: fields read from another board of the vehicle, shown as they
/// arrive (no charts). Latest value of every field, then the readings, newest first.
class ExtraScreen extends ConsumerWidget {
  const ExtraScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    ref.listen(liveEventsProvider, (previous, next) {
      final event = next.value;
      if (event?['type'] == 'extra' && event?['deviceId'] == deviceId) ref.invalidate(extraProvider(deviceId));
    });
    return Scaffold(
      appBar: AppBar(title: Text(l.extraData)),
      body: ref.watch(extraProvider(deviceId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(errorText(l, error))),
            data: (data) {
              final latest = (data['latest'] as List).cast<Map<String, dynamic>>();
              final items = (data['items'] as List).cast<Map<String, dynamic>>();
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(extraProvider(deviceId)),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(l.extraIntro, style: Theme.of(context).textTheme.bodySmall),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Center(child: Text(l.extraEmpty, key: const Key('extraEmpty'))),
                    )
                  else ...[
                    const SizedBox(height: 16),
                    Text(l.extraLatest, style: Theme.of(context).textTheme.titleMedium),
                    Card(
                      child: Column(children: [
                        for (final field in latest)
                          ListTile(
                            dense: true,
                            title: Text(field['key'] as String),
                            subtitle: Text(formatDayTime(DateTime.parse(field['time'] as String).toLocal())),
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 200),
                              child: Text(extraValue(field['value']), textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleSmall),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text(l.extraReadings(items.length), style: Theme.of(context).textTheme.titleMedium),
                    for (final item in items)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(formatFull(DateTime.parse(item['time'] as String).toLocal())),
                        subtitle: Text(l.extraFields((item['data'] as Map).length)),
                        children: [
                          for (final MapEntry(:key, :value) in (item['data'] as Map<String, dynamic>).entries)
                            ListTile(dense: true, title: Text(key), trailing: Text(extraValue(value))),
                        ],
                      ),
                  ],
                ]),
              );
            },
          ),
    );
  }
}
