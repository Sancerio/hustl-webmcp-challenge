import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../domain/models/food_log_entry.dart';
import '../utils/macro_format.dart';
import 'food_entry_avatar.dart';

/// The "plate" is the staging tray for the Add Food sheet: foods you've picked
/// but not yet committed. It is a STATE, not a screen — the parent holds a
/// `List<FoodLogEntry>` and a single "Log foods (N)" commits the whole tray.
///
/// This file holds the pure plate math and the sticky [PlateBar]. The editable
/// review surface lives in `plate_review_sheet.dart`.

/// Summed macros across [entries]. Null sub-macros (e.g. an AI scan unsure of
/// carbs) contribute 0 to the running total but are never themselves surfaced.
({double calories, double protein, double carbs, double fat}) plateTotals(
  List<FoodLogEntry> entries,
) {
  var calories = 0.0;
  var protein = 0.0;
  var carbs = 0.0;
  var fat = 0.0;
  for (final e in entries) {
    calories += e.calories;
    protein += e.proteinGrams;
    carbs += e.carbsGrams;
    fat += e.fatGrams;
  }
  return (calories: calories, protein: protein, carbs: carbs, fat: fat);
}

/// Proportionally rescales [e] to [newGrams], moving calories and every macro by
/// the same factor (new/old). A non-positive old serving can't define a ratio,
/// so the factor falls back to 1 (grams change, macros stay put) rather than
/// dividing by zero. Nullable sub-macros stay null.
FoodLogEntry rescaleEntryToGrams(FoodLogEntry e, double newGrams) {
  final old = e.servingGrams;
  final factor = old <= 0 ? 1.0 : newGrams / old;
  return e.copyWith(
    servingGrams: newGrams,
    calories: e.calories * factor,
    proteinGrams: e.proteinGrams * factor,
    carbsGrams: e.carbsGrams * factor,
    fatGrams: e.fatGrams * factor,
    fiberGrams: e.fiberGrams == null ? null : e.fiberGrams! * factor,
    sugarGrams: e.sugarGrams == null ? null : e.sugarGrams! * factor,
    sodiumMg: e.sodiumMg == null ? null : e.sodiumMg! * factor,
  );
}

/// Sticky, rounded, elevated bar shown only when the plate is non-empty. The
/// body (item count + muted totals) is tappable to expand the review sheet; the
/// trailing filled button commits the whole plate.
class PlateBar extends StatelessWidget {
  const PlateBar({
    super.key,
    required this.entries,
    required this.onExpand,
    required this.onCommit,
  });

