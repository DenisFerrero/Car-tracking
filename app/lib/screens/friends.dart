import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';

/// Code of a friend from a QR code (CTF1:<code>) or typed: null when it isn't one
String? parseFriendCode(String text) {
  final value = text.trim().toUpperCase();
  if (value.startsWith('CT1:')) return null;
  final code = value.replaceFirst(Friends.qrPrefix, '').replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[0-9A-Z]{10}$').hasMatch(code) ? code : null;
}

/// Friends: the personal code (text and QR code), the friend requests and the users who
/// can receive shares. Users don't see each other: one of the two types or scans the code
/// of the other, the friendship starts when the other one accepts.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _code = TextEditingController();
  bool _scanning = false;
  bool _busy = false;

  ApiClient get api => ref.read(apiProvider);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _add(String text) async {
    final l = context.l10n;
    final code = parseFriendCode(text);
    if (code == null) return showMessage(context, l.friendCodeUnknown);
    setState(() => _busy = true);
    try {
      final friend = await api.post('/api/friends', {'code': code}) as Map<String, dynamic>;
      _code.clear();
      ref.invalidate(friendsProvider);
      final name = friend['name'] as String;
      if (mounted) showMessage(context, friend['status'] == 'requested' ? l.friendRequested(name) : l.friendAdded(name));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.code == 'not_found' ? l.friendCodeUnknown : errorText(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onScan(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = parseFriendCode(barcode.rawValue ?? '');
      if (code != null) {
        setState(() => _scanning = false);
        _add(code);
        return;
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final l = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _newCode() async {
    final l = context.l10n;
    if (!await _confirm(l.newCodeTitle, l.newCodeBody, l.newCode)) return;
    try {
      await api.post('/api/friends/code');
      ref.invalidate(friendsProvider);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _accept(Friend friend) async {
    try {
      await api.post('/api/friends/requests/${friend.id}/accept');
      ref.invalidate(friendsProvider);
      if (mounted) showMessage(context, context.l10n.friendAdded(friend.name));
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Declines a request received or withdraws one sent
  Future<void> _dropRequest(Friend friend) async {
    try {
      await api.delete('/api/friends/requests/${friend.id}');
      ref.invalidate(friendsProvider);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _remove(Friend friend) async {
    final l = context.l10n;
    if (!await _confirm(l.removeFriendTitle(friend.name), l.removeFriendBody, l.removeFriend)) return;
    try {
      await api.delete('/api/friends/${friend.id}');
      ref.invalidate(friendsProvider);
      ref.invalidate(devicesProvider);
      if (mounted) showMessage(context, l.friendRemoved);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.scanFriend),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _scanning = false)),
        ),
        body: MobileScanner(onDetect: _onScan),
      );
    }
    final friends = ref.watch(friendsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.friends)),
      body: friends.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorText(l, error)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => ref.invalidate(friendsProvider), child: Text(l.retry)),
          ]),
        ),
        data: (data) => ListView(padding: const EdgeInsets.all(16), children: [
          Text(l.friendsHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(l.yourCode, style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                SizedBox.square(
                  dimension: 200,
                  child: QrImageView(data: data.qr, backgroundColor: Colors.white, padding: const EdgeInsets.all(12)),
                ),
                const SizedBox(height: 12),
                SelectableText(data.formattedCode, style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(l.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: data.formattedCode));
                      if (context.mounted) showMessage(context, l.codeCopied);
                    },
                  ),
                  TextButton.icon(icon: const Icon(Icons.autorenew), label: Text(l.newCode), onPressed: _newCode),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text(l.addFriend, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('friendCode'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l.friendCode, hintText: 'ABCDE-FGHJK'),
                onSubmitted: _busy ? null : _add,
              ),
            ),
            IconButton(tooltip: l.scanFriend, icon: const Icon(Icons.qr_code_scanner), onPressed: () => setState(() => _scanning = true)),
            FilledButton(onPressed: _busy ? null : () => _add(_code.text), child: Text(l.add)),
          ]),
          if (data.incoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.requestsReceived, style: theme.textTheme.titleSmall),
            for (final request in data.incoming)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add)),
                title: Text(request.name),
                subtitle: Text(l.requestedOn(formatDay(request.since))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: l.decline, icon: const Icon(Icons.close), onPressed: () => _dropRequest(request)),
                  IconButton(tooltip: l.accept, icon: const Icon(Icons.check), onPressed: () => _accept(request)),
                ]),
              ),
          ],
          if (data.outgoing.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.requestsSent, style: theme.textTheme.titleSmall),
            for (final request in data.outgoing)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.schedule)),
                title: Text(request.name),
                subtitle: Text(l.requestWaiting),
                trailing: IconButton(tooltip: l.withdraw, icon: const Icon(Icons.undo), onPressed: () => _dropRequest(request)),
              ),
          ],
          const SizedBox(height: 24),
          Text(l.friends, style: theme.textTheme.titleSmall),
          if (data.friends.isEmpty) ListTile(title: Text(l.noFriends)),
          for (final friend in data.friends)
            ListTile(
              leading: CircleAvatar(child: Text(friend.name.isEmpty ? '?' : friend.name[0].toUpperCase())),
              title: Text(friend.name),
              subtitle: Text(l.friendsSince(formatDay(friend.since))),
              trailing: IconButton(tooltip: l.removeFriend, icon: const Icon(Icons.person_remove), onPressed: () => _remove(friend)),
            ),
        ]),
      ),
    );
  }
}
