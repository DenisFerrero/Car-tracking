import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/providers.dart';

/// Centered card used by the access screens
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.location_on, size: 56),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _busyChild(bool busy, String label) => busy
    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
    : Text(label);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } catch (_) {
      // Passkey dialog closed by the user, or no passkey for this site
      if (mounted) showMessage(context, context.l10n.passkeyNotCompleted);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final l = context.l10n;
    return AuthLayout(
      title: session.config?.appName ?? l.appTitle,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(session.loginWithPasskey),
          icon: const Icon(Icons.fingerprint),
          label: Text(l.loginPasskey),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l.or)),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 24),
        AutofillGroup(
          child: Column(children: [
            TextField(
              key: const Key('email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l.emailLabel, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l.passwordLabel, border: const OutlineInputBorder()),
              onSubmitted: (_) => _run(() => session.login(_email.text, _password.text)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() => session.login(_email.text, _password.text)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busyChild(_busy, l.loginPassword),
        ),
        if (!session.api.web) ...[
          const SizedBox(height: 24),
          TextButton(
            onPressed: session.changeServer,
            child: Text(l.serverChange(Uri.tryParse(session.api.baseUrl)?.host ?? '')),
          ),
        ],
      ],
    );
  }
}

/// Second factor after the password: code of the authenticator app or recovery code
class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final _code = TextEditingController();
  bool _recovery = false;
  bool _busy = false;

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    setState(() => _busy = true);
    try {
      if (_recovery) {
        final left = await session.verifyRecoveryCode(_code.text);
        if (mounted && left <= 3) showMessage(context, context.l10n.recoveryCodesLeft(left));
      } else {
        await session.verifyTotp(_code.text);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      // Pending session expired (10 minutes): back to the password
      if (error.status == 401 && error.code == 'unauthorized') {
        await session.logout();
      } else {
        showError(context, error);
      }
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthLayout(
      title: l.mfaTitle,
      subtitle: _recovery ? l.mfaRecoveryHint : l.mfaTotpHint,
      children: [
        TextField(
          key: const Key('code'),
          controller: _code,
          autofocus: true,
          keyboardType: _recovery ? TextInputType.text : TextInputType.number,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
          // In the browser an autofill hint moves the editing to an input of an autofill form,
          // outside the semantics: with a screen reader the keys didn't reach the field until
          // the page was loaded again. Android keeps the code from the SMS or the app.
          autofillHints: kIsWeb ? null : const [AutofillHints.oneTimeCode],
          inputFormatters: _recovery ? null : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l.mfaCode,
            hintText: _recovery ? 'XXXX-XXXX-XXXX' : '000000',
          ),
          onChanged: (value) {
            if (!_recovery && value.length == 6) _submit();
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busyChild(_busy, l.verify),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _recovery = !_recovery;
            _code.clear();
          }),
          child: Text(_recovery ? l.useAuthenticator : l.useRecoveryCode),
        ),
        TextButton(onPressed: () => ref.read(sessionProvider).logout(), child: Text(l.cancel)),
      ],
    );
  }
}

/// Invite or access reset link: choose the password
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final Future<Map<String, dynamic>> _invite = ref.read(sessionProvider).invite(widget.token);
  bool _busy = false;

  Future<void> _submit() async {
    final l = context.l10n;
    if (_password.text.length < 12) return showMessage(context, l.passwordTooShort);
    if (_password.text != _confirm.text) return showMessage(context, l.passwordsDiffer);
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).acceptInvite(widget.token, _password.text);
      if (mounted) context.go('/enroll');
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder(
      future: _invite,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AuthLayout(title: l.inviteInvalid, subtitle: errorText(l, snapshot.error!), children: [
            FilledButton(onPressed: () => context.go('/login'), child: Text(l.goToLogin)),
          ]);
        }
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final invite = snapshot.data!;
        return AuthLayout(
          title: invite['reset'] == true ? l.resetTitle : l.welcome(invite['name'] as String),
          subtitle: l.inviteHint(invite['email'] as String),
          children: [
            TextField(
              key: const Key('password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(labelText: l.newPassword, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('confirm'),
              controller: _confirm,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(labelText: l.repeatPassword, border: const OutlineInputBorder()),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _busyChild(_busy, l.continueLabel),
            ),
          ],
        );
      },
    );
  }
}

/// Mandatory TOTP enrollment
class EnrollScreen extends ConsumerStatefulWidget {
  const EnrollScreen({super.key});

  @override
  ConsumerState<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends ConsumerState<EnrollScreen> {
  late Future<({String secret, String uri})> _setup = ref.read(sessionProvider).startEnrollment();
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).confirmEnrollment(_code.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      showError(context, error);
      _code.clear();
      if (error.code == 'enroll_expired') {
        final setup = ref.read(sessionProvider).startEnrollment();
        setState(() {
          _setup = setup;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = ref.read(sessionProvider);
    return FutureBuilder(
      future: _setup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AuthLayout(title: l.sessionExpired, subtitle: errorText(l, snapshot.error!), children: [
            FilledButton(onPressed: session.logout, child: Text(l.loginAgain)),
          ]);
        }
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final setup = snapshot.data!;
        return AuthLayout(
          title: l.enrollTitle,
          subtitle: l.enrollHint,
          children: [
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: setup.uri, size: 200, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              setup.secret.replaceAllMapped(RegExp(r'.{4}'), (match) => '${match[0]} ').trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
            if (!session.api.web)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: setup.secret));
                  showMessage(context, l.keyCopied);
                },
                icon: const Icon(Icons.copy),
                label: Text(l.copyKey),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('code'),
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '000000'),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _confirm,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _busyChild(_busy, l.activate),
            ),
            TextButton(onPressed: session.logout, child: Text(l.cancel)),
          ],
        );
      },
    );
  }
}

/// Recovery codes shown once, then the proposal of a passkey
class RecoveryCodesScreen extends ConsumerStatefulWidget {
  const RecoveryCodesScreen({super.key});

  @override
  ConsumerState<RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends ConsumerState<RecoveryCodesScreen> {
  bool _saved = false;
  bool _busy = false;

  Future<void> _addPasskey() async {
    final l = context.l10n;
    final session = ref.read(sessionProvider);
    setState(() => _busy = true);
    try {
      await session.addPasskey(session.api.web ? l.defaultPasskeyBrowser : l.defaultPasskeyPhone);
      if (mounted) showMessage(context, l.passkeyCreated);
      session.clearRecoveryCodes();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } catch (_) {
      if (mounted) showMessage(context, l.passkeyNotCreated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = ref.watch(sessionProvider);
    final codes = session.pendingRecoveryCodes ?? const <String>[];
    return AuthLayout(
      title: l.recoveryTitle,
      subtitle: l.recoveryHint,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              codes.join('\n'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.6),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: codes.join('\n')));
            showMessage(context, l.codesCopied);
          },
          icon: const Icon(Icons.copy),
          label: Text(l.copy),
        ),
        CheckboxListTile(
          value: _saved,
          onChanged: (value) => setState(() => _saved = value ?? false),
          title: Text(l.codesSaved),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: !_saved || _busy ? null : _addPasskey,
          icon: const Icon(Icons.fingerprint),
          label: Text(l.createPasskey),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        TextButton(onPressed: _saved ? session.clearRecoveryCodes : null, child: Text(l.later)),
      ],
    );
  }
}
