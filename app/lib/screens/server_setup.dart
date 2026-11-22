import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/providers.dart';

/// First start of the Android app: address of the platform
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _url = TextEditingController();
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).connect(_url.text);
    } catch (_) {
      if (mounted) showMessage(context, context.l10n.serverUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.location_on, size: 64),
                const SizedBox(height: 16),
                Text(l.appTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(l.serverAddress, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('server'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.serverLabel, hintText: 'tracking.example.com', border: const OutlineInputBorder()),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.continueLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
