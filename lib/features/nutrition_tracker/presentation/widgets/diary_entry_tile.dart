import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:intl/intl.dart';

import '../../domain/models/food_log_entry.dart';
import '../utils/macro_format.dart';
import 'food_entry_avatar.dart';

/// A flat logged-food row: a leading food-type glyph ([FoodEntryAvatar],
/// MacroFactor-style, derived from the food name) with a small source badge,
/// the food name at 15/w500 (max two lines) with a 12px muted serving+macros
/// line beneath, and the right-aligned kcal value with the muted log time below
/// it. Tap to edit; swipe left to delete; long-press to enter selection.
///
/// In [selectionMode] the row swaps the leading glyph for a checkbox, drops the
/// swipe-to-delete gesture, and routes taps to [onSelectToggle] instead of
/// [onTap] — an additive overlay on the same row, no layout reflow.
class DiaryEntryTile extends StatelessWidget {
  const DiaryEntryTile({
    super.key,
    required this.entry,
    required this.onDelete,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  final FoodLogEntry entry;
  final ValueChanged<String> onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  String _secondLine() {
    final portion = entry.portionLabel?.trim();
    final serving = (portion != null && portion.isNotEmpty)
        ? portion
        : entry.servingGrams > 0
        ? '${entry.servingGrams.toStringAsFixed(0)} g'
        : null;
    final macros = formatMacros(
      protein: entry.proteinGrams,
      fat: entry.fatGrams,
      carbs: entry.carbsGrams,
    );
    return serving == null ? macros : '$serving · $macros';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = entry.foodName ?? entry.food?.name ?? 'Food';
    final minuteStr = DateFormat('h:mm').format(entry.loggedAt.toLocal());

    final row = InkWell(
      onTap: selectionMode ? onSelectToggle : onTap,
      onLongPress: selectionMode ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onSelectToggle?.call(),
              ),
              const SizedBox(width: AppSpacing.x1),
            ],
            FoodEntryAvatar(name: name, source: entry.source),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _secondLine(),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    text: entry.calories.toStringAsFixed(0),
                    style: theme.textTheme.labelLarge,
                    children: [
                      TextSpan(text: ' Cal', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(minuteStr, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );

    // Selection mode disables swipe-to-delete so a selecting drag can't
    // accidentally remove a row; tap toggles selection instead.
    if (selectionMode) return row;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      movementDuration: const Duration(milliseconds: 120),
      confirmDismiss: (dir) async => dir == DismissDirection.endToStart,
      onDismissed: (_) {
        Haptics.confirm();
        onDelete(entry.id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.x2),
        color: theme.colorScheme.error.withValues(alpha: 0.15),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      child: row,
    );
  }
}
