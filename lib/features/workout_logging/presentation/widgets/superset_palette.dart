import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';

/// Maps a [SupersetGrouping]-supplied `colorIndex` (0..3) to a quiet,
/// theme-driven accent for the per-group left rail and header chip.
///
/// The grouping helper intentionally returns an int index, not a [Color], so
/// the UI owns the palette and keeps it theme-aware. No hard-coded `Color(0x…)`
/// values: each entry derives from `colorScheme` or an `AppColors` brand token.
class SupersetPalette {
  const SupersetPalette._();

  /// Resolve the accent [Color] for a 0-based group [colorIndex]. Wraps the
  /// palette so arbitrarily many groups stay legible. The result is a fully
  /// saturated accent meant to be used at low alpha for rails/chips.
  static Color accentFor(BuildContext context, int colorIndex) {
    final colors = Theme.of(context).colorScheme;
    // Four restrained, distinguishable accents — all theme-derived. Amber is
    // intentionally excluded so the rail never reads as a warm-up cue.
    final palette = <Color>[
      colors.secondary,
      colors.tertiary,
      AppColors.accentElectricBlue,
      AppColors.accentEmeraldGreen,
    ];
    final i = colorIndex % palette.length;
    return palette[i < 0 ? 0 : i];
  }
}
