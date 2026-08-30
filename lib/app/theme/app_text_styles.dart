import 'package:flutter/material.dart';

/// Wave G (MacroFactor fidelity) type system. Small, precise, dense.
///
/// The §12.1 hard scale:
/// - screen/app-bar title: 20 / w700                      -> [TextTheme.titleLarge]
/// - section header: 13 / w600 UPPERCASE +0.6 tracking    -> [sectionHeader]
/// - row label: 15 / w500                                 -> [TextTheme.bodyLarge]
/// - row value: 15 / w600 tabular                         -> [TextTheme.labelLarge]
/// - emphasized metric: 22 / w700 tabular (max anywhere
///   outside the rest timer)                              -> [metricEmphasis]
/// - caption/units: 12 / w400 onSurfaceVariant            -> [TextTheme.bodySmall]
///
/// Every headline/display slot except the rest-timer tier ([TextTheme.displayLarge])
/// is pinned to the 22px metric cap so un-migrated call sites render quiet.
class AppTextStyles {
  AppTextStyles._();

  /// Bundled font family (static weights 400/500/600/700 in assets/fonts).
  /// The asset-registered font is the only path — no runtime font fetching,
  /// so theme construction stays synchronous and offline-safe.
  static const String fontFamily = 'DM Sans';

  /// Concrete cross-platform monospace fallback chain for code/command snippets
  /// (the connector URL, CLI blocks) — the one sanctioned mono use. Named
  /// explicitly so iOS/web don't drift on the bare 'monospace' string.
  static const List<String> monoFallback = <String>[
    'SFMono-Regular',
    'Menlo',
    'Consolas',
    'Roboto Mono',
  ];

  /// Apply the mono family to [base] (keeps its size/weight/color).
  static TextStyle mono(TextStyle? base) => (base ?? const TextStyle()).copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: monoFallback,
  );

  static const double _rowLineHeight = 20 / 15;
  static const double _captionLineHeight = 16 / 12;

  /// Static system fallback chain for glyphs missing from bundled DM Sans.
  /// Public so component themes (e.g. button text styles in AppTheme) can pin
  /// the same family + fallbacks — ButtonStyle.textStyle REPLACES the
  /// textTheme style, so it must carry the family itself.
  static const List<String> fontFallback = <String>[
    'SF Pro Text',
    'Roboto',
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
  ];

  /// Applies tabular figures to a style. Every animated or live-updating
  /// number (timers, weights, calories) MUST use this to prevent layout shift
  /// as digits change width.
  static TextStyle metric(TextStyle style) {
    return style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  /// Section header voice: 13/w600, +0.6 tracking, onSurfaceVariant.
  /// Render the text in UPPERCASE (see `SectionHeader` in
  /// `core/widgets/app_section.dart`, which uppercases for you).
  static TextStyle sectionHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 13,
      height: 16 / 13,
      letterSpacing: 0.6,
    );
  }

  /// Emphasized metric: 22/w700 tabular. The LARGEST number allowed anywhere
  /// outside the rest-timer countdown.
  static TextStyle metricEmphasis(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      color: colors.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 28 / 22,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Nutrition data-as-hero numeral: 40/w700 tabular. The single sanctioned
  /// big-number tier for the nutrition screens — the Strategy calorie budget,
  /// the Weight trend hero, and Insights headline figures all use THIS so they
  /// read as one family. It's a deliberate, isolated exception to the 22px
  /// metric cap (a true screen hero), but is NOT the 56px [TextTheme.displayLarge]
  /// which stays reserved for the rest-timer countdown.
  static TextStyle nutritionHero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      color: colors.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: 40,
      height: 44 / 40,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextTheme light(TextTheme base, ColorScheme colors) =>
      _build(base, colors);

  static TextTheme dark(TextTheme base, ColorScheme colors) =>
      _build(base, colors);

  static TextTheme _build(TextTheme base, ColorScheme colors) {
    final themed = base.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    );

    const tabular = [FontFeature.tabularFigures()];

    // The 22/w700 tabular metric tier — every legacy headline/display slot
    // (except the rest-timer displayLarge) collapses onto it.
    final metricTier = themed.headlineMedium?.copyWith(
      color: colors.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 28 / 22,
      letterSpacing: 0,
      fontFeatures: tabular,
    );

    return themed.copyWith(
      // Reserved EXCLUSIVELY for the rest-timer countdown.
      displayLarge: themed.displayLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 56,
        height: 1.05,
        letterSpacing: -0.5,
        fontFeatures: tabular,
      ),
      displayMedium: metricTier,
      displaySmall: metricTier,
      headlineLarge: metricTier,
      headlineMedium: metricTier,
      headlineSmall: themed.headlineSmall?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 26 / 20,
        letterSpacing: 0,
      ),
      // Screen / app-bar title.
      titleLarge: themed.titleLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 26 / 20,
        letterSpacing: 0,
      ),
      // Dialog / sheet titles.
      titleMedium: themed.titleMedium?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 22 / 16,
        letterSpacing: 0,
      ),
      // Section-header voice (callers must UPPERCASE; prefer SectionHeader).
      titleSmall: themed.titleSmall?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 16 / 13,
        letterSpacing: 0.6,
      ),
      // Row label (the default list voice).
      bodyLarge: themed.bodyLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w500,
        fontSize: 15,
        height: _rowLineHeight,
        letterSpacing: 0,
      ),
      // Reading voice.
      bodyMedium: themed.bodyMedium?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w400,
        fontSize: 15,
        height: _rowLineHeight,
        letterSpacing: 0,
      ),
      // Caption / units.
      bodySmall: themed.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w400,
        fontSize: 12,
        height: _captionLineHeight,
        letterSpacing: 0,
      ),
      // Row value (and button text): tabular so aligned columns never shift.
      labelLarge: themed.labelLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        height: _rowLineHeight,
        letterSpacing: 0,
        fontFeatures: tabular,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontSize: 13,
        height: 16 / 13,
        letterSpacing: 0,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontSize: 11,
        height: 14 / 11,
        letterSpacing: 0.2,
      ),
    );
  }
}
