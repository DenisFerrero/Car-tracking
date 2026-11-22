import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'core/session.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

/// License of the bundled typeface, in the licenses page of the app
void registerFontLicense() => LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['Barlow'], await rootBundle.loadString('assets/fonts/OFL.txt'));
    });

class CarTrackingApp extends StatefulWidget {
  const CarTrackingApp({super.key, required this.session});

  final Session session;

  @override
  State<CarTrackingApp> createState() => _CarTrackingAppState();
}

class _CarTrackingAppState extends State<CarTrackingApp> {
  late final router = buildRouter(widget.session);
  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    // The language follows the account (or the device before the login)
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final language = widget.session.language;
        Intl.defaultLocale = language;
        return MaterialApp.router(
          title: widget.session.config?.appName ?? 'Car Tracking',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
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
