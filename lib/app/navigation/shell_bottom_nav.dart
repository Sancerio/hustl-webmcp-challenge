import 'package:flutter/material.dart';

import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

import '../theme/app_spacing.dart';

/// A single shell destination.
class ShellDestination {
  const ShellDestination({required this.asset, required this.label});

  /// Path to the custom line-icon SVG in the `assets/icons/` family. The same
  /// glyph serves selected and unselected states — only the tint color changes.
  final String asset;
  final String label;
}

/// The five top-level destinations, in shell-branch order.
const List<ShellDestination> kShellDestinations = [
  ShellDestination(asset: 'assets/icons/nav_train.svg', label: 'Train'),
  ShellDestination(asset: 'assets/icons/nav_nutrition.svg', label: 'Nutrition'),
  ShellDestination(asset: 'assets/icons/nav_history.svg', label: 'History'),
  ShellDestination(asset: 'assets/icons/nav_progress.svg', label: 'Progress'),
  ShellDestination(asset: 'assets/icons/nav_library.svg', label: 'Library'),
];

/// Flat bottom navigation bar (Wave I). The bar IS the canvas: scaffold
/// background fill, a 1px `outlineVariant` hairline top divider, and custom
/// line-icon SVG glyphs with 11px labels. The active tab is marked by the brand
/// primary tint + w600 weight; inactive tabs sit at a muted variant — no pill,
/// no indicator block.
///
/// Instantiated once by the shell; all spacing lives on [AppSpacing] tokens.
class ShellBottomNav extends StatelessWidget {
  const ShellBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.itemKeys,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Map<int, GlobalKey>? itemKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Brand emphasis: the active tab is the brand primary; inactive is a muted
    // variant.
    final Color selectedColor = colors.primary;
    final Color unselectedColor = colors.onSurfaceVariant;

    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final int slotCount = kShellDestinations.length;
    final int effectiveIndex = currentIndex.clamp(0, slotCount - 1);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: colors.outlineVariant, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < slotCount; i++)
                _NavItem(
                  destination: kShellDestinations[i],
                  selected: i == effectiveIndex,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  itemKey: itemKeys?[i],
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
    this.itemKey,
  });

  final ShellDestination destination;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;
  final GlobalKey? itemKey;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    // Fold the tab into one semantics node: a selectable button announcing
    // its label and selected state. The inner tree's semantics are excluded
    // to avoid a duplicate node and a redundant tap action.
    final Widget tab = Semantics(
      label: destination.label,
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HustlIcon(asset: destination.asset, size: 24, color: color),
              const SizedBox(height: AppSpacing.x1 / 4),
              Text(
                destination.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );

    return Expanded(
      child: KeyedSubtree(key: itemKey, child: tab),
    );
  }
}
