import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/providers.dart';

final _usersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async => (await ref.watch(apiProvider).get('/api/admin/users') as List).cast<Map<String, dynamic>>(),
);
final _invitesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async => (await ref.watch(apiProvider).get('/api/admin/invites') as List).cast<Map<String, dynamic>>(),
);
final _backupProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async => await ref.watch(apiProvider).get('/api/admin/backup') as Map<String, dynamic>,
);
final _firmwareProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async => (await ref.watch(apiProvider).get('/api/admin/firmware') as List).cast<Map<String, dynamic>>(),
);

/// Users of the platform. No public registration: the administrator creates an
/// invite link and sends it to the person (no email server needed).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final users = ref.watch(_usersProvider);
    final invites = ref.watch(_invitesProvider);
    final api = ref.read(apiProvider);
    final me = ref.watch(sessionProvider).user;

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(_usersProvider);
        ref.invalidate(_invitesProvider);
        ref.invalidate(_firmwareProvider);
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.administration)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context, ref),
        icon: const Icon(Icons.person_add),
        label: Text(l.invite),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        ...ref.watch(_backupProvider).maybeWhen(data: (backup) => [_BackupCard(backup: backup)], orElse: () => const <Widget>[]),
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(l.users)),
        ...users.when(
          loading: () => [const LinearProgressIndicator()],
          error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
          data: (list) => [
            for (final user in list)
              ListTile(
                leading: Icon(
                  user['disabled'] == true ? Icons.block : (user['isAdmin'] == true ? Icons.admin_panel_settings : Icons.person),
                  color: user['disabled'] == true ? Colors.red : null,
                ),
                title: Text('${user['name']}${user['id'] == me?.id ? ' (${l.you})' : ''}'),
                subtitle: Text([
                  l.userSummary(user['email'] as String, user['devices'] as int, user['passkeys'] as int),
                  if (user['totpEnabled'] != true) l.twoFactorPending,
                  if (user['lastLoginAt'] != null) l.lastLogin(formatAgo(l, DateTime.parse(user['lastLoginAt'] as String).toLocal())),
                ].join()),
                trailing: user['id'] == me?.id
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) => guard(() async {
                          final id = user['id'];
                          switch (action) {
                            case 'reset':
                              final result = await api.post('/api/admin/users/$id/reset') as Map<String, dynamic>;
                              if (context.mounted) await _showLink(context, l.resetLink, result['link'] as String);
                            case 'disable':
                              await api.patch('/api/admin/users/$id', {'disabled': user['disabled'] != true});
                            case 'admin':
                              await api.patch('/api/admin/users/$id', {'isAdmin': user['isAdmin'] != true});
                            case 'delete':
                              if (await _confirm(context, l.deleteUserTitle(user['name'] as String))) {
                                await api.delete('/api/admin/users/$id');
                              }
                          }
                        }),
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'reset', child: Text(l.resetAccess)),
                          PopupMenuItem(value: 'disable', child: Text(user['disabled'] == true ? l.enable : l.disable)),
                          PopupMenuItem(value: 'admin', child: Text(user['isAdmin'] == true ? l.removeAdmin : l.makeAdmin)),
                          PopupMenuItem(value: 'delete', child: Text(l.delete)),
                        ],
                      ),
              ),
          ],
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(l.pendingInvites)),
        ...invites.when(
          loading: () => [const LinearProgressIndicator()],
          error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
          data: (list) => list.isEmpty
              ? [ListTile(title: Text(l.none))]
              : [
                  for (final invite in list)
                    ListTile(
                      leading: Icon(invite['userId'] == null ? Icons.mail_outline : Icons.lock_reset),
                      title: Text('${invite['name']} · ${invite['email']}'),
                      subtitle: Text(l.expires(formatDayTime(DateTime.parse(invite['expiresAt'] as String).toLocal()))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l.cancelInvite,
                        onPressed: () => guard(() => api.delete('/api/admin/invites/${invite['id']}')),
                      ),
                    ),
                ],
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(l.firmwareImages)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l.firmwareImagesHint, style: Theme.of(context).textTheme.bodySmall),
        ),
        ...ref.watch(_firmwareProvider).when(
              loading: () => [const LinearProgressIndicator()],
              error: (error, _) => [ListTile(title: Text(errorText(l, error)))],
              data: (list) => [
                for (final image in list)
                  ListTile(
                    leading: const Icon(Icons.memory),
                    title: Text('${image['version']} · ${image['variant']}'),
                    subtitle: Text([
                      '${((image['size'] as int) / 1024).round()} KB',
                      formatDay(DateTime.parse(image['createdAt'] as String).toLocal()),
                      if ((image['pending'] as int) > 0) l.firmwarePending(image['pending'] as int),
                      if ((image['notes'] as String).isNotEmpty) image['notes'] as String,
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l.delete,
                      onPressed: () => guard(() => api.delete('/api/admin/firmware/${image['id']}')),
                    ),
                  ),
              ],
            ),
      ]),
    );
  }

  static Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final email = TextEditingController();
    final name = TextEditingController();
    var admin = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(l.inviteUser),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('inviteName'), controller: name, decoration: InputDecoration(labelText: l.nameLabel)),
            TextField(
              key: const Key('inviteEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.emailLabel),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: admin,
              onChanged: (value) => setDialog(() => admin = value ?? false),
              title: Text(l.administrator),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.createInvite)),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final result = await ref.read(apiProvider).post('/api/admin/invites', {
        'email': email.text.trim(),
        'name': name.text.trim(),
        'isAdmin': admin,
      }) as Map<String, dynamic>;
      ref.invalidate(_invitesProvider);
      if (context.mounted) await _showLink(context, l.inviteCreated, result['link'] as String);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  static Future<void> _showLink(BuildContext context, String title, String link) {
    final l = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.linkHint),
          const SizedBox(height: 12),
          SelectableText(link, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              showMessage(context, l.linkCopied);
            },
            child: Text(l.copy),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
        ],
      ),
    );
  }

  static Future<bool> _confirm(BuildContext context, String title) async {
    final l = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(l.deleteUserBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
            ],
          ),
        ) ==
        true;
  }
}

/// Daily dumps of the database (backup service) and the copy off the server (restic)
class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.backup});

  final Map<String, dynamic> backup;

  @override
  Widget build(BuildContext context) {
    if (backup['configured'] != true) return const SizedBox.shrink();
    final l = context.l10n;
    final stale = backup['stale'] == true;
    final latest = backup['latest'] as Map<String, dynamic>?;
    final last = backup['lastSuccess'] as String?;
    final offsite = backup['lastOffsite'] as String?;
    String time(String value) => formatDayTime(DateTime.parse(value).toLocal());
    return Card(
      key: const Key('backupCard'),
      margin: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: ListTile(
        leading: Icon(stale ? Icons.warning_amber : Icons.backup, color: stale ? Colors.red : Colors.green),
        title: Text(l.backups),
        subtitle: Text([
          if (stale) l.backupStale,
          if (last != null) l.backupLast(time(last), latest == null ? '-' : formatBytes(latest['size'] as num)),
          l.backupFiles(backup['files'] as int, formatBytes(backup['totalBytes'] as num)),
          offsite == null ? l.backupNoOffsite : l.backupOffsite(time(offsite)),
        ].join('\n')),
      ),
    );
  }
}
