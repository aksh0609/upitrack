import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Seed for the colour scheme: violet.
const Color kSeed = Color(0xFF7C3AED);

const Color _blue = Color(0xFF2563EB);
const Color _violet = Color(0xFF7C3AED);
const Color _pink = Color(0xFFDB2777);

/// The brand gradient: blue → violet → pink. Hero card, FAB, logo mark.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_blue, _violet, _pink],
);

/// Coloured shadow under gradient surfaces.
const Color kGlow = _violet;

/// Same-width digits so amounts line up in lists and don't jitter.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  if (dark) {
    // Deep navy instead of near-black, so sheets and dialogs match [Aurora].
    scheme = scheme.copyWith(
      surface: const Color(0xFF0C0E20),
      surfaceContainerLowest: const Color(0xFF080A18),
      surfaceContainerLow: const Color(0xFF12142B),
      surfaceContainer: const Color(0xFF171A35),
      surfaceContainerHigh: const Color(0xFF1D2040),
      surfaceContainerHighest: const Color(0xFF24284C),
    );
  }
  // Frosted panels: translucent so the background glows through.
  final glass = dark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.75);
  final hairline = dark
      ? Colors.white.withValues(alpha: 0.10)
      : scheme.outlineVariant.withValues(alpha: 0.6);
  final base = ThemeData(
      colorScheme: scheme, useMaterial3: true, fontFamily: 'PlusJakartaSans');
  final text = base.textTheme;
  final page = _AuroraTransitions(const FadeForwardsPageTransitionsBuilder());
  final iosPage = _AuroraTransitions(const CupertinoPageTransitionsBuilder());

  return base.copyWith(
    // Every page paints [Aurora] itself, via the page transitions below.
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values)
        p: p == TargetPlatform.iOS || p == TargetPlatform.macOS
            ? iosPage
            : page,
    }),
    textTheme: text.copyWith(
      displaySmall: text.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
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
      color: glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: glass,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: hairline),
      showCheckmark: false,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface.withValues(alpha: dark ? 0.85 : 0.9),
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
      fillColor: glass,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
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

/// The app background: a deep navy (or soft lavender, in light mode) wash
/// with blue, pink and violet glows. Static, so it costs one paint per page.
class Aurora extends StatelessWidget {
  const Aurora({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.40 : 0.20;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF080A18), Color(0xFF0E0B1E)]
              : const [Color(0xFFF7F7FD), Color(0xFFFCF4F9)],
        ),
      ),
      child: Stack(
        children: [
          RepaintBoundary(
            child: Stack(children: [
              _glow(const Alignment(-1.2, -1.1), _blue, a, 1.1),
              _glow(const Alignment(1.3, -0.5), _pink, a * 0.7, 0.9),
              _glow(const Alignment(-0.2, 1.3), _violet, a * 0.6, 1.0),
            ]),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  static Widget _glow(Alignment at, Color color, double alpha, double radius) =>
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: at,
              radius: radius,
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0)
              ],
            ),
          ),
        ),
      );
}

/// Wraps each page in [Aurora], then runs the platform's own transition.
class _AuroraTransitions extends PageTransitionsBuilder {
  const _AuroraTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      inner.buildTransitions(
          route, context, animation, secondaryAnimation, Aurora(child: child));
}
