import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';

/// Firmware of a tracker: version, newer images of its variant, state of the update
final firmwareProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, deviceId) async => await ref.watch(apiProvider).get('/api/devices/$deviceId/firmware') as Map<String, dynamic>,
);

String firmwareStatusText(AppLocalizations l, Map<String, dynamic> update) {
  final version = update['version'] as String;
  final text = switch (update['status'] as String?) {
    null => (update['sent'] as int) > 0 ? l.firmwareDownloading(version) : l.firmwareWaiting(version),
    'installed' => l.firmwareRebooting(version),
    'done' => l.firmwareDone(version),
    'not_applied' => l.firmwareNotApplied(version),
    _ => l.firmwareFailed(version),
  };
  return update['automatic'] == true ? '$text · ${l.firmwareAutomatic}' : text;
}

/// Update over the air: the owner installs a newer version, the tracker downloads it at
/// the next connection (about 1.2 MB of the SIM) and reboots with it. Builds with
/// AUTO_UPDATE ask every day and install the new official versions by themselves, if the
/// owner allows it.
class FirmwareSection extends ConsumerWidget {
  const FirmwareSection({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    ref.listen(liveEventsProvider, (previous, next) {
      final event = next.value;
      if (event?['type'] == 'firmware' && event?['deviceId'] == deviceId) ref.invalidate(firmwareProvider(deviceId));
    });

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(firmwareProvider(deviceId));
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    Future<void> install(Map<String, dynamic> image) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.firmwareInstallTitle(image['version'] as String)),
          content: Text([
            if ((image['notes'] as String).isNotEmpty) image['notes'] as String,
            l.firmwareInstallBody(formatDecimal((image['size'] as int) / 1024 / 1024, 1)),
          ].join('\n\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.firmwareInstall)),
          ],
        ),
      );
      if (ok == true) await guard(() => ref.read(apiProvider).post('/api/devices/$deviceId/firmware', {'firmwareId': image['id']}));
    }

    return ref.watch(firmwareProvider(deviceId)).when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => ListTile(leading: const Icon(Icons.system_update), title: Text(errorText(l, error))),
          data: (data) {
            final update = data['update'] as Map<String, dynamic>?;
            final pending = update != null && update['finishedAt'] == null;
            final available = (data['available'] as List).cast<Map<String, dynamic>>();
            return Column(children: [
              if (update != null)
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: Text(firmwareStatusText(l, update)),
                  subtitle: pending && (update['sent'] as int) > 0
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(value: (update['sent'] as int) / (update['size'] as int)),
                        )
                      : null,
                  trailing: pending
                      ? TextButton(
                          onPressed: () => guard(() => ref.read(apiProvider).delete('/api/devices/$deviceId/firmware')),
                          child: Text(l.cancel),
                        )
                      : null,
                ),
              if (!pending && available.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.new_releases, color: Colors.orange),
                  title: Text(l.firmwareAvailable(available.first['version'] as String)),
                  subtitle: (available.first['notes'] as String).isEmpty ? null : Text(available.first['notes'] as String),
                  trailing: FilledButton(onPressed: () => install(available.first), child: Text(l.firmwareInstall)),
                ),
              if (!pending && available.isEmpty && update == null)
                ListTile(leading: const Icon(Icons.verified), title: Text(l.firmwareUpToDate(data['version'] as String))),
              SwitchListTile(
                key: const Key('autoUpdate'),
                secondary: const Icon(Icons.update),
                title: Text(l.autoUpdate),
                subtitle: Text(data['updateCheckedAt'] == null
                    ? l.autoUpdateNever
                    : l.autoUpdateChecked(formatDayTime(DateTime.parse(data['updateCheckedAt'] as String).toLocal()))),
                value: data['autoUpdate'] as bool? ?? true,
                onChanged: (value) => guard(() => ref.read(apiProvider).put('/api/devices/$deviceId/firmware/auto', {'enabled': value})),
              ),
            ]);
          },
        );
  }
}
