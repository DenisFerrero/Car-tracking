import 'package:flutter/material.dart';

// "Night road" look: deep petrol of a dashboard at night, amber of the road signs and of
// the instrument lights, squared shapes and the Barlow typeface (road signage style).
// Light and dark share the identity: petrol bars, amber actions.

const petrol = Color(0xFF0F3D3E);
const petrolDeep = Color(0xFF0A2A2B);
const amber = Color(0xFFFFB300);
const _radius = BorderRadius.all(Radius.circular(4));
const _squared = RoundedRectangleBorder(borderRadius: _radius);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: petrol,
    brightness: brightness,
    primary: dark ? const Color(0xFF7FC8C4) : petrol,
    onPrimary: dark ? petrolDeep : Colors.white,
    secondary: amber,
    onSecondary: const Color(0xFF231A00),
    secondaryContainer: dark ? const Color(0xFF4A3800) : const Color(0xFFFFE7A8),
    onSecondaryContainer: dark ? const Color(0xFFFFE7A8) : const Color(0xFF3A2C00),
    surface: dark ? const Color(0xFF101818) : const Color(0xFFF3F4F1),
    surfaceContainerLowest: dark ? const Color(0xFF0B1212) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF151F1F) : const Color(0xFFFAFAF8),
    surfaceContainer: dark ? const Color(0xFF192424) : const Color(0xFFFFFFFF),
    surfaceContainerHigh: dark ? const Color(0xFF1E2A2A) : const Color(0xFFF7F8F5),
    surfaceContainerHighest: dark ? const Color(0xFF243131) : const Color(0xFFE9ECE8),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Barlow');
  final text = base.textTheme;
  // Labels of buttons, tabs and navigation: spaced like a road sign
  const label = TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w600, letterSpacing: 0.6);
  final bar = dark ? petrolDeep : petrol;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.1),
      labelLarge: text.labelLarge?.merge(label),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bar,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Colors.white),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: amber,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle: label,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bar,
      indicatorColor: amber,
      indicatorShape: _squared,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) =>
          IconThemeData(color: states.contains(WidgetState.selected) ? const Color(0xFF231A00) : Colors.white70)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => label.copyWith(
          fontSize: 12, color: states.contains(WidgetState.selected) ? amber : Colors.white70)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: bar,
      indicatorColor: amber,
      indicatorShape: _squared,
      selectedIconTheme: const IconThemeData(color: Color(0xFF231A00)),
      unselectedIconTheme: const IconThemeData(color: Colors.white70),
      selectedLabelTextStyle: label.copyWith(color: amber, fontSize: 12),
      unselectedLabelTextStyle: label.copyWith(color: Colors.white70, fontSize: 12),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: dark ? const Color(0xFF2A3838) : const Color(0xFFDDE2DD)),
      ),
      elevation: 0,
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: amber, foregroundColor: const Color(0xFF231A00), shape: _squared, textStyle: label),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: _squared, textStyle: label, side: BorderSide(color: scheme.primary)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: _squared, textStyle: label)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: _squared, textStyle: label)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: _squared, selectedBackgroundColor: scheme.secondaryContainer),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: amber,
      foregroundColor: Color(0xFF231A00),
      shape: _squared,
      extendedTextStyle: TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, letterSpacing: 0.8),
    ),
    chipTheme: ChipThemeData(shape: _squared, labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, color: scheme.onSurface)),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(borderRadius: _radius)),
    dialogTheme: const DialogThemeData(shape: _squared),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: _radius, side: BorderSide(color: amber, width: 0)),
      backgroundColor: petrolDeep,
      contentTextStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white),
      actionTextColor: amber,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? petrolDeep : null),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? amber : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: amber),
    listTileTheme: ListTileThemeData(selectedColor: dark ? amber : petrol, selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.35)),
  );
}

/// Map tiles in the colors of the app: desaturated with a petrol tint, dark at night
const lightMapFilter = ColorFilter.matrix([
  0.55, 0.30, 0.08, 0, 4, //
  0.20, 0.62, 0.10, 0, 8,
  0.20, 0.30, 0.48, 0, 10,
  0, 0, 0, 1, 0,
]);

/// Inverted luminance, petrol blacks: the roads light up like at night
const darkMapFilter = ColorFilter.matrix([
  -0.38, -0.50, -0.10, 0, 232, //
  -0.33, -0.55, -0.08, 0, 238,
  -0.30, -0.50, -0.05, 0, 232,
  0, 0, 0, 1, 0,
]);

/// Card with the amber stripe on the left, for the main panel of a screen
class AccentCard extends StatelessWidget {
  const AccentCard({super.key, required this.child, this.elevation = 0});

  final Widget child;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: amber, width: 4))),
        child: child,
      ),
    );
  }
}
