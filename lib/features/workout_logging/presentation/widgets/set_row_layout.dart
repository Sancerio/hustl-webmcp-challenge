import 'package:flutter/widgets.dart';

/// Shared column geometry for the active-workout sets table.
///
/// The card-level header row ([ExerciseCard]) and the per-set data row
/// ([SetRowContent]) are built in two different widgets. To keep the header
/// labels ("Set / Prev / kg / Reps") lined up exactly above their columns,
/// both reference the SAME constants here. Changing a column width in one place
/// updates both the header and the rows, so they can never drift apart.
class SetRowLayout {
  const SetRowLayout._();

  /// Inner horizontal padding applied to BOTH the sets-table header and each
  /// data row (`SetRow` wraps `SetRowContent` in `fromLTRB(rowPadding, …)`).
  /// Matches the exercise card's title inset (16) so the "Set" column and its
  /// numbers line up under the exercise name rather than hugging the card edge.
  static const double rowPadding = 16;

  /// "Set" column: holds the tappable set badge that doubles as the set-type
  /// selector — the working ordinal, or a `W`/`F`/`D` pill, or an `A1/B2`
  /// superset round label. Sized to fit a 22px badge, a 2-digit ordinal ("10"),
  /// and the popup's tap padding now that the separate type-button slot is gone.
  static const double setColumnWidth = 40;

  /// Gap between the "Set" badge cell and the "Previous" column.
  static const double previousLeadingGap = 8;

  /// Weight / distance field width (the "kg" / "km" column).
  ///
  /// Wide enough that a 3-digit-plus-decimal value (`122.5`) sits fully left of
  /// the inline "kg"/"km" suffix instead of clipping into it, while staying
  /// compact so the flexible "Previous" column keeps room to show last
  /// session's value on a 360/390 phone. The Previous [Expanded] absorbs the
  /// slack and ellipsizes on the very smallest (320dp) phones; the entry fields
  /// never shrink.
  static const double weightFieldWidth = 76;

  /// Gap that follows the weight field before the reps/time column.
  static const double weightTrailingGap = 8;

  /// Reps column width for weight×reps logging ("Reps"). Compact — a 2–3 digit
  /// rep count fits comfortably.
  static const double repsFieldWidth = 56;

  /// Duration column width for duration-only / distance+duration ("Time"). A
  /// touch wider than [repsFieldWidth] so an `mm:ss` value reads comfortably.
  static const double durationFieldWidth = 80;

  /// Gap between the reps/time column and the completion button.
  static const double completionLeadingGap = 4;

  /// Completion button column width (matches `SetRowCompletionButton`).
  static const double completionButtonWidth = 34;
}
