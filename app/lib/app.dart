import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'core/session.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

class CarTrackingApp extends StatefulWidget {
  const CarTrackingApp({super.key, required this.session});

  final Session session;

  @override
  State<CarTrackingApp> createState() => _CarTrackingAppState();
}

class _CarTrackingAppState extends State<CarTrackingApp> {
  late final router = buildRouter(widget.session);

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E88E5);
    // The language follows the account (or the device before the login)
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final language = widget.session.language;
        Intl.defaultLocale = language;
        return MaterialApp.router(
          title: widget.session.config?.appName ?? 'Car Tracking',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
          darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        );
      },
    );
  }
}
