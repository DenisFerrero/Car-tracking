import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';

/// Active temporary links of a device (owner)
final liveLinksProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/links') as Map<String, dynamic>,
);

const _hourChoices = [1, 2, 4, 8, 24];

/// Settings of a device: links to the live position for who has no account, created for a
/// few hours, shown once (only their hash is stored), revocable
class LiveLinksSection extends ConsumerWidget {
  const LiveLinksSection({super.key, required this.deviceId});

  final int deviceId;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final choice = await showDialog<({int hours, String label})>(context: context, builder: (_) => const _NewLinkDialog());
    if (choice == null || !context.mounted) return;
    try {
      final created = await ref.read(apiProvider).post('/api/devices/$deviceId/links', {'hours': choice.hours, 'label': choice.label})
          as Map<String, dynamic>;
      ref.invalidate(liveLinksProvider(deviceId));
      if (!context.mounted) return;
      final url = created['url'] as String;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.liveLinkUntil(formatDayTime(DateTime.parse(created['expiresAt'] as String).toLocal()))),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.liveLinkCreated),
            const SizedBox(height: 12),
            SelectableText(url, key: const Key('liveLinkUrl'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ]),
          actions: [
            TextButton(
              key: const Key('liveLinkCopy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                showMessage(context, l.liveLinkCopied);
              },
              child: Text(l.copy),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, int id) async {
    try {
      await ref.read(apiProvider).delete('/api/links/$id');
      ref.invalidate(liveLinksProvider(deviceId));
      if (context.mounted) showMessage(context, context.l10n.liveLinkRevoked);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l.liveLinksHint, style: Theme.of(context).textTheme.bodySmall)),
      ...ref.watch(liveLinksProvider(deviceId)).when(
            loading: () => [const LinearProgressIndicator()],
            error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
            data: (data) {
              final links = (data['links'] as List).cast<Map<String, dynamic>>();
              return [
                if (links.isEmpty) ListTile(title: Text(l.liveLinksNone)),
                for (final link in links)
                  ListTile(
                    key: Key('liveLink_${link['id']}'),
                    leading: const Icon(Icons.link),
                    title: Text((link['label'] as String).isNotEmpty
                        ? link['label'] as String
                        : l.liveLinkUntil(formatDayTime(DateTime.parse(link['expiresAt'] as String).toLocal()))),
                    subtitle: Text([
                      if ((link['label'] as String).isNotEmpty) l.liveLinkUntil(formatDayTime(DateTime.parse(link['expiresAt'] as String).toLocal())),
                      link['lastViewedAt'] == null
                          ? l.liveLinkNotViewed
                          : l.liveLinkViewed(formatAgo(l, DateTime.parse(link['lastViewedAt'] as String).toLocal())),
                    ].join(' · ')),
                    trailing: IconButton(
                      key: Key('liveLinkRevoke_${link['id']}'),
                      tooltip: l.liveLinkRevoke,
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _revoke(context, ref, link['id'] as int),
                    ),
                  ),
                if (links.length < (data['max'] as int))
                  ListTile(
                    key: const Key('liveLinkNew'),
                    leading: const Icon(Icons.add_link),
                    title: Text(l.liveLinkNew),
                    onTap: () => _create(context, ref),
                  ),
              ];
            },
          ),
    ]);
  }
}

class _NewLinkDialog extends StatefulWidget {
  const _NewLinkDialog();

  @override
  State<_NewLinkDialog> createState() => _NewLinkDialogState();
}

class _NewLinkDialogState extends State<_NewLinkDialog> {
  final _label = TextEditingController();
  int _hours = 2;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.liveLinkNew),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const Key('liveLinkLabel'),
          controller: _label,
          maxLength: 40,
          decoration: InputDecoration(labelText: l.liveLinkLabel),
        ),
        DropdownButtonFormField<int>(
          key: const Key('liveLinkHours'),
          initialValue: _hours,
          decoration: InputDecoration(labelText: l.liveLinkHours),
          items: [for (final hours in _hourChoices) DropdownMenuItem(value: hours, child: Text(l.liveLinkDuration(hours)))],
          onChanged: (value) => setState(() => _hours = value!),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          key: const Key('liveLinkCreate'),
          onPressed: () => Navigator.pop(context, (hours: _hours, label: _label.text.trim())),
          child: Text(l.liveLinkNew),
        ),
      ],
    );
  }
}
