import 'package:flutter/material.dart';

// Helper function to convert hex strings to Color
Color _hexToColor(String code) {
  return Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
}

/// Wave I (Apple Fitness+ x Whoop — "data as hero"): Hustl's ORIGINAL emerald +
/// electric-blue identity, restored and expressed as a premium athletic
/// instrument. Electric blue (#3B82F6) is the brand/primary — it matches the
/// app icon and is the Material `primary`; emerald (#10B981) is the success /
/// data accent (rings, goal-met, protein); amber (#F59E0B) is the warm warning.
/// The
/// canvas is a cool near-black (#0B0B0F) in dark with a layered surface ladder
/// so cards read as physical objects (NOT flat hairline rows), and a cool
/// off-white (#F2F5FA) in light. Solid color only — no gradients.
class AppColors {
  AppColors._();

  // --- Core tones ---
  /// Cool near-black: light-theme ink and the base of the dark canvas.
  static final Color brandCarbonBlack = _hexToColor('#0B0B0F');

  /// Cool mid gray for muted/secondary content.
  static final Color brandAshGray = _hexToColor('#B0B5C1');

  /// Cool near-white: dark-theme ink.
  static final Color brandCloudWhite = _hexToColor('#F8FAFC');

  // --- The accents (the restored Hustl palette) ---
  /// Secondary data accent + interactive links + calories alt.
  static final Color accentElectricBlue = _hexToColor('#3B82F6');

  /// Retained name for source compatibility — remapped onto blue (the app no
  /// longer uses purple as an identity hue).
  static final Color accentPurple = accentElectricBlue;

  /// PRIMARY brand color — rings, CTAs, active state, success.
  static final Color accentEmeraldGreen = _hexToColor('#10B981');

  /// Warm warning / over-budget / fat data.
  static final Color accentWarningAmber = _hexToColor('#F59E0B');

  /// Destructive / error only (not a data accent).
  static final Color accentAlertRed = _hexToColor('#EF4444');

  /// Effort (RIR reps-in-reserve) intensity scale — a muted, effort-specific
  /// palette. Deliberately desaturated so a column of effort gauges reads as a
  /// premium data signal rather than a traffic-light. "Easy" is teal, NOT the
  /// electric-blue accent, so 6+ never collides with the selected/interactive
  /// blue used elsewhere. Effort UI only.
  static final Color effortNearFailure = _hexToColor('#D25A54'); // RIR 0–1
  static final Color effortHard = _hexToColor('#C08A2E'); // RIR 2–3
  static final Color effortModerate = _hexToColor('#3C9A76'); // RIR 4–5
  static final Color effortEasy = _hexToColor('#3690A0'); // RIR 6+ (teal)

  /// Set-type indicator inks — darkened glyph shades that sit on the tinted
  /// fills (W amber, F terracotta). One hue per type; blue stays
  /// interactive-only (the ✓ Done key, active control chips) and never
  /// marks a set type. D / SS stay on the existing neutral slate tokens.
  static final Color warmupInkLight = _hexToColor('#B45309'); // amber-700
  static final Color warmupInkDark = _hexToColor('#FBBF24'); // amber-400
  static final Color warmupSolid = _hexToColor(
    '#D97706',
  ); // amber-600 (engaged fill, white glyph)
  static final Color failureInkLight = _hexToColor('#B7443E');
  static final Color failureInkDark = _hexToColor('#E07B76');

  /// Claude's official logo terracotta. An exact brand tint for the Claude
  /// connector mark — intentionally OUTSIDE the semantic palette (not an accent).
  static final Color brandClaudeTerracotta = _hexToColor('#D97757');

  // --- Primary (the brand accent: electric blue, matching the app icon) ---
  static final Color primaryLight = accentElectricBlue;
  static final Color onPrimaryLight = brandCloudWhite;
  static final Color primaryContainerLight = _hexToColor('#DCE8FD');
  static final Color onPrimaryContainerLight = _hexToColor('#1A3E8C');

  static final Color primaryDark = accentElectricBlue;
  static final Color onPrimaryDark = brandCloudWhite;
  static final Color primaryContainerDark = _hexToColor('#13294F');
  static final Color onPrimaryContainerDark = _hexToColor('#9DBDF7');

  // --- Secondary (neutral grays — calm support) ---
  static final Color secondaryLight = _hexToColor('#667085');
  static final Color onSecondaryLight = brandCloudWhite;
  static final Color secondaryContainerLight = _hexToColor('#EEF2F7');
  static final Color onSecondaryContainerLight = brandCarbonBlack;

  static final Color secondaryDark = brandAshGray;
  static final Color onSecondaryDark = brandCarbonBlack;
  static final Color secondaryContainerDark = _hexToColor('#23252E');
  static final Color onSecondaryContainerDark = brandCloudWhite;

  // --- Tertiary (emerald — success/protein semantics) ---
  static final Color tertiaryLight = accentEmeraldGreen;
  static final Color onTertiaryLight = brandCarbonBlack;
  static final Color tertiaryContainerLight = accentEmeraldGreen.withValues(
    alpha: 0.12,
  );
  static final Color onTertiaryContainerLight = _hexToColor('#04603F');

  static final Color tertiaryDark = accentEmeraldGreen;
  static final Color onTertiaryDark = brandCarbonBlack;
  static final Color tertiaryContainerDark = accentEmeraldGreen.withValues(
    alpha: 0.18,
  );
  static final Color onTertiaryContainerDark = accentEmeraldGreen;

