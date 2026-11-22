import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';

final maintenanceProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/maintenance') as Map<String, dynamic>,
);

const maintenanceKinds = ['service', 'inspection', 'insurance', 'tax', 'tyres', 'other'];

String deadlineName(BuildContext context, Map<String, dynamic> item) =>
    (item['title'] as String).isNotEmpty ? item['title'] as String : maintenanceKindLabel(context.l10n, item['kind'] as String);

/// Deadlines of a car: service by km, inspection, insurance and tax by date. The owner
/// enters the odometer once, then it follows the km of the trips.
class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final api = ref.read(apiProvider);

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(maintenanceProvider(deviceId));
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.maintenance)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addDeadline'),
        onPressed: () async {
          final body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const DeadlineEditor());
          if (body != null) await guard(() => api.post('/api/devices/$deviceId/maintenance', body));
        },
        icon: const Icon(Icons.add),
        label: Text(l.addDeadline),
      ),
      body: ref.watch(maintenanceProvider(deviceId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(errorText(l, error))),
            data: (data) {
              final odometer = data['odometerKm'] as int?;
              final items = (data['items'] as List).cast<Map<String, dynamic>>();
              final log = (data['log'] as List).cast<Map<String, dynamic>>();
              return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(l.maintenanceHint)),
                Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    key: const Key('odometer'),
                    leading: const Icon(Icons.speed),
                    title: Text(l.odometer),
                    subtitle: Text(odometer == null ? l.odometerUnset : l.odometerValue(formatInt(odometer))),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      final km = await askNumber(context, l.odometer, l.odometerHint, odometer);
                      if (km != null) await guard(() => api.put('/api/devices/$deviceId/odometer', {'km': km}));
                    },
                  ),
                ),
                if (items.isEmpty) ListTile(title: Text(l.noDeadlines)),
                for (final item in items)
                  ListTile(
                    key: Key('deadline${item['id']}'),
                    leading: Icon(
                      Icons.event,
                      color: switch (item['state']) { 'due' => Colors.red, 'soon' => Colors.orange, _ => Colors.green },
                    ),
                    title: Text(deadlineName(context, item)),
                    subtitle: Text([
                      remainingText(l, item['remainingDays'] as int?, item['remainingKm'] as int?),
                      if (item['dueDate'] != null) formatDay(DateTime.parse(item['dueDate'] as String)),
                      if (item['dueKm'] != null) '${formatInt(item['dueKm'] as int)} km',
                      if (item['everyMonths'] != null) l.deadlineEvery(l.monthsShort(item['everyMonths'] as int)),
                      if (item['everyKm'] != null) l.deadlineEvery('${formatInt(item['everyKm'] as int)} km'),
                    ].where((text) => text.isNotEmpty).join(' · ')),
                    onTap: () async {
                      final body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => DeadlineEditor(item: item));
                      if (body != null) await guard(() => api.patch('/api/maintenance/${item['id']}', body));
                    },
                    trailing: PopupMenuButton<String>(
                      key: Key('deadlineMenu${item['id']}'),
                      onSelected: (action) => guard(() async {
                        if (action == 'done') {
                          final km = await askNumber(context, l.deadlineDoneTitle(deadlineName(context, item)), l.deadlineDoneHint, odometer,
                              label: l.deadlineDoneKm);
                          if (km != null) await api.post('/api/maintenance/${item['id']}/done', {'km': km});
                        } else if (await confirmDelete(context, l.deleteDeadline)) {
                          await api.delete('/api/maintenance/${item['id']}');
                        }
                      }),
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'done', child: Text(l.deadlineDone)),
                        PopupMenuItem(value: 'delete', child: Text(l.delete)),
                      ],
                    ),
                  ),
                if (log.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(l.maintenanceLog)),
                  for (final entry in log)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(deadlineName(context, entry)),
                      subtitle: Text([
                        formatDay(DateTime.parse(entry['doneOn'] as String)),
                        if (entry['km'] != null) '${formatInt(entry['km'] as int)} km',
                        if ((entry['note'] as String).isNotEmpty) entry['note'] as String,
                      ].join(' · ')),
                    ),
                ],
              ]);
            },
          ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.cancel)),
          FilledButton(key: const Key('confirmDelete'), onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.delete)),
        ],
      ),
    ) ??
    false;

