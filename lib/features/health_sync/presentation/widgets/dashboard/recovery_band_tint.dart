import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';

/// The day's-ledger receipt (plan 012) marks external (other-app) workouts with
/// a distinct violet source dot. It lives here beside the band-tint mapping so
/// there is a single defining site, and — deliberately — it is NEVER the
/// Recharge band's warm amber, so a violet dot can never read as a recovery
/// warning. Hustl sessions use `AppColors.accentEmeraldGreen`; ambient movement
/// uses a neutral `onSurfaceVariant` slate.
const Color kExternalWorkoutTint = Color(0xFFA78BFA);

/// Resolved, token-mapped colors for a readiness band. The domain hands us a
/// semantic [RecoveryBandTint]; this maps it onto `colorScheme` / `AppColors`
/// tokens. The lowest band ("Recharge") is warm amber — never `colorScheme.error`
/// / red. Color is always paired with the band's text label by callers, so the
/// surface stays color-blind safe.
class RecoveryBandColors {
  const RecoveryBandColors({
    required this.accent,
    required this.container,
    required this.onContainer,
  });

  /// The primary tint (ring, pill border accent).
  final Color accent;

  /// A soft container fill for pills / chips.
  final Color container;

  /// Readable foreground for content on [container].
  final Color onContainer;

  /// Resolves band colors from the four-band tint hint. Falls back to a quiet
  /// neutral when there is no band yet (calibrating / no data) so the surface
  /// renders exactly as today.
  static RecoveryBandColors resolve(
    ColorScheme colorScheme,
    RecoveryFlowBand? band,
  ) {
    if (band == null) {
      return RecoveryBandColors(
        accent: colorScheme.primary,
        container: colorScheme.surfaceContainerHighest,
        onContainer: colorScheme.onSurfaceVariant,
      );
    }
    switch (band.tintHint) {
      case RecoveryBandTint.vital:
        // Charged → the existing high-band positive accent (emerald).
        return RecoveryBandColors(
          accent: AppColors.accentEmeraldGreen,
          container: colorScheme.tertiaryContainer,
          onContainer: colorScheme.onTertiaryContainer,
        );
      case RecoveryBandTint.calm:
        // Ready → a calm primary/secondary accent.
        return RecoveryBandColors(
          accent: colorScheme.primary,
          container: colorScheme.primaryContainer,
          onContainer: colorScheme.onPrimaryContainer,
        );
      case RecoveryBandTint.soft:
        // Steady → a quiet, amber-leaning neutral. Deliberately desaturated
        // toward the surface's neutral (`onSurfaceVariant`) so it reads as a
        // clearly distinct, muted tone next to Recharge's vivid warm amber —
        // the two must never be confusable — while staying warm-leaning and
        // never alarmist.
        final softAmber = Color.lerp(
          AppColors.accentWarningAmber,
          colorScheme.onSurfaceVariant,
          0.45,
        )!;
        return RecoveryBandColors(
          accent: softAmber,
          container: softAmber.withValues(alpha: 0.16),
          onContainer: colorScheme.onSurface,
        );
      case RecoveryBandTint.warmAmber:
        // Recharge → warm amber. NEVER red.
        return RecoveryBandColors(
          accent: AppColors.accentWarningAmber,
          container: AppColors.accentWarningAmber.withValues(alpha: 0.22),
          onContainer: colorScheme.onSurface,
        );
    }
  }
}
