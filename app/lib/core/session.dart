import 'package:flutter/widgets.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import 'api.dart';
import 'live.dart';
import 'models.dart';

/// Stage of the session on the backend: password ok and second factor missing,
/// authenticator app to configure, or complete.
enum Stage { none, mfaPending, enroll, full }

Stage _stageOf(String? value) => switch (value) {
      'mfa_pending' => Stage.mfaPending,
      'enroll' => Stage.enroll,
      'full' => Stage.full,
      _ => Stage.none,
    };

/// Languages of the app
const supportedLanguages = ['it', 'en'];

/// Language of the device if supported, English otherwise
String detectLanguage(Locale locale) => supportedLanguages.contains(locale.languageCode) ? locale.languageCode : 'en';

/// Passkeys of the platform (fingerprint / screen lock): JSON in, JSON out
class Passkeys {
  const Passkeys();

  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async =>
      (await PasskeyAuthenticator().register(RegisterRequestType.fromJson(options))).toJson();

  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async =>
      (await PasskeyAuthenticator().authenticate(AuthenticateRequestType.fromJson(options))).toJson();
}

/// Login state, language and authentication flows. 2FA is mandatory: password + TOTP
/// (or a recovery code), or a passkey (fingerprint / screen lock, a second factor by itself).
class Session extends ChangeNotifier {
  Session(this.api, this.live, {this.passkeys = const Passkeys(), Locale? deviceLocale})
      : deviceLocale = deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale;

  final ApiClient api;
  final LiveChannel live;
  final Passkeys passkeys;
  final Locale deviceLocale;

  Stage stage = Stage.none;
  User? user;
  ServerConfig? config;
  bool ready = false;

  /// Codes to show once after the TOTP enrollment
  List<String>? pendingRecoveryCodes;

  bool get loggedIn => stage == Stage.full;

  /// Language of the app: the one saved with the account, the device one before the login
  String get language => user?.locale ?? detectLanguage(deviceLocale);

  Future<void> load() async {
    if (api.hasServer) {
      try {
        config = ServerConfig.fromJson(await api.get('/api/config') as Map<String, dynamic>);
        final session = await api.get('/api/auth/session') as Map<String, dynamic>;
        await _apply(session['stage'] as String?, session['user']);
      } on ApiException catch (_) {
        stage = Stage.none;
      }
    }
    ready = true;
    notifyListeners();
  }

  /// Mobile only: address of the platform, checked with /api/config
  Future<void> connect(String url) async {
    var address = url.trim();
    if (!address.startsWith('http://') && !address.startsWith('https://')) address = 'https://$address';
    final previous = api.baseUrl;
    await api.setServer(address);
    try {
      config = ServerConfig.fromJson(await api.get('/api/config') as Map<String, dynamic>);
    } catch (_) {
      await api.setServer(previous);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> changeServer() async {
    await logout();
    await api.setServer('');
    config = null;
    notifyListeners();
  }

  Future<void> _apply(String? newStage, dynamic userJson) async {
    stage = _stageOf(newStage);
    if (userJson is Map<String, dynamic>) user = User.fromJson(userJson);
    if (stage == Stage.full) {
      live.start();
      // First login: the language detected on the device becomes the one of the account
      if (user != null && user!.locale == null) await setLanguage(detectLanguage(deviceLocale));
    } else {
      live.stop();
    }
  }

  /// Saves the language with the account (push notifications use it too)
  Future<void> setLanguage(String language) async {
    final current = user;
    if (current == null || !supportedLanguages.contains(language)) return;
    try {
      await api.patch('/api/account', {'locale': language});
    } on ApiException catch (_) {
      // Kept for this session, saved at the next login
    }
    user = User(id: current.id, email: current.email, name: current.name, isAdmin: current.isAdmin, locale: language);
    notifyListeners();
  }

  Future<void> rename(String name) async {
    await api.patch('/api/account', {'name': name});
    final current = user!;
    user = User(id: current.id, email: current.email, name: name, isAdmin: current.isAdmin, locale: current.locale);
    notifyListeners();
  }

  Future<void> _afterStep(Map<String, dynamic> response) async {
    final token = response['token'] as String?;
    if (token != null) await api.setToken(token);
    if (response['recoveryCodes'] is List) {
      pendingRecoveryCodes = (response['recoveryCodes'] as List).cast<String>();
    }
    final session = await api.get('/api/auth/session') as Map<String, dynamic>;
    await _apply(session['stage'] as String?, session['user']);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final response = await api.post('/api/auth/login', {
      'email': email.trim(),
      'password': password,
      'client': api.clientType,
    });
    await _afterStep(response as Map<String, dynamic>);
  }

  Future<void> verifyTotp(String code) async {
    await _afterStep(await api.post('/api/auth/totp', {'code': code.trim()}) as Map<String, dynamic>);
  }

  Future<int> verifyRecoveryCode(String code) async {
    final response = await api.post('/api/auth/recovery', {'code': code.trim()}) as Map<String, dynamic>;
    await _afterStep(response);
    return response['recoveryCodesLeft'] as int? ?? 0;
  }

  Future<void> loginWithPasskey() async {
    final options = await api.post('/api/auth/passkey/options') as Map<String, dynamic>;
    final credential = await passkeys.authenticate(options);
    final response = await api.post('/api/auth/passkey/verify', {'response': credential, 'client': api.clientType});
    await _afterStep(response as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> invite(String token) async =>
      await api.get('/api/auth/invites/$token') as Map<String, dynamic>;

  Future<void> acceptInvite(String token, String password) async {
    final response = await api.post('/api/auth/invites/$token', {'password': password, 'client': api.clientType});
    await _afterStep(response as Map<String, dynamic>);
  }

  /// TOTP secret and otpauth:// uri to show as QR code
  Future<({String secret, String uri})> startEnrollment() async {
    final response = await api.post('/api/auth/enroll/start') as Map<String, dynamic>;
    return (secret: response['secret'] as String, uri: response['uri'] as String);
  }

  Future<void> confirmEnrollment(String code) async {
    await _afterStep(await api.post('/api/auth/enroll/confirm', {'code': code.trim()}) as Map<String, dynamic>);
  }

  void clearRecoveryCodes() {
    pendingRecoveryCodes = null;
    notifyListeners();
  }

  /// New passkey of the current account. [code] is the TOTP when the login is not recent.
  Future<void> addPasskey(String name, {String? code}) async {
    final options = await api.post('/api/account/passkeys/options', {'code': ?code}) as Map<String, dynamic>;
    final credential = await passkeys.register(options);
    await api.post('/api/account/passkeys', {'name': name, 'response': credential});
  }

  Future<void> logout() async {
    try {
      await api.post('/api/auth/logout');
    } catch (_) {
      // Offline: the local session is dropped anyway
    }
    await _drop();
  }

  /// Deletes the account and all its data; [email] confirms the intention
  Future<void> deleteAccount(String email, {String? code}) async {
    await api.delete('/api/account', {'email': email, 'code': ?code});
    await _drop();
  }

  Future<void> _drop() async {
    await api.setToken(null);
    live.stop();
    stage = Stage.none;
    user = null;
    notifyListeners();
  }
}
