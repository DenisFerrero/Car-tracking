import 'package:car_tracking/screens/admin.dart';
import 'package:car_tracking/screens/auth.dart';
import 'package:car_tracking/screens/server_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Map<String, dynamic> _session(int id, String? agent, {bool current = false, String client = 'web'}) => {
      'id': id,
      'client': client,
      'user_agent': agent,
      'ip': '10.0.0.$id',
      'last_seen_at': iso(ago(Duration(minutes: id))),
      'current': current,
    };

FakeBackend accountBackend({bool admin = true, int recoveryLeft = 8}) => fullBackend(admin: admin)
  ..on('GET', '/api/account', (_) => {
        'passkeys': [
          {'id': 'pk/1', 'name': 'Pixel', 'created_at': iso(ago(const Duration(days: 3))), 'last_used_at': iso(ago(const Duration(hours: 2))), 'backed_up': true},
          {'id': 'pk2', 'name': 'Laptop', 'created_at': iso(ago(const Duration(days: 9))), 'last_used_at': null, 'backed_up': false},
        ],
        'sessions': [
          _session(1, 'Mozilla/5.0 (X11; Linux) Chrome/130', current: true),
          _session(2, 'Mozilla/5.0 (Linux; Android 15)', client: 'app'),
          _session(3, 'Mozilla/5.0 (iPhone)'),
          _session(4, 'Mozilla/5.0 Firefox/133'),
          _session(5, 'Mozilla/5.0 Chrome/130 Edg/130'),
          _session(6, 'Mozilla/5.0 (Macintosh) Safari/605'),
          _session(7, 'Dart/3.10 (dart:io)', client: 'app'),
          _session(8, null),
          _session(9, 'curl/8.10 x'),
        ],
        'recoveryCodesLeft': recoveryLeft,
        'pushEnabled': true,
      });

Future<TestApp> openAccount(WidgetTester tester, FakeBackend backend, {bool web = true}) async {
  final app = TestApp(backend, web: web, token: web ? null : 'tok');
  await app.start(tester);
  await tapAndSettle(tester, find.text(it.navAccount));
  return app;
}

