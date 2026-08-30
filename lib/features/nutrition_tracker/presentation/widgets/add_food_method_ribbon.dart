import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';

/// A compact, horizontally-scrollable row of add-food method chips shown between
/// the search body and the plate bar. Search is the always-on surface below, so
/// it is NOT a chip here; these are the other ways in — Scan, Quick add,
/// Describe, Recipes, Copy day — surfaced as one discoverable, equal-weight row
/// so scanning is no longer buried behind a camera glyph.
///
/// Each chip just fires the matching callback; every flow already stages onto
/// the plate via the sheet's `_addEntries`.
class AddFoodMethodRibbon extends StatelessWidget {
  const AddFoodMethodRibbon({
    super.key,
    required this.onScan,
    required this.onQuickAdd,
    required this.onDescribe,
    required this.onRecipes,
    required this.onCopyDay,
  });

  /// Opens the meal/barcode/label scan menu in one tap.
  final VoidCallback onScan;

  /// Opens the manual quick-add dialog.
  final VoidCallback onQuickAdd;

  /// Opens the NL "describe a meal" flow.
  final VoidCallback onDescribe;

  /// Opens the recipes browser.
  final VoidCallback onRecipes;

  /// Opens the copy-from-a-day sheet.
  final VoidCallback onCopyDay;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      AppChip(
        label: 'Scan',
        variant: AppChipVariant.filter,
        icon: Icons.photo_camera_outlined,
        onTap: onScan,
      ),
      AppChip(
        label: 'Quick add',
        variant: AppChipVariant.filter,
        icon: Icons.edit_outlined,
        onTap: onQuickAdd,
      ),
      AppChip(
        label: 'Describe',
        variant: AppChipVariant.filter,
        icon: Icons.auto_awesome_outlined,
        onTap: onDescribe,
      ),
      AppChip(
        label: 'Recipes',
        variant: AppChipVariant.filter,
        icon: Icons.menu_book_outlined,
        onTap: onRecipes,
      ),
      AppChip(
        label: 'Copy day',
        variant: AppChipVariant.filter,
        icon: Icons.copy_all_outlined,
        onTap: onCopyDay,
      ),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.x1),
        itemBuilder: (_, index) => Center(child: chips[index]),
      ),
    );
  }
}
