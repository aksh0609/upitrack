import 'package:flutter/material.dart';

/// The app's single seed colour: a calm teal that reads as "money, trusted".
const Color kSeed = Color(0xFF0F766E);

/// Same-width digits so amounts line up in lists and don't jitter.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final rounded =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 2,
      titleTextStyle:
          base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: rounded,
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  );
}

extension MoneyColors on ColorScheme {
  /// Money coming in. A fixed green, tuned per brightness for contrast.
  Color get moneyIn => brightness == Brightness.dark
      ? const Color(0xFF7DD99A)
      : const Color(0xFF1B7A3A);
}
