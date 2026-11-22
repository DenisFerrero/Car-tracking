import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Push notifications on Android through Firebase Cloud Messaging. Optional: the
/// Firebase project is given at build time, without google-services.json:
///   flutter build apk --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=...
///     --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
/// Without them the notifications arrive only while the app is open.
class Push {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured => !kIsWeb && _apiKey.isNotEmpty && _appId.isNotEmpty;
  static bool _initialized = false;

  static Future<void> init() async {
    if (!configured || _initialized) return;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
      ),
    );
    _initialized = true;
  }

  /// Asks the permission (Android 13+) and registers the token on the backend
  static Future<void> register(ApiClient api) async {
    if (!_initialized) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    // Registration token of the FCM HTTP v1 API used by the backend; the new
    // register()/onRegistered API gives installation ids instead
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token != null) await api.post('/api/account/push-tokens', {'token': token});
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((token) {
      api.post('/api/account/push-tokens', {'token': token}).ignore();
    });
  }
}
