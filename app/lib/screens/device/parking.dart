import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';

/// Parking of a vehicle: the current one (or null), the latest position and the proposal at
/// the ignition off
final parkingProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/parking') as Map<String, dynamic>,
);

const _remindChoices = [0, 5, 10, 15, 30, 60];

/// Result of the sheet that ends the parking
const _stop = 'stop';

/// Chip of the live panel: start the parking, or its state (end of the ticket) to change it
class ParkingChip extends ConsumerWidget {
  const ParkingChip({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(parkingProvider(deviceId)).value;
    if (state == null) return const SizedBox.shrink();
    final parking = state['parking'] as Map<String, dynamic>?;
    final end = parking?['expiresAt'] == null ? null : DateTime.parse(parking!['expiresAt'] as String).toLocal();
    final label = parking == null
        ? l.parkHere
        : end == null
            ? l.parkingActive(formatTime(DateTime.parse(parking['startedAt'] as String).toLocal()))
            : end.isBefore(DateTime.now())
                ? l.parkingExpired(formatTime(end))
                : l.parkingUntil(formatTime(end));
    return ActionChip(
      key: const Key('parkingChip'),
      avatar: Icon(Icons.local_parking, size: 18, color: end != null && end.isBefore(DateTime.now()) ? Colors.red : null),
      label: Text(label),
      onPressed: () => editParking(context, ref, deviceId, state),
    );
  }
}

/// Sheet of the parking, then the request: started or changed, or ended
Future<void> editParking(BuildContext context, WidgetRef ref, int deviceId, Map<String, dynamic> state) async {
  final l = context.l10n;
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ParkingSheet(state: state),
  );
  if (result == null || !context.mounted) return;
  final api = ref.read(apiProvider);
  try {
    if (result == _stop) {
      await api.delete('/api/devices/$deviceId/parking');
    } else {
      await api.put('/api/devices/$deviceId/parking', result);
    }
    ref.invalidate(parkingProvider(deviceId));
    if (context.mounted) showMessage(context, result == _stop ? l.parkingStopped : l.parkingSaved);
  } on ApiException catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class _ParkingSheet extends StatefulWidget {
  const _ParkingSheet({required this.state});

  final Map<String, dynamic> state;

  @override
  State<_ParkingSheet> createState() => _ParkingSheetState();
}

class _ParkingSheetState extends State<_ParkingSheet> {
  late final Map<String, dynamic>? _parking = widget.state['parking'] as Map<String, dynamic>?;
  late bool _hasEnd = _parking == null || _parking['expiresAt'] != null;
  // A new ticket: one hour from now, to the next quarter
  late DateTime _end = _parking?['expiresAt'] != null ? DateTime.parse(_parking!['expiresAt'] as String).toLocal() : _nextHour();
  late int _remind = _parking?['remindMinutes'] as int? ?? 10;
  late final _note = TextEditingController(text: _parking?['note'] as String? ?? '');

  static DateTime _nextHour() {
    final later = DateTime.now().add(const Duration(hours: 1));
    return DateTime(later.year, later.month, later.day, later.hour, (later.minute / 15).ceil() * 15);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: _end, firstDate: now, lastDate: now.add(const Duration(days: 31)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (time == null) return;
    setState(() => _end = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final placeless = _parking == null ? widget.state['position'] == null : _parking['lat'] == null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.parkingTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(l.parkingHint, style: theme.textTheme.bodySmall),
            if (placeless) ...[
              const SizedBox(height: 8),
              Text(l.parkingNoPlace, key: const Key('parkingNoPlace'), style: TextStyle(color: theme.colorScheme.error)),
            ],
            SwitchListTile(
              key: const Key('parkingHasEnd'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.parkingHasEnd),
              subtitle: Text(l.parkingHasEndHint),
              value: _hasEnd,
              onChanged: (value) => setState(() => _hasEnd = value),
            ),
            if (_hasEnd) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(l.parkingEnd(formatDayTime(_end))),
                trailing: TextButton(key: const Key('parkingEnd'), onPressed: _pickEnd, child: Text(l.parkingChangeEnd)),
              ),
              DropdownButtonFormField<int>(
                key: const Key('parkingRemind'),
                initialValue: _remindChoices.contains(_remind) ? _remind : 10,
                decoration: InputDecoration(labelText: l.parkingRemind),
                items: [
                  for (final minutes in _remindChoices)
                    DropdownMenuItem(value: minutes, child: Text(minutes == 0 ? l.parkingRemindNone : l.parkingRemindBefore(minutes))),
                ],
                onChanged: (value) => setState(() => _remind = value!),
              ),
            ],
            TextField(
              key: const Key('parkingNote'),
              controller: _note,
              maxLength: 200,
              decoration: InputDecoration(labelText: l.parkingNote),
            ),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              if (_parking != null)
                TextButton(key: const Key('parkingStop'), onPressed: () => Navigator.pop(context, _stop), child: Text(l.parkingStop)),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
              FilledButton(
                key: const Key('parkingSave'),
                onPressed: () => Navigator.pop(context, {
                  'expiresAt': _hasEnd ? _end.toUtc().toIso8601String() : null,
                  'remindMinutes': _remind,
                  'note': _note.text.trim(),
                }),
                child: Text(_parking == null ? l.parkingStart : l.save),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Setting of a tracker: a notification at the ignition off suggests the parking
class ParkingPromptSwitch extends ConsumerWidget {
  const ParkingPromptSwitch({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(parkingProvider(deviceId)).value;
    return SwitchListTile(
      key: const Key('parkingPrompt'),
      secondary: const Icon(Icons.local_parking),
      title: Text(l.parkingPrompt),
      subtitle: Text(l.parkingPromptHint),
      value: state?['prompt'] == true,
      onChanged: state == null
          ? null
          : (value) async {
              try {
                await ref.read(apiProvider).put('/api/devices/$deviceId/parking/prompt', {'enabled': value});
                ref.invalidate(parkingProvider(deviceId));
              } on ApiException catch (error) {
                if (context.mounted) showError(context, error);
              }
            },
    );
  }
}