void main() {
  setUpAll(initFormats);

  group('account', () {
    testWidgets('language, name, sessions, logout', (tester) async {
      final backend = accountBackend();
      final app = await openAccount(tester, backend);
      expect(find.text('Anna'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('language')));
      await tapAndSettle(tester, find.text('English').last);
      expect(backend.lastBody('/api/account', 'PATCH'), {'locale': 'en'});
      expect(find.text(en.language), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('language')));
      await tapAndSettle(tester, find.text('Italiano').last);
      expect(app.session.language, 'it');

      await tapAndSettle(tester, find.byTooltip(it.editName));
      await tapAndSettle(tester, find.text(it.cancel));
      await tapAndSettle(tester, find.byTooltip(it.editName));
      await tester.enterText(find.byKey(const Key('prompt')), 'Anna Maria');
      await tapAndSettle(tester, find.text(it.ok));
      expect(backend.lastBody('/api/account', 'PATCH'), {'name': 'Anna Maria'});
      expect(find.text('Anna Maria'), findsOneWidget);

      for (final agent in [it.androidApp, 'Chrome${it.thisSession}', 'Android', 'iOS', 'Firefox', 'Edge', 'Safari', it.unknownAgent, 'curl/8.10']) {
        await reveal(tester, find.text(agent));
      }
      backend.on('DELETE', '/api/account/sessions/2', (_) => {'ok': true});
      await tapAndSettle(tester, find.byTooltip(it.disconnect).first);
      expect(backend.calls('/api/account/sessions/2', 'DELETE'), hasLength(1));
      backend.on('POST', '/api/account/sessions/revoke-others', (_) => {'ok': true});
      await tapAndSettle(tester, find.text(it.disconnectOthers));
      expect(find.text(it.sessionsClosed), findsOneWidget);
      expect(find.text(it.pushTitle), findsNothing);

      await tapAndSettle(tester, find.text(it.logout));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('passkeys with the step up of the second factor', (tester) async {
      var steps = 0;
      final backend = accountBackend()
        ..on('DELETE', '/api/account/passkeys/pk%2F1', (r) => r.body.contains('code') ? {'ok': true} : Reply.error(403, 'step_up_required'))
        ..on('POST', '/api/account/passkeys/options', (r) => steps++ == 0 ? Reply.error(403, 'step_up_required') : {'challenge': 'c'})
        ..on('POST', '/api/account/passkeys', (_) => {'ok': true});
      final app = await openAccount(tester, backend);
      expect(find.textContaining(it.passkeySynced.trim()), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip(it.delete).first);
      expect(find.text(it.confirmWithCode), findsOneWidget);
      await tester.enterText(find.byKey(const Key('totp')), '123456');
      await tapAndSettle(tester, find.text(it.confirm));
      expect(backend.lastBody('/api/account/passkeys/pk%2F1', 'DELETE'), {'code': '123456'});
      expect(find.text(it.passkeyRemoved), findsOneWidget);

      // Step up closed: nothing happens
      await reveal(tester, find.text(it.addPasskey));
      await tester.ensureVisible(find.text(it.addPasskey));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(it.addPasskey));
      expect(find.text(it.defaultPasskeyBrowser), findsOneWidget);
      await tapAndSettle(tester, find.text(it.ok));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/account/passkeys', 'POST'), isEmpty);

      await tapAndSettle(tester, find.text(it.addPasskey));
      await tester.enterText(find.byKey(const Key('prompt')), 'Yubikey');
      await tapAndSettle(tester, find.text(it.ok));
      expect(backend.lastBody('/api/account/passkeys', 'POST')['name'], 'Yubikey');
      expect(find.text(it.passkeyAdded), findsOneWidget);

      app.passkeys.fail = true;
      await tapAndSettle(tester, find.text(it.addPasskey));
      await tapAndSettle(tester, find.text(it.ok));
      expect(find.text(it.operationCancelled), findsOneWidget);

      // Empty name or dialog closed
      await tapAndSettle(tester, find.text(it.addPasskey));
      await tester.enterText(find.byKey(const Key('prompt')), ' ');
      await tapAndSettle(tester, find.text(it.ok));
      await tapAndSettle(tester, find.text(it.addPasskey));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(app.passkeys.calls.length, 2);

      backend.on('DELETE', '/api/account/passkeys/pk2', (_) => Reply.error(404, 'not_found'));
      await tester.fling(find.byType(ListView), const Offset(0, 2000), 3000);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byTooltip(it.delete).last);
      expect(find.text(it.errNotFound), findsOneWidget);
    });

    testWidgets('password, authenticator app, recovery codes', (tester) async {
      final backend = accountBackend(recoveryLeft: 2)
        ..on('POST', '/api/account/password', (_) => Reply.error(400, 'invalid_password'))
        ..on('POST', '/api/account/totp/start', (_) => {'uri': 'otpauth://totp/x', 'secret': 'NEWSECRET'})
        ..on('POST', '/api/account/totp/confirm', (_) => {'ok': true})
        ..on('POST', '/api/account/recovery-codes', (_) => {'recoveryCodes': ['AAAA-1111', 'BBBB-2222']});
      await openAccount(tester, backend);

      await tapAndSettle(tester, find.text(it.changePassword));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/account/password'), isEmpty);
      await tapAndSettle(tester, find.text(it.changePassword));
      await tester.enterText(find.byKey(const Key('current')), 'old password');
      await tester.enterText(find.byKey(const Key('next')), 'short');
      await tapAndSettle(tester, find.text(it.change));
      expect(find.text(it.errInvalidPassword), findsOneWidget);
      expect(backend.lastBody('/api/account/password'), {'current': 'old password', 'password': 'short'});

      backend.on('POST', '/api/account/password', (_) => {'ok': true});
      await tapAndSettle(tester, find.text(it.changePassword));
      await tester.enterText(find.byKey(const Key('current')), 'old password');
      await tester.enterText(find.byKey(const Key('next')), 'a much longer one');
      await tester.enterText(find.byKey(const Key('code')), '123456');
      await tapAndSettle(tester, find.text(it.change));
      expect(backend.lastBody('/api/account/password')['code'], '123456');
      expect(find.text(it.passwordChanged), findsOneWidget);
      await clearSnackbars(tester);

      await tapAndSettle(tester, find.text(it.changeAuthenticator));
      expect(find.text('NEWSECRET'), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/account/totp/confirm'), isEmpty);
      await tapAndSettle(tester, find.text(it.changeAuthenticator));
      await tester.enterText(find.byKey(const Key('newCode')), '654321');
      await tapAndSettle(tester, find.text(it.confirm));
      expect(find.text(it.authenticatorUpdated), findsOneWidget);
      await clearSnackbars(tester);
      backend.on('POST', '/api/account/totp/start', (_) => Reply.error(429, 'rate_limited'));
      await tapAndSettle(tester, find.text(it.changeAuthenticator));
      expect(find.text(it.errRateLimited), findsOneWidget);

      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.recoveryLeft(2)));
      expect(find.text('AAAA-1111\nBBBB-2222'), findsOneWidget);
      await tapAndSettle(tester, find.text(it.copy));
      await tapAndSettle(tester, find.text(it.done));
      expect(find.text(it.newRecoveryCodes), findsNothing);
    });

    testWidgets('Android: push, server, no administration', (tester) async {
      final backend = accountBackend(admin: false)
        ..on('GET', '/api/account', (_) => {'passkeys': [], 'sessions': [_session(1, 'Dart/3.10', current: true, client: 'app')], 'recoveryCodesLeft': 8});
      await openAccount(tester, backend, web: false);
      expect(find.text(it.administration), findsNothing);
      expect(find.text(it.disconnectOthers), findsNothing);
      await reveal(tester, find.text(it.pushOff));

      await tapAndSettle(tester, find.text(it.addPasskey));
      expect(find.text(it.defaultPasskeyPhone), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));

      await tapAndSettle(tester, find.text('https://tracking.test'));
      expect(find.byType(ServerSetupScreen), findsOneWidget);
    });

    testWidgets('account that cannot be loaded', (tester) async {
      await openAccount(tester, fullBackend()..on('GET', '/api/account', (_) => Reply.error(500, 'x')));
      expect(find.text(it.errGeneric(500)), findsOneWidget);
    });
  });

  group('administration', () {
    FakeBackend adminBackend() => accountBackend()
      ..on('GET', '/api/admin/users', (_) => [
            {'id': 1, 'name': 'Anna', 'email': 'anna@example.com', 'isAdmin': true, 'devices': 1, 'passkeys': 2, 'totpEnabled': true, 'lastLoginAt': iso(ago(const Duration(minutes: 3)))},
            {'id': 2, 'name': 'Mario', 'email': 'mario@example.com', 'isAdmin': false, 'devices': 2, 'passkeys': 0, 'totpEnabled': false, 'disabled': false},
            {'id': 3, 'name': 'Sara', 'email': 'sara@example.com', 'isAdmin': true, 'devices': 0, 'passkeys': 1, 'totpEnabled': true, 'disabled': true},
          ])
      ..on('GET', '/api/admin/invites', (_) => [
            {'id': 4, 'name': 'Luca', 'email': 'luca@example.com', 'userId': null, 'expiresAt': iso(DateTime.now().add(const Duration(days: 3)))},
            {'id': 5, 'name': 'Mario', 'email': 'mario@example.com', 'userId': 2, 'expiresAt': iso(DateTime.now().add(const Duration(days: 1)))},
          ])
      ..on('POST', '/api/admin/users/2/reset', (_) => {'link': 'https://tracking.test/invite/reset'})
      ..on('PATCH', '/api/admin/users/2', (_) => {'ok': true})
      ..on('PATCH', '/api/admin/users/3', (_) => {'ok': true})
      ..on('DELETE', '/api/admin/users/2', (_) => {'ok': true})
      ..on('DELETE', '/api/admin/invites/4', (_) => {'ok': true});

    Future<FakeBackend> openAdmin(WidgetTester tester, [FakeBackend? custom]) async {
      final backend = custom ?? adminBackend();
      await openAccount(tester, backend);
      await tapAndSettle(tester, find.text(it.administration));
      expect(find.byType(AdminScreen), findsOneWidget);
      return backend;
    }

    Future<void> menu(WidgetTester tester, int index, String action) async {
      await tapAndSettle(tester, find.byType(PopupMenuButton<String>).at(index));
      await tapAndSettle(tester, find.text(action).last);
    }

    testWidgets('users: reset, enable, roles, delete', (tester) async {
      final backend = await openAdmin(tester);
      expect(find.text('Anna (${it.you})'), findsOneWidget);
      expect(find.textContaining(it.twoFactorPending.trim()), findsOneWidget);
      expect(find.textContaining(it.lastLogin('').trim()), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);

      await menu(tester, 0, it.resetAccess);
      expect(find.text('https://tracking.test/invite/reset'), findsOneWidget);
      await tapAndSettle(tester, find.text(it.copy));
      expect(find.text(it.linkCopied), findsOneWidget);
      await tapAndSettle(tester, find.text(it.close));

      await menu(tester, 0, it.disable);
      expect(backend.lastBody('/api/admin/users/2', 'PATCH'), {'disabled': true});
      await menu(tester, 0, it.makeAdmin);
      expect(backend.lastBody('/api/admin/users/2', 'PATCH'), {'isAdmin': true});
      await menu(tester, 1, it.enable);
      expect(backend.lastBody('/api/admin/users/3', 'PATCH'), {'disabled': false});
      await menu(tester, 1, it.removeAdmin);
      expect(backend.lastBody('/api/admin/users/3', 'PATCH'), {'isAdmin': false});

      await menu(tester, 0, it.delete);
      expect(find.text(it.deleteUserTitle('Mario')), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/admin/users/2', 'DELETE'), isEmpty);
      await menu(tester, 0, it.delete);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, it.delete));
      expect(backend.calls('/api/admin/users/2', 'DELETE'), hasLength(1));

      backend.on('PATCH', '/api/admin/users/2', (_) => Reply.error(400, 'self'));
      await menu(tester, 0, it.disable);
      expect(find.text(it.errSelf), findsOneWidget);
    });

    testWidgets('invites: create, cancel', (tester) async {
      final backend = await openAdmin(tester);
      backend.on('POST', '/api/admin/invites', (_) => Reply.error(409, 'email_taken'));
      await tapAndSettle(tester, find.text(it.invite));
      await tapAndSettle(tester, find.text(it.cancel));
      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.invite));
      await tester.enterText(find.byKey(const Key('inviteName')), 'Nuovo');
      await tester.enterText(find.byKey(const Key('inviteEmail')), ' nuovo@example.com ');
      await tapAndSettle(tester, find.text(it.administrator));
      await tapAndSettle(tester, find.text(it.createInvite));
      expect(find.text(it.errEmailTaken), findsOneWidget);
      expect(backend.lastBody('/api/admin/invites', 'POST'), {'email': 'nuovo@example.com', 'name': 'Nuovo', 'isAdmin': true});

      backend.on('POST', '/api/admin/invites', (_) => {'link': 'https://tracking.test/invite/new'});
      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.invite));
      await tapAndSettle(tester, find.text(it.createInvite));
      expect(find.text(it.inviteCreated), findsOneWidget);
      expect(find.text(it.linkHint), findsOneWidget);
      await tapAndSettle(tester, find.text(it.close));

      expect(find.byIcon(Icons.lock_reset), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.cancelInvite).first);
      expect(backend.calls('/api/admin/invites/4', 'DELETE'), hasLength(1));
    });

    testWidgets('empty invites and failing lists', (tester) async {
      final backend = adminBackend()..on('GET', '/api/admin/invites', (_) => []);
      await openAdmin(tester, backend);
      expect(find.text(it.none), findsOneWidget);
    });

    testWidgets('lists that cannot be loaded', (tester) async {
      final backend = adminBackend()
        ..on('GET', '/api/admin/users', (_) => Reply.error(403, 'forbidden'))
        ..on('GET', '/api/admin/invites', (_) => Reply.error(500, 'x'));
      await openAdmin(tester, backend);
      expect(find.text(it.errForbidden), findsOneWidget);
      expect(find.text(it.errGeneric(500)), findsOneWidget);
    });
  });
}