  // --- Error (Alert Red) ---
  static final Color errorLight = accentAlertRed;
  static final Color onErrorLight = brandCloudWhite;
  static final Color errorContainerLight = accentAlertRed.withValues(
    alpha: 0.1,
  );
  static final Color onErrorContainerLight = accentAlertRed;

  static final Color errorDark = accentAlertRed.withValues(alpha: 0.9);
  static final Color onErrorDark = brandCarbonBlack;
  static final Color errorContainerDark = accentAlertRed.withValues(alpha: 0.2);
  static final Color onErrorContainerDark = errorDark;

  // --- Background (cool off-white light / cool near-black dark) ---
  static final Color backgroundLight = _hexToColor('#F2F5FA');
  static final Color onBackgroundLight = brandCarbonBlack;

  static final Color backgroundDark = _hexToColor('#0B0B0F');
  static final Color onBackgroundDark = brandCloudWhite;

  // --- Surface (LAYERED: cards sit above the canvas so they read as objects) ---
  static final Color surfaceLight = _hexToColor('#FFFFFF');
  static final Color onSurfaceLight = brandCarbonBlack;
  static final Color surfaceVariantLight = _hexToColor('#E9EEF6');
  static final Color onSurfaceVariantLight = _hexToColor('#5E677A');

  // Dark elevation ladder: canvas #0B0B0F -> card #15151F -> raised #1F2230.
  static final Color surfaceDark = _hexToColor('#15151F');
  static final Color onSurfaceDark = brandCloudWhite;
  static final Color surfaceVariantDark = _hexToColor('#1F2230');
  static final Color onSurfaceVariantDark = brandAshGray;

  // --- Outline (soft, not structural — cards/elevation carry structure now) ---
  static final Color outlineLight = _hexToColor('#D4DBE6');
  static final Color outlineVariantLight = _hexToColor('#E6EBF2');

  static final Color outlineDark = brandCloudWhite.withValues(alpha: 0.18);
  static final Color outlineVariantDark = brandCloudWhite.withValues(
    alpha: 0.09,
  );

  // --- Chips / Filters ---
  static final Color filterChipBackgroundLight = surfaceVariantLight;
  static final Color filterChipSelectedBackgroundLight = primaryLight;
  static final Color filterChipSelectedForegroundLight = onPrimaryLight;

  static final Color inputChipBackgroundLight = secondaryContainerLight;
  static final Color inputChipDeleteIconLight = onSecondaryContainerLight;

  static final Color filterChipBackgroundDark = surfaceVariantDark;
  static final Color filterChipSelectedBackgroundDark = primaryDark;
  static final Color filterChipSelectedForegroundDark = onPrimaryDark;

  static final Color inputChipBackgroundDark = secondaryContainerDark;
  static final Color inputChipDeleteIconDark = onSecondaryContainerDark;

  // --- Navigation (Bottom Bar) ---
  // The active tab is marked by the emerald primary; tokens come from the
  // colorScheme so no bespoke nav tokens are needed.

  // --- Elevation ladder (dark): canvas -> card -> raised ---
  static final Color surfaceOverlayDark = surfaceVariantDark;

  // Foreground color for content rendered on a solid accent surface (white on
  // the blue primary).
  static const Color onGradient = Color(0xFFF8FAFC);

  // --- Glass material tokens (rest-timer chip only) ---
  static final Color glassSurfaceDark = _hexToColor(
    '#15151F',
  ).withValues(alpha: 0.62);
  static final Color glassBorderDark = brandCloudWhite.withValues(alpha: 0.10);
  static const double glassBlurDark = 16;

  static final Color glassSurfaceLight = brandCloudWhite.withValues(
    alpha: 0.72,
  );
  static final Color glassBorderLight = brandCarbonBlack.withValues(
    alpha: 0.06,
  );
  static const double glassBlurLight = 12;

  // Opaque fallbacks (web / disabled-blur).
  static final Color glassSurfaceDarkOpaque = _hexToColor('#1F2230');
  static final Color glassSurfaceLightOpaque = _hexToColor('#F1F4F9');

  // --- Macro / data tokens ---
  // Protein = emerald, carbs = blue, fat = amber. Calories (the hero ring) =
  // emerald (primary). Same hues in both themes.
  static final Color macroProtein = accentEmeraldGreen;
  static final Color macroCarbs = accentElectricBlue;
  static final Color macroFat = accentWarningAmber;

  // Legacy light-theme variants collapse onto the unsuffixed tokens.
  static final Color macroProteinLight = macroProtein;
  static final Color macroCarbsLight = macroCarbs;
  static final Color macroFatLight = macroFat;

  // --- Health accent tokens: collapsed onto the restored palette ---
  static final Color accentLavender = accentElectricBlue;
  static final Color accentPeriwinkle = accentElectricBlue;
  static final Color accentBronze = accentWarningAmber;

  /// Theme-aware glyph ink for warm-up (W) surfaces sitting on an amber tint.
  static Color warmupInk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? warmupInkDark
      : warmupInkLight;

  /// Theme-aware glyph ink for failure (F) surfaces sitting on a terracotta
  /// tint.
  static Color failureInk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? failureInkDark
      : failureInkLight;

  /// Shared tint alpha for set-type badges/chips (16% light, 24% dark).
  static double setTypeTintAlpha(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.16;

  /// Shared tint alpha for idle set-type keyboard keys (12% light, 24% dark).
  static double setTypeKeyIdleAlpha(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.12;
}
