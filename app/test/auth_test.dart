import 'package:car_tracking/screens/auth.dart';
import 'package:car_tracking/screens/map_overview.dart';
import 'package:car_tracking/screens/server_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Backend whose session stage changes with the steps of the user
class AuthBackend {
  AuthBackend([this.stage = 'none']) {
    backend.on('GET', '/api/auth/session', (_) => {'stage': stage, 'user': userJson()});
  }

  String stage;
  final backend = fullBackend();

  void step(String method, String path, String next, [Map<String, dynamic> body = const {}]) =>
      backend.on(method, path, (_) {
        stage = next;
        return body;
      });
}

void main() {
  setUpAll(initFormats);

  testWidgets('mobile: platform address, then login and change of server', (tester) async {
    final auth = AuthBackend();
    final app = TestApp(auth.backend, web: false, server: '');
    await app.start(tester);
    expect(find.byType(ServerSetupScreen), findsOneWidget);

    auth.backend.offline = true;
    await tester.enterText(find.byKey(const Key('server')), 'tracking.test');
    await tapAndSettle(tester, find.text(it.continueLabel));
    expect(find.text(it.serverUnreachable), findsOneWidget);

    auth.backend.offline = false;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Tracker'), findsOneWidget);

    await tapAndSettle(tester, find.text(it.serverChange('tracking.test')));
    expect(find.byType(ServerSetupScreen), findsOneWidget);
  });

  testWidgets('password, wrong and right TOTP code', (tester) async {
    final auth = AuthBackend();
    final app = TestApp(auth.backend);
    await app.start(tester);
    expect(find.text(it.serverChange('tracking.test')), findsNothing);

    auth.backend.on('POST', '/api/auth/login', (_) => Reply.error(401, 'invalid_credentials'));
    await tester.enterText(find.byKey(const Key('email')), 'anna@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tapAndSettle(tester, find.text(it.loginPassword));
    expect(find.text(it.errInvalidCredentials), findsOneWidget);

    auth.step('POST', '/api/auth/login', 'mfa_pending');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byType(MfaScreen), findsOneWidget);
    expect(find.text(it.mfaTotpHint), findsOneWidget);

    auth.backend.on('POST', '/api/auth/totp', (_) => Reply.error(400, 'invalid_code'));
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await settle(tester);
    expect(find.text(it.errInvalidCode), findsOneWidget);

    auth.step('POST', '/api/auth/totp', 'full');
    // Six digits are sent without the button
    await tester.enterText(find.byKey(const Key('code')), '654321');
    await settle(tester);
    expect(find.byType(MapOverviewScreen), findsOneWidget);
    expect(app.live.active, isTrue);
  });

  testWidgets('recovery code, expired pending session and cancel', (tester) async {
    final auth = AuthBackend('mfa_pending');
    final app = TestApp(auth.backend);
    await app.start(tester);

    await tapAndSettle(tester, find.text(it.useRecoveryCode));
    expect(find.text(it.mfaRecoveryHint), findsOneWidget);
    await tapAndSettle(tester, find.text(it.useAuthenticator));
    await tapAndSettle(tester, find.text(it.useRecoveryCode));

    // The pending session lasts 10 minutes: back to the password
    auth.backend.on('POST', '/api/auth/recovery', (_) {
      auth.stage = 'none';
      return Reply.error(401, 'unauthorized');
    });
    await tester.enterText(find.byKey(const Key('code')), 'AAAA-BBBB-CCCC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    auth.stage = 'mfa_pending';
    await app.session.load();
    await settle(tester);
    await tapAndSettle(tester, find.text(it.useRecoveryCode));
    auth.backend.on('POST', '/api/auth/recovery', (_) => Reply.error(400, 'invalid_code'));
    await tester.enterText(find.byKey(const Key('code')), 'AAAA-BBBB-CCCC');
    await tapAndSettle(tester, find.text(it.verify));
    expect(find.text(it.errInvalidCode), findsOneWidget);

    auth.step('POST', '/api/auth/recovery', 'full', {'recoveryCodesLeft': 2});
    await tester.enterText(find.byKey(const Key('code')), 'AAAA-BBBB-CCCC');
    await tapAndSettle(tester, find.text(it.verify));
    expect(find.text(it.recoveryCodesLeft(2)), findsOneWidget);
    expect(find.byType(MapOverviewScreen), findsOneWidget);

    await app.session.logout();
    auth.stage = 'mfa_pending';
    await app.session.load();
    await settle(tester);
    await tapAndSettle(tester, find.text(it.cancel));
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('passkey login: success, closed dialog, backend error', (tester) async {
    final auth = AuthBackend();
    final app = TestApp(auth.backend);
    await app.start(tester);

    auth.backend.on('POST', '/api/auth/passkey/options', (_) => Reply.error(429, 'rate_limited'));
    await tapAndSettle(tester, find.text(it.loginPasskey));
    expect(find.text(it.errRateLimited), findsOneWidget);

    auth.backend.on('POST', '/api/auth/passkey/options', (_) => {'challenge': 'c'});
    app.passkeys.fail = true;
    await tapAndSettle(tester, find.text(it.loginPasskey));
    expect(find.text(it.passkeyNotCompleted), findsOneWidget);

    app.passkeys.fail = false;
    auth.step('POST', '/api/auth/passkey/verify', 'full');
    await tapAndSettle(tester, find.text(it.loginPasskey));
    expect(find.byType(MapOverviewScreen), findsOneWidget);
  });

  testWidgets('invite: password rules, then enrollment', (tester) async {
    final auth = AuthBackend();
    auth.backend.on('GET', '/api/auth/invites/abc', (_) => {'email': 'new@example.com', 'name': 'Nuovo', 'reset': false});
    auth.step('POST', '/api/auth/invites/abc', 'enroll', {'token': 'x'});
    auth.backend.on('POST', '/api/auth/enroll/start', (_) => {'secret': 'ABCDEFGHIJKLMNOP', 'uri': 'otpauth://totp/x'});
    final app = TestApp(auth.backend);
    await app.start(tester);
    app.go(tester, '/invite/abc');
    await settle(tester);
    expect(find.text(it.welcome('Nuovo')), findsOneWidget);
    expect(find.text(it.inviteHint('new@example.com')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password')), 'short');
    await tapAndSettle(tester, find.text(it.continueLabel));
    expect(find.text(it.passwordTooShort), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password')), 'a long password');
    await tester.enterText(find.byKey(const Key('confirm')), 'another password');
    await tapAndSettle(tester, find.text(it.continueLabel));
    expect(find.text(it.passwordsDiffer), findsOneWidget);

    auth.backend.on('POST', '/api/auth/invites/abc', (_) => Reply.error(400, 'invalid_password'));
    await tester.enterText(find.byKey(const Key('confirm')), 'a long password');
    await tapAndSettle(tester, find.text(it.continueLabel));
    expect(find.text(it.errInvalidPassword), findsOneWidget);

    auth.step('POST', '/api/auth/invites/abc', 'enroll', {'token': 'x'});
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byType(EnrollScreen), findsOneWidget);
    expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);
  });

  testWidgets('invalid invite and access reset', (tester) async {
    final auth = AuthBackend();
    auth.backend.on('GET', '/api/auth/invites/old', (_) => Reply.error(404, 'not_found'));
    auth.backend.on('GET', '/api/auth/invites/reset', (_) => {'email': 'anna@example.com', 'name': 'Anna', 'reset': true});
    final app = TestApp(auth.backend);
    await app.start(tester);
    app.go(tester, '/invite/old');
    await settle(tester);
    expect(find.text(it.inviteInvalid), findsOneWidget);
    expect(find.text(it.errNotFound), findsOneWidget);
    await tapAndSettle(tester, find.text(it.goToLogin));
    expect(find.byType(LoginScreen), findsOneWidget);

    app.go(tester, '/invite/reset');
    await settle(tester);
    expect(find.text(it.resetTitle), findsOneWidget);
  });

  testWidgets('enrollment: wrong code, expired setup, recovery codes, passkey', (tester) async {
    final auth = AuthBackend('enroll');
    var starts = 0;
    auth.backend.on('POST', '/api/auth/enroll/start', (_) => {'secret': 'SECRET${starts++}', 'uri': 'otpauth://totp/x'});
    final app = TestApp(auth.backend, web: false, token: 't');
    await app.start(tester);
    expect(find.text(it.enrollTitle), findsOneWidget);

    await tapAndSettle(tester, find.text(it.copyKey));
    expect(find.text(it.keyCopied), findsOneWidget);

    auth.backend.on('POST', '/api/auth/enroll/confirm', (_) => Reply.error(400, 'invalid_code'));
    await tester.enterText(find.byKey(const Key('code')), '111111');
    await tapAndSettle(tester, find.text(it.activate));
    expect(find.text(it.errInvalidCode), findsOneWidget);

    auth.backend.on('POST', '/api/auth/enroll/confirm', (_) => Reply.error(400, 'enroll_expired'));
    await tester.enterText(find.byKey(const Key('code')), '111111');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(starts, 2);

    auth.step('POST', '/api/auth/enroll/confirm', 'full', {'recoveryCodes': ['AAAA-1111', 'BBBB-2222']});
    await tester.enterText(find.byKey(const Key('code')), '222222');
    await tapAndSettle(tester, find.text(it.activate));
    expect(find.byType(RecoveryCodesScreen), findsOneWidget);
    expect(find.text('AAAA-1111\nBBBB-2222'), findsOneWidget);

    await tapAndSettle(tester, find.text(it.copy));
    expect(find.text(it.codesCopied), findsOneWidget);
    await tapAndSettle(tester, find.byType(CheckboxListTile));

    auth.backend.on('POST', '/api/account/passkeys/options', (_) => Reply.error(403, 'step_up_required'));
    await tapAndSettle(tester, find.text(it.createPasskey));
    expect(find.text(it.errStepUp), findsOneWidget);

    auth.backend.on('POST', '/api/account/passkeys/options', (_) => {'challenge': 'c'});
    auth.backend.on('POST', '/api/account/passkeys', (_) => {'ok': true});
    app.passkeys.fail = true;
    await tapAndSettle(tester, find.text(it.createPasskey));
    expect(find.text(it.passkeyNotCreated), findsOneWidget);

    app.passkeys.fail = false;
    await tapAndSettle(tester, find.text(it.createPasskey));
    expect(auth.backend.lastBody('/api/account/passkeys')['name'], it.defaultPasskeyPhone);
    expect(find.byType(MapOverviewScreen), findsOneWidget);
  });

  testWidgets('enrollment: later, failed setup, cancel', (tester) async {
    final auth = AuthBackend('enroll');
    auth.backend.on('POST', '/api/auth/enroll/start', (_) => {'secret': 'S', 'uri': 'otpauth://totp/x'});
    auth.step('POST', '/api/auth/enroll/confirm', 'full', {'recoveryCodes': ['A']});
    final app = TestApp(auth.backend);
    await app.start(tester);
    expect(find.text(it.copyKey), findsNothing);
    await tester.enterText(find.byKey(const Key('code')), '222222');
    await tapAndSettle(tester, find.text(it.activate));
    await tapAndSettle(tester, find.byType(CheckboxListTile));
    await tapAndSettle(tester, find.text(it.later));
    expect(find.byType(MapOverviewScreen), findsOneWidget);

    await app.session.logout();
    auth.stage = 'enroll';
    auth.backend.on('POST', '/api/auth/enroll/start', (_) => Reply.error(401, 'unauthorized'));
    await app.session.load();
    await settle(tester);
    expect(find.text(it.sessionExpired), findsOneWidget);
    await tapAndSettle(tester, find.text(it.loginAgain));
    expect(find.byType(LoginScreen), findsOneWidget);

    auth.stage = 'enroll';
    auth.backend.on('POST', '/api/auth/enroll/start', (_) => {'secret': 'S', 'uri': 'otpauth://totp/x'});
    await app.session.load();
    await settle(tester);
    await tapAndSettle(tester, find.text(it.cancel));
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('an invite opened while the session loads: no login', (tester) async {
    final auth = AuthBackend();
    auth.backend.on('GET', '/api/auth/invites/abc', (_) => {'email': 'new@example.com', 'name': 'Nuovo', 'reset': false});
    final app = TestApp(auth.backend);
    await app.start(tester);
    // The link opened in a new browser: the session isn't known yet
    app.session.ready = false;
    app.go(tester, '/invite/abc');
    await settle(tester);
    await app.session.load();
    await settle(tester);
    expect(find.text(it.inviteHint('new@example.com')), findsOneWidget);
  });

  testWidgets('a page asked before the login opens after it', (tester) async {
    final auth = AuthBackend();
    final app = TestApp(auth.backend);
    await app.start(tester);
    app.go(tester, '/notifications');
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    auth.step('POST', '/api/auth/passkey/verify', 'full');
    auth.backend.on('POST', '/api/auth/passkey/options', (_) => {'challenge': 'c'});
    await tapAndSettle(tester, find.text(it.loginPasskey));
    expect(find.text(it.notificationsTitle), findsWidgets);
  });
}