/// A whole number of km: null when cancelled
Future<int?> askNumber(BuildContext context, String title, String hint, int? initial, {String? label}) =>
    showDialog<int>(context: context, builder: (_) => _NumberDialog(title: title, hint: hint, initial: initial, label: label));

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.hint, required this.initial, this.label});

  final String title;
  final String hint;
  final int? initial;
  final String? label;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: widget.initial?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 0) return setState(() => _error = context.l10n.invalidNumber);
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.hint),
        TextField(
          key: const Key('numberField'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: widget.label ?? 'km', suffixText: 'km', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('numberSave'), onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}

/// New deadline or changes of one: returns the body of the request
class DeadlineEditor extends StatefulWidget {
  const DeadlineEditor({super.key, this.item});

  final Map<String, dynamic>? item;

  @override
  State<DeadlineEditor> createState() => _DeadlineEditorState();
}

class _DeadlineEditorState extends State<DeadlineEditor> {
  late String _kind = widget.item?['kind'] as String? ?? 'service';
  late DateTime? _date = widget.item?['dueDate'] == null ? null : DateTime.parse(widget.item!['dueDate'] as String);
  TextEditingController _text(String key, [int? fallback]) =>
      TextEditingController(text: (widget.item?[key] ?? fallback)?.toString() ?? '');
  late final _title = _text('title');
  late final _dueKm = _text('dueKm');
  late final _everyMonths = _text('everyMonths');
  late final _everyKm = _text('everyKm');
  late final _remindDays = _text('remindDays', 30);
  late final _remindKm = _text('remindKm', 1000);
  late final _note = _text('note');
  String? _error;

  @override
  void dispose() {
    for (final controller in [_title, _dueKm, _everyMonths, _everyKm, _remindDays, _remindKm, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, TextEditingController controller, String label, {bool number = true}) => TextField(
        key: Key(key),
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      );

  void _submit() {
    final l = context.l10n;
    int? number(TextEditingController controller) => int.tryParse(controller.text.trim());
    final dueKm = number(_dueKm);
    if (_kind == 'other' && _title.text.trim().isEmpty) return setState(() => _error = l.deadlineNeedsTitle);
    if (_date == null && dueKm == null) return setState(() => _error = l.deadlineNeedsDue);
    final day = _date == null
        ? null
        : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
    Navigator.pop(context, {
      'kind': _kind,
      'title': _title.text.trim(),
      'dueDate': day,
      'dueKm': dueKm,
      'everyMonths': number(_everyMonths),
      'everyKm': number(_everyKm),
      'remindDays': number(_remindDays) ?? 30,
      'remindKm': number(_remindKm) ?? 1000,
      'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.item == null ? l.addDeadline : l.editDeadline),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            key: const Key('deadlineKind'),
            initialValue: _kind,
            decoration: InputDecoration(labelText: l.deadlineKind),
            items: [for (final kind in maintenanceKinds) DropdownMenuItem(value: kind, child: Text(maintenanceKindLabel(l, kind)))],
            onChanged: (value) => setState(() => _kind = value!),
          ),
          // Custom deadline: the description is its name
          _field('deadlineTitle', _title, _kind == 'other' ? l.deadlineTitleRequired : l.deadlineTitle, number: false),
          const SizedBox(height: 8),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_date == null ? l.deadlineNoDate : formatDay(_date!)),
            TextButton.icon(
              key: const Key('deadlineDate'),
              icon: const Icon(Icons.event),
              label: Text(l.deadlineDate),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? now,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            if (_date != null)
              IconButton(key: const Key('deadlineClearDate'), icon: const Icon(Icons.clear), onPressed: () => setState(() => _date = null)),
          ]),
          _field('deadlineKm', _dueKm, l.deadlineKm),
          _field('deadlineEveryMonths', _everyMonths, l.deadlineEveryMonths),
          _field('deadlineEveryKm', _everyKm, l.deadlineEveryKm),
          _field('deadlineRemindDays', _remindDays, l.deadlineRemindDays),
          _field('deadlineRemindKm', _remindKm, l.deadlineRemindKm),
          _field('deadlineNote', _note, l.deadlineNote, number: false),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('deadlineSave'), onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}
