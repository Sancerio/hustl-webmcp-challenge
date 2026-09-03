import 'package:flutter/widgets.dart';

/// Corner-radius scale. Use these tokens instead of raw literals so nested
/// surfaces stay visually concentric and bottom sheets are consistent app-wide.
class AppRadius {
  AppRadius._();

  /// Inputs, buttons, small controls.
  static const double control = 12;

  /// Cards and primary content surfaces.
  static const double card = 16;

  /// Bottom sheets (applied to the top corners only).
  static const double sheet = 28;

  /// Fully rounded pills / stadiums.
  static const double pill = 999;

  /// Concentric rule for nested rounded elements: the inner radius equals the
  /// outer radius minus the padding between them. Clamped at 0 so tiny insets
  /// never produce a negative (square-flipped) radius.
  static double concentric(double outer, double padding) {
    final inner = outer - padding;
    return inner < 0 ? 0 : inner;
  }

  // --- BorderRadius conveniences ---
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );

  /// Sheet rounding: top corners only.
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}
