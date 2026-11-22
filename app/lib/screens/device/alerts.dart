import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';

// Alerts of the logged user on a device they see, owner or viewer: long stop outside their
// areas; low battery of a phone shared with them

/// Hours of the long stop notification
const stopAlertChoices = [1, 2, 4, 8, 12, 24, 48];

/// Battery (%) of the low battery notification
const batteryAlertChoices = [10, 15, 20, 30, 40, 50];

String stopAlertText(AppLocalizations l, int? hours) => switch (hours) {
      null => l.stopAlertOff,
      1 => l.stopAlertAfterOne,
      _ => l.stopAlertAfter(hours),
    };

String batteryAlertText(AppLocalizations l, int? percent) => percent == null ? l.stopAlertOff : l.batteryAlertAt(percent);

/// Asks the long stop hours and saves them; false when dismissed or failed
Future<bool> chooseStopAlert(BuildContext context, WidgetRef ref, Device device) async {
  final l = context.l10n;
  final hours = await _pick(context, l.stopAlert, 'stop', stopAlertChoices, (value) => stopAlertText(l, value));
  if (hours == null || !context.mounted) return false;
  final saved = await _save(context, ref, device, {'stopAlertHours': hours.value});
  if (saved) device.stopAlertHours = hours.value;
  return saved;
}

/// Asks the low battery threshold of a shared phone and saves it
Future<bool> chooseBatteryAlert(BuildContext context, WidgetRef ref, Device device) async {
  final l = context.l10n;
  final percent = await _pick(context, l.batteryAlert, 'battery', batteryAlertChoices, (value) => batteryAlertText(l, value));
  if (percent == null || !context.mounted) return false;
  final saved = await _save(context, ref, device, {'batteryAlert': percent.value});
  if (saved) device.batteryAlert = percent.value;
  return saved;
}

/// Off or one of the choices; null when dismissed
Future<({int? value})?> _pick(BuildContext context, String title, String key, List<int> choices, String Function(int?) label) =>
    showDialog<({int? value})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final value in [null, ...choices])
            SimpleDialogOption(
              key: Key('$key${value ?? 0}'),
              onPressed: () => Navigator.pop(context, (value: value)),
              child: Text(label(value)),
            ),
        ],
      ),
    );

Future<bool> _save(BuildContext context, WidgetRef ref, Device device, Map<String, dynamic> body) async {
  try {
    await ref.read(apiProvider).patch('/api/devices/${device.id}/alerts', body);
    ref.invalidate(devicesProvider);
    return true;
  } on ApiException catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}
