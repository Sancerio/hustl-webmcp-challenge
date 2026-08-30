import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';

/// Intensity colour for a RIR value: 0–1 near-failure (red), 2–3 hard (amber),
/// 4–5 moderate (green), 6+ easy (teal). Uses the muted, effort-specific
/// [AppColors] scale (desaturated, and teal — not the blue accent — at the easy
/// end) so effort reads as a premium data signal. Single source of truth —
/// every RIR-aware widget (set input keyboard, reps field tag, the
/// exercise-history reserve gauge) shares this exact palette.
Color rirColor(int rir) {
  if (rir <= 1) return AppColors.effortNearFailure;
  if (rir <= 3) return AppColors.effortHard;
  if (rir <= 5) return AppColors.effortModerate;
  return AppColors.effortEasy;
}
