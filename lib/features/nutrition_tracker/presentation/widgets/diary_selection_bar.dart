import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

/// Sticky bottom action bar shown while the diary is in selection mode
/// (MacroFactor-style retroactive bulk actions). A "N selected · NNN Cal"
/// summary line sits up top with an X to dismiss; the selection actions —
/// "Copy to…" and "Create recipe" — share an equal-width row beneath it so
/// both stay reachable and the bar never overflows at narrow widths. The whole
/// bar floats above the content on the app surface ladder and respects the
/// bottom safe area.
class DiarySelectionBar extends StatelessWidget {
  const DiarySelectionBar({
    super.key,
    required this.selectedCount,
    required this.selectedCalories,
    required this.onCreateRecipe,
    required this.onCopyTo,
    required this.onCancel,
  });

  final int selectedCount;
  final double selectedCalories;
  final VoidCallback onCreateRecipe;
  final VoidCallback onCopyTo;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final n = selectedCount;
    final hasSelection = n > 0;

    return Material(
      color: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      shadowColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.cardRadius,
          boxShadow: [AppShadows.medium(context)],
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x1,
          AppSpacing.x1 + 4,
          AppSpacing.x2,
          AppSpacing.x2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary row: dismiss + "N selected · NNN Cal".
            Row(
              children: [
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel selection',
                ),
                Expanded(
                  child: Text(
                    hasSelection
                        ? '$n selected · ${selectedCalories.toStringAsFixed(0)} Cal'
                        : 'Select foods to copy or save as a recipe',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            // Actions row: equal-width buttons so both fit at 360px.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasSelection
                          ? () {
                              Haptics.selection();
                              onCopyTo();
                            }
                          : null,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: const Text(
                        'Copy to…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: hasSelection
                          ? () {
                              Haptics.selection();
                              onCreateRecipe();
                            }
                          : null,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text(
                        'Create recipe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
