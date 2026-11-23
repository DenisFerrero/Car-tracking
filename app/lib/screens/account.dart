import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/providers.dart';
import '../core/push.dart';
import '../l10n/app_localizations.dart';
import 'summary_screen.dart';

final _accountProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => await ref.watch(apiProvider).get('/api/account') as Map<String, dynamic>,
);

/// Names of the languages, each in its own language
const languageNames = {'it': 'Italiano', 'en': 'English'};

/// Asks the TOTP code: sensitive changes need it when the login is older than 15 minutes
Future<String?> askTotp(BuildContext context, {String? title}) {
  final l = context.l10n;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title ?? l.confirmWithCode),
      content: TextField(
        key: const Key('totp'),
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        decoration: InputDecoration(labelText: l.authenticatorCode),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l.confirm)),
      ],
    ),
  );
}

/// Runs an action, asking the TOTP code and retrying when the backend wants a step up
Future<T?> withStepUp<T>(BuildContext context, Future<T> Function(String? code) action) async {
  try {
    return await action(null);
  } on ApiException catch (error) {
    if (error.code != 'step_up_required' || !context.mounted) rethrow;
    final code = await askTotp(context);
    if (code == null || code.isEmpty) return null;
    return await action(code);
  }
}

DateTime _date(Object? value) => DateTime.parse(value as String).toLocal();

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = ref.watch(sessionProvider);
    final account = ref.watch(_accountProvider);
    final api = ref.read(apiProvider);

    Future<void> guard(Future<void> Function() action, [String? done]) async {
      try {
        await action();
        ref.invalidate(_accountProvider);
        if (context.mounted && done != null) showMessage(context, done);
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      } catch (_) {
        if (context.mounted) showMessage(context, l.operationCancelled);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(errorText(l, error))),
        data: (data) {
          final passkeys = (data['passkeys'] as List).cast<Map<String, dynamic>>();
          final sessions = (data['sessions'] as List).cast<Map<String, dynamic>>();
          final recoveryLeft = data['recoveryCodesLeft'] as int;
          return ListView(padding: readable(context), children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(session.user?.name ?? ''),
              subtitle: Text(session.user?.email ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: l.editName,
                onPressed: () async {
                  final name = await _prompt(context, l.nameLabel, session.user?.name ?? '');
                  if (name != null && name.isNotEmpty) await guard(() => session.rename(name));
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l.language),
              trailing: DropdownButton<String>(
                key: const Key('language'),
                value: session.language,
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) session.setLanguage(value);
                },
                items: [
                  for (final entry in languageNames.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: Text(l.friends),
              subtitle: Text(l.friendsSub),
              onTap: () => context.go('/account/friends'),
            ),
            ListTile(
              key: const Key('openSummary'),
              leading: const Icon(Icons.calendar_month),
              title: Text(l.monthlySummary),
              subtitle: Text(l.monthlySummarySub),
              onTap: () => context.go('/account/summary'),
            ),
            MonthlySummarySwitch(enabled: data['monthlySummary'] != false, onChanged: () => ref.invalidate(_accountProvider)),
            if (session.user?.isAdmin == true)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: Text(l.administration),
                subtitle: Text(l.administrationSub),
                onTap: () => context.go('/account/admin'),
              ),
            _header(context, l.passkeys),
            for (final passkey in passkeys)
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text(passkey['name'] as String),
                subtitle: Text([
                  l.passkeyCreatedAgo(formatAgo(l, _date(passkey['created_at']))),
                  if (passkey['last_used_at'] != null) l.passkeyUsedAgo(formatAgo(l, _date(passkey['last_used_at']))),
                  if (passkey['backed_up'] == true) l.passkeySynced,
                ].join()),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l.delete,
                  onPressed: () => guard(() async {
                    await withStepUp(context, (code) => api.delete(
                          '/api/account/passkeys/${Uri.encodeComponent(passkey['id'] as String)}',
                          {'code': ?code},
                        ));
                  }, l.passkeyRemoved),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l.addPasskey),
              subtitle: Text(l.addPasskeySub),
              onTap: () async {
                final name = await _prompt(context, l.passkeyName, api.web ? l.defaultPasskeyBrowser : l.defaultPasskeyPhone);
                if (name == null || name.isEmpty || !context.mounted) return;
                await guard(() async {
                  await withStepUp(context, (code) => session.addPasskey(name, code: code));
                }, l.passkeyAdded);
              },
            ),
            _header(context, l.security),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(l.changePassword),
              onTap: () => _changePassword(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.phonelink_lock),
              title: Text(l.changeAuthenticator),
              subtitle: Text(l.newPhone),
              onTap: () => _changeTotp(context, ref),
            ),
            ListTile(
              leading: Icon(Icons.key, color: recoveryLeft <= 3 ? Colors.orange : null),
              title: Text(l.recoveryTitle),
              subtitle: Text(l.recoveryLeft(recoveryLeft)),
              onTap: () => guard(() async {
                final result = await withStepUp(context, (code) => api.post('/api/account/recovery-codes', {'code': ?code}));
                if (result != null && context.mounted) {
                  await _showCodes(context, ((result as Map)['recoveryCodes'] as List).cast<String>());
                }
              }),
            ),
            _header(context, l.activeSessions),
            for (final s in sessions)
              ListTile(
                leading: Icon(s['client'] == 'app' ? Icons.phone_android : Icons.computer),
                title: Text(_agent(l, s['user_agent'] as String?) + (s['current'] == true ? l.thisSession : '')),
                subtitle: Text(l.sessionActive('${s['ip'] ?? ''}', formatAgo(l, _date(s['last_seen_at'])))),
                trailing: s['current'] == true
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l.disconnect,
                        onPressed: () => guard(() => api.delete('/api/account/sessions/${s['id']}')),
                      ),
              ),
            if (sessions.length > 1)
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l.disconnectOthers),
                onTap: () => guard(() => api.post('/api/account/sessions/revoke-others'), l.sessionsClosed),
              ),
            _header(context, l.app),
            if (!api.web)
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: Text(l.pushTitle),
                subtitle: Text(Push.configured && data['pushEnabled'] == true ? l.pushOn : l.pushOff),
              ),
            if (!api.web)
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(l.serverLabel),
                subtitle: Text(api.baseUrl),
                onTap: session.changeServer,
              ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(l.logout, style: const TextStyle(color: Colors.red)),
              onTap: session.logout,
            ),
            _header(context, l.yourData),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l.exportData),
              subtitle: Text(l.exportDataSub),
              onTap: () => guard(() => downloadFile(ref, '/api/account/export', 'application/json')),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
              title: Text(l.deleteAccount, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(l.deleteAccountSub),
              onTap: () async {
                final email = await _confirmDeletion(context, session.user?.email ?? '');
                if (email == null || !context.mounted) return;
                await guard(() async => withStepUp(context, (code) => session.deleteAccount(email, code: code)));
              },
            ),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  /// What is deleted, and the email typed again: null when cancelled
  static Future<String?> _confirmDeletion(BuildContext context, String email) {
    final l = context.l10n;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.deleteAccountTitle),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.deleteAccountBody),
            const SizedBox(height: 12),
            TextField(
              key: const Key('deleteEmail'),
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.deleteAccountEmail(email)),
              onChanged: (_) => setState(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: controller.text.trim().toLowerCase() == email.toLowerCase() ? () => Navigator.pop(context, controller.text.trim()) : null,
              child: Text(l.deleteAccount),
            ),
          ],
        ),
      ),
    );
  }

  static String _agent(AppLocalizations l, String? userAgent) {
    final ua = userAgent ?? '';
    if (ua.contains('Android')) return 'Android';
    if (ua.contains('iPhone') || ua.contains('iPad')) return 'iOS';
    if (ua.contains('Firefox')) return 'Firefox';
    if (ua.contains('Edg/')) return 'Edge';
    if (ua.contains('Chrome')) return 'Chrome';
    if (ua.contains('Safari')) return 'Safari';
    if (ua.startsWith('Dart')) return l.androidApp;
    return ua.isEmpty ? l.unknownAgent : ua.split(' ').first;
  }

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  static Future<String?> _prompt(BuildContext context, String title, String initial) {
    final l = context.l10n;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(key: const Key('prompt'), controller: controller, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(l.ok)),
        ],
      ),
    );
  }

  static Future<void> _showCodes(BuildContext context, List<String> codes) {
    final l = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.newRecoveryCodes),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.newRecoveryHint),
          const SizedBox(height: 12),
          SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
        ]),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: codes.join('\n'))), child: Text(l.copy)),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.done)),
        ],
      ),
    );
  }

  static Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final current = TextEditingController();
    final next = TextEditingController();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.changePassword),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('current'), controller: current, obscureText: true, decoration: InputDecoration(labelText: l.currentPassword)),
          TextField(
            key: const Key('next'),
            controller: next,
            obscureText: true,
            decoration: InputDecoration(labelText: l.newPassword, helperText: l.passwordMin),
          ),
          TextField(
            key: const Key('code'),
            controller: code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.authenticatorCode),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.change)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).post('/api/account/password', {
        'current': current.text,
        'password': next.text,
        if (code.text.isNotEmpty) 'code': code.text,
      });
      if (context.mounted) showMessage(context, l.passwordChanged);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  static Future<void> _changeTotp(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final api = ref.read(apiProvider);
    try {
      final setup = await withStepUp(
        context,
        (code) => api.post('/api/account/totp/start', {'code': ?code}),
      ) as Map<String, dynamic>?;
      if (setup == null || !context.mounted) return;
      final code = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.newAuthenticator),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                // Fixed size: the dialog measures its content and the QR code cannot be measured
                child: SizedBox.square(
                  dimension: 180,
                  child: QrImageView(data: setup['uri'] as String, size: 180, backgroundColor: Colors.white),
                ),
              ),
              SelectableText(setup['secret'] as String, style: const TextStyle(fontFamily: 'monospace')),
              TextField(
                key: const Key('newCode'),
                controller: code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.newAppCode),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.confirm)),
          ],
        ),
      );
      if (ok != true) return;
      await api.post('/api/account/totp/confirm', {'code': code.text});
      if (context.mounted) showMessage(context, l.authenticatorUpdated);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}
