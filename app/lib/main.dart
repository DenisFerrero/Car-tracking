import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/live.dart';
import 'core/phone_service.dart';
import 'core/phone_tracker.dart';
import 'core/providers.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final language in supportedLanguages) {
    await initializeDateFormatting(language);
  }

  final api = await ApiClient.create();
  final live = LiveChannel(api);
  final session = Session(api, live);
  // Channel of the notification of the phone sharing, named in the language of the system
  final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  final channel = lookupAppLocalizations(Locale(detectLanguage(Locale(system)))).phoneChannel;
  final phone = PhoneTracker(api, session, ForegroundPhoneService(channelName: channel));
  try {
    await Push.init();
  } catch (_) {
    // Wrong Firebase configuration: the app works without push notifications
  }
  session.load();

  registerFontLicense();
  runApp(ProviderScope(
    retry: retryNetwork,
    overrides: [
      apiProvider.overrideWithValue(api),
      liveProvider.overrideWithValue(live),
      sessionProvider.overrideWithValue(session),
      phoneTrackerProvider.overrideWithValue(phone),
    ],
    child: CarTrackingApp(session: session),
  ));
}
