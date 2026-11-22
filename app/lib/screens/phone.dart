import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/phone_tracker.dart';
import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import 'add_device.dart' show deviceColors;

/// Text of a refused location permission
String permissionText(AppLocalizations l, String reason) => switch (reason) {
      'disabled' => l.phoneLocationOff,
      'deniedForever' => l.phoneDeniedForever,
      _ => l.phoneDenied,
    };

/// Shares the position of this phone with friends, without a tracker
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  late final PhoneTracker _phone = ref.read(phoneTrackerProvider);
  // "All the time" is granted in the settings of the system: checked when back
  late final _lifecycle = AppLifecycleListener(onResume: _phone.checkBackground);
  final _name = TextEditingController();
  Color _color = deviceColors[2];
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty) _name.text = context.l10n.phoneDefaultName(ref.read(sessionProvider).user?.name ?? '');
  }

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final refused = await _phone.enable(name: name, color: colorToHex(_color));
      ref.invalidate(devicesProvider);
      if (refused != null && mounted) showMessage(context, permissionText(l, refused));
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.phoneTitle)),
      body: ListenableBuilder(
        listenable: _phone,
        builder: (context, _) {
          final fix = _phone.status.lastFix;
          final queued = _phone.status.queued;
          final paused = _phone.paused;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(l.phoneIntro),
            const SizedBox(height: 8),
            Text(_phone.supported ? l.phoneAndroidHint : l.phoneOnlyAndroid, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            if (!_phone.supported)
              const SizedBox.shrink()
            else ...[
            if (_phone.gone && !_phone.sharing)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(l.phoneGone, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (_phone.sharing) ...[
              Card(
                child: ListTile(
                  leading: Icon(paused ? Icons.pause_circle : Icons.share_location, color: paused ? Colors.orange : Colors.green),
                  title: Text(paused ? l.phonePausedUntil(formatTime(_phone.status.pausedUntil!)) : l.phoneSharing),
                  subtitle: Text([
                    fix == null ? l.phoneWaitingFix : l.phoneLastFix(formatTime(fix.time), '${fix.accuracy.round()}'),
                    if (queued > 0) l.phoneQueued(queued),
                  ].join('\n')),
                  trailing: paused
                      ? TextButton(onPressed: () => _phone.pause(null), child: Text(l.phoneResume))
                      : TextButton(onPressed: () => _phone.pause(phonePause), child: Text(l.phonePauseHour)),
                ),
              ),
              if (!_phone.background)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: Text(l.phoneBackgroundHint, style: theme.textTheme.bodySmall),
                    trailing: TextButton(onPressed: _phone.allowBackground, child: Text(l.phoneBackgroundAllow)),
                  ),
                ),
              const SizedBox(height: 12),
              OverflowBar(spacing: 8, alignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.group),
                  label: Text(l.phoneOpenDevice),
                  onPressed: () => context.go('/devices/${_phone.deviceId}?tab=4'),
                ),
                FilledButton.icon(icon: const Icon(Icons.stop), label: Text(l.phoneStop), onPressed: _phone.disable),
              ]),
            ] else ...[
              if (_phone.deviceId == null) ...[
                TextField(key: const Key('phoneName'), controller: _name, maxLength: 60, decoration: InputDecoration(labelText: l.phoneName)),
                Wrap(spacing: 8, children: [
                  for (final color in deviceColors)
                    InkWell(
                      onTap: () => setState(() => _color = color),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: color,
                        child: _color.toARGB32() == color.toARGB32() ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('phoneStart'),
                  icon: const Icon(Icons.share_location),
                  label: Text(l.phoneStart),
                  onPressed: _busy ? null : _start,
                ),
              ),
            ],
            ],
          ]);
        },
      ),
    );
  }
}