  final List<FoodLogEntry> entries;
  final VoidCallback onExpand;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = entries.length;
    final totals = plateTotals(entries);
    final macros = formatMacros(
      protein: totals.protein,
      fat: totals.fat,
      carbs: totals.carbs,
      calories: totals.calories,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.cardRadius,
        boxShadow: [AppShadows.medium(context)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x1),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onExpand,
                borderRadius: AppRadius.controlRadius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x1,
                    vertical: AppSpacing.x1 - 2,
                  ),
                  // Fill the Expanded width (max) so the Flexible children
                  // receive bounded constraints and degrade gracefully (the
                  // cluster clips, the text ellipsizes) instead of forcing the
                  // row past its bounds at small widths / large text — the
                  // commit button always stays reachable.
                  child: Row(
                    children: [
                      // MacroFactor-style "plate preview": an overlapping
                      // cluster of the staged foods' glyph avatars, a glanceable
                      // picture of what's about to be logged. Reuses the same
                      // name->glyph FoodEntryAvatar the diary/plate rows render.
                      // Flexible + a right-anchored clip: when space is tight the
                      // cluster yields width first and clips its BACK (oldest)
                      // discs, keeping the front-most (most-recent) avatar.
                      Flexible(
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.centerRight,
                            widthFactor: 1,
                            child: PlatePreviewCluster(entries: entries),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1 + 4),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              count == 1 ? '1 item' : '$count items',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (macros.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                macros,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            FilledButton(
              onPressed: onCommit,
              child: Text('Log foods ($count)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A MacroFactor-style "plate preview": a horizontal, slightly-overlapping
/// cluster of the staged foods' glyph avatars shown beside the "N items" count
/// in the [PlateBar]. A glanceable picture of what's about to be logged.
///
/// Reuses the same name->glyph [FoodEntryAvatar] the diary rows / plate review
/// rows render, so the preview reads as one system with the rest of nutrition.
/// At most [maxVisible] avatars are drawn; any remainder collapses into a "+K"
/// count chip at the back of the stack (MacroFactor-style). The cluster stays in
/// stable insertion order — the most recently added food sits last (front-most,
/// trailing edge) — and animates each avatar/chip in and out via [AppMotion].
///
/// Sizing is fixed and clip-safe: the whole strip is width-bounded by the
/// avatar diameter + the per-extra overlap step, so it never grows unbounded or
/// pushes the "Log foods" button off-screen at small widths / large text.
class PlatePreviewCluster extends StatelessWidget {
  const PlatePreviewCluster({
    super.key,
    required this.entries,
    this.maxVisible = 4,
    this.radius = 14,
  });

  final List<FoodLogEntry> entries;

  /// How many real avatars to draw before collapsing the rest into a "+K" chip.
  final int maxVisible;

  /// Avatar radius. The cluster height is the ring diameter
  /// (`2 * radius + 2 * _kRingInset`), accounting for the surface ring border.
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    // How many real avatars vs. how many collapse into the trailing "+K" chip.
    // When there's an overflow we reserve one slot for the chip so the cluster
    // never grows past [maxVisible] discs total.
    final total = entries.length;
    final hasOverflow = total > maxVisible;
    final avatarCount = hasOverflow ? maxVisible - 1 : total;
    final overflow = hasOverflow ? total - avatarCount : 0;

    // Most-recently-added LAST (front-most / trailing edge): take the tail of
    // the plate so a fresh pick animates in on the right, over the older ones.
    final shown = entries.sublist(total - avatarCount);

    // The painted ring box is the bare avatar plus the [_kRingInset] padding on
    // every side, so the cluster must be laid out from the RING diameter (not the
    // bare avatar) or the front-most ring overshoots [width]/height and clips
    // inside [PlateBar]'s ClipRect.
    final ringDiameter = radius * 2 + _kRingInset * 2;
    // Negative spacing: each extra disc is nudged left so they overlap ~40%.
    final step = ringDiameter * 0.62;
    final discCount = avatarCount + (overflow > 0 ? 1 : 0);
    final width = ringDiameter + step * (discCount - 1);

    final children = <Widget>[];
    // The overflow chip sits at the BACK (left-most, drawn first so later discs
    // overlap it), mirroring how the most-recent avatar wins the front edge.
    if (overflow > 0) {
      children.add(
        Positioned(
          left: 0,
          child: _ClusterRing(
            radius: radius,
            // Keyed so a changing remainder animates rather than snapping.
            child: _OverflowChip(
              key: ValueKey('overflow-$overflow'),
              count: overflow,
              radius: radius,
            ),
          ),
        ),
      );
    }

    // Real avatars left->right, oldest->newest, so the newest lands on top.
    for (var i = 0; i < shown.length; i++) {
      final entry = shown[i];
      final slot = (overflow > 0 ? 1 : 0) + i;
      final name = entry.foodName ?? entry.food?.name ?? 'Food';
      children.add(
        Positioned(
          left: slot * step,
          child: _ClusterRing(
            radius: radius,
            child: FoodEntryAvatar(
              // Key on identity + slot so adds/removes animate the right disc.
              key: ValueKey('avatar-${entry.id}'),
              name: name,
              radius: radius,
            ),
          ),
        ),
      );
    }

    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.emphasizedCurve,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: ringDiameter,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: children,
        ),
      ),
    );
  }
}

/// The inset (per side) the [_ClusterRing] pads around each disc. The painted
/// ring box is therefore `radius * 2 + 2 * _kRingInset` across; [PlatePreviewCluster]
/// lays out from that ring diameter so the rings never paint outside the SizedBox.
const double _kRingInset = 2.0;

/// Wraps a cluster disc in a subtle surface ring so overlapping avatars read as
/// a separated stack rather than a smear. The ring is the brand surface colour,
/// matching how MacroFactor separates its overlapping plate avatars.
class _ClusterRing extends StatelessWidget {
  const _ClusterRing({required this.child, required this.radius});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.enterCurve,
      switchOutCurve: AppMotion.exitCurve,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        // Re-key on the inner child's key so an avatar/chip swap animates.
        key: child.key,
        padding: const EdgeInsets.all(_kRingInset),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }
}

/// The trailing "+K" count chip for the overflow remainder. A circular disc the
/// same diameter as an avatar, tinted from theme tokens so it tracks the palette.
class _OverflowChip extends StatelessWidget {
  const _OverflowChip({super.key, required this.count, required this.radius});

  final int count;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '+$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
