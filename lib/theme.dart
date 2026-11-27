import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A colour palette from Settings → Appearance: [main] carries the app (the
/// spending card, the Add button, the logo), [highlight] marks only what
/// needs attention (Due soon, today's spending).
class Palette {
  const Palette(
      this.id, this.name, this.main, this.highlight, this.light, this.dark);

  /// Stored in the [kPaletteSetting] setting; never rename.
  final String id;
  final String name;
  final Color main;
  final Color highlight;

  /// Page backgrounds.
  final Color light;
  final Color dark;
}

const List<Palette> kPalettes = [
  Palette('navy', 'Navy', Color(0xFF16294D), Color(0xFFF2A900),
      Color(0xFFF4F6FA), Color(0xFF0B1424)),
  Palette('emerald', 'Emerald', Color(0xFF0B6E4F), Color(0xFFE8A317),
      Color(0xFFF2F7F4), Color(0xFF08130F)),
  Palette('charcoal', 'Charcoal', Color(0xFF22272E), Color(0xFF0E9F9A),
      Color(0xFFF5F5F3), Color(0xFF111316)),
  Palette('violet', 'Violet', Color(0xFF4C1D95), Color(0xFFF472B6),
      Color(0xFFF6F4FC), Color(0xFF0E0B1E)),
];

/// The chosen palette; MaterialApp rebuilds when it changes.
final ValueNotifier<Palette> palette = ValueNotifier(kPalettes.first);

/// Device setting (TxnRepository.setSetting): a [Palette.id].
const String kPaletteSetting = 'palette';

Palette paletteNamed(String? id) =>
    kPalettes.firstWhere((p) => p.id == id, orElse: () => kPalettes.first);

/// Light, dark or the phone's setting (Settings → Appearance). Read from
/// [kThemeSetting] at launch; MaterialApp rebuilds when it changes.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

/// Device setting (TxnRepository.setSetting): 'system', 'light' or 'dark'.
const String kThemeSetting = 'theme';

ThemeMode themeModeNamed(String? name) => ThemeMode.values
    .firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);

/// Same-width digits so amounts line up in lists and don't jitter.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

/// The palette's colours where the colour scheme has no slot for them.
class Brand extends ThemeExtension<Brand> {
  const Brand({required this.hero, required this.highlight});

  /// The deep main colour, in both modes, under white text.
  final Color hero;
  final Color highlight;

  @override
  Brand copyWith({Color? hero, Color? highlight}) =>
      Brand(hero: hero ?? this.hero, highlight: highlight ?? this.highlight);

  @override
  Brand lerp(Brand? other, double t) => other == null
      ? this
      : Brand(
          hero: Color.lerp(hero, other.hero, t)!,
          highlight: Color.lerp(highlight, other.highlight, t)!);
}

extension BrandOf on BuildContext {
  /// The default palette's when the theme has none (a bare MaterialApp).
  Brand get brand =>
      Theme.of(this).extension<Brand>() ??
      Brand(hero: kPalettes.first.main, highlight: kPalettes.first.highlight);
}

ThemeData buildTheme(Brightness brightness, [Palette? chosen]) {
  final p = chosen ?? kPalettes.first;
  final dark = brightness == Brightness.dark;
  final bg = dark ? p.dark : p.light;
  Color lift(double t) => Color.lerp(bg, Colors.white, t)!;
  var scheme = ColorScheme.fromSeed(seedColor: p.main, brightness: brightness);
  scheme = dark
      ? scheme.copyWith(
          surface: bg,
          surfaceContainerLowest: bg,
          surfaceContainerLow: lift(0.03),
          surfaceContainer: lift(0.05),
          surfaceContainerHigh: lift(0.08),
          surfaceContainerHighest: lift(0.11),
        )
      : scheme.copyWith(primary: p.main, onPrimary: Colors.white);
  final card = dark ? scheme.surfaceContainer : Colors.white;
  final hairline = dark
      ? Colors.white.withValues(alpha: 0.08)
      : scheme.outlineVariant.withValues(alpha: 0.5);
  final base = ThemeData(
      colorScheme: scheme, useMaterial3: true, fontFamily: 'PlusJakartaSans');
  final text = base.textTheme;

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    // Lifted a little in dark mode so the button and logo stand off the page.
    extensions: [
      Brand(
          hero: dark ? Color.lerp(p.main, Colors.white, 0.16)! : p.main,
          highlight: p.highlight)
    ],
    textTheme: text.copyWith(
      displaySmall: text.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle:
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: card,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: hairline),
      showCheckmark: false,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
    dividerTheme: DividerThemeData(color: hairline),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

extension MoneyColors on ColorScheme {
  /// Money coming in. A fixed green, tuned per brightness for contrast.
  Color get moneyIn => brightness == Brightness.dark
      ? const Color(0xFF7DD99A)
      : const Color(0xFF1B7A3A);
}

/// The "+" button in the palette's main colour.
class BrandFab extends StatelessWidget {
  const BrandFab({super.key, required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: context.brand.hero,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add),
        label: Text(label),
      );
}
