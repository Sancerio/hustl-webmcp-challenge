import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../domain/models/food_log_entry.dart';
import 'food_glyph.dart';

/// A single quick-pick chip in [FoodQuickStrip]: the [entry] to re-log and
/// whether it's a time-of-day suggestion (which earns a subtle sparkle accent)
/// rather than a plain recent.
class FoodQuickPick {
  const FoodQuickPick(this.entry, {this.isSuggestion = false});

  final FoodLogEntry entry;

  /// A "Suggested for now" pick — gets a small sparkle badge so the most
  /// time-relevant chips read as picks-for-you, not indistinguishable recents.
  final bool isSuggestion;
}

/// A horizontal, MacroFactor-style strip of one-tap food chips — a full-colour
/// glyph with a `+` badge and the food name beneath. Tapping a chip re-logs that
/// food immediately. Used on the add-food landing so re-logging a staple is a
/// single tap that never costs vertical space.
///
/// The strip is one combined quick-pick row: time-of-day SUGGESTIONS come first
/// (marked with a subtle sparkle), then plain recents. Pass [picks] to mix the
/// two; [FoodQuickStrip.recents] is a convenience for an all-recents strip.
class FoodQuickStrip extends StatelessWidget {
  const FoodQuickStrip({super.key, required this.picks, required this.onPick});

  /// An all-recents strip (no suggestions) — every chip is a plain recent.
  FoodQuickStrip.recents({
    super.key,
    required List<FoodLogEntry> entries,
    required this.onPick,
  }) : picks = entries.map(FoodQuickPick.new).toList(growable: false);

  final List<FoodQuickPick> picks;
  final ValueChanged<FoodLogEntry> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: picks.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.x2),
        itemBuilder: (context, i) => _QuickChip(
          entry: picks[i].entry,
          isSuggestion: picks[i].isSuggestion,
          onTap: () => onPick(picks[i].entry),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.entry,
    required this.isSuggestion,
    required this.onTap,
  });

  final FoodLogEntry entry;
  final bool isSuggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = entry.foodName ?? entry.food?.name ?? 'Food';

    return SizedBox(
      width: 68,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x1),
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colors.surfaceContainerHighest,
                  child: FoodGlyph(name: name, size: 30),
                ),
                // Suggestions earn a subtle sparkle in the top-left corner — the
                // same auto_awesome glyph the coach uses — so a "Suggested for
                // now" pick reads as a pick-for-you, not a plain recent. Tasteful
                // and small; plain recents show nothing here.
                if (isSuggestion)
                  Positioned(
                    left: -2,
                    top: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.surface, width: 2),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    child: Icon(Icons.add, size: 11, color: colors.onPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
