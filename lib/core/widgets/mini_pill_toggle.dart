import 'package:flutter/material.dart';

import 'package:hustl_app/core/services/haptics.dart';

/// A small, low-emphasis segmented toggle for a SECONDARY chart dimension that
/// lives in a card/section header (e.g. a metric or series choice) — distinct
/// from the full-width [SegmentedPillSelector] used for the primary dimension.
///
/// Keeping the secondary dimension as a compact header toggle (rather than a
/// second full-width pill row) avoids the "double-tab" stack where two
/// tab-like bars compete for primacy.
class MiniPillToggle extends StatelessWidget {
  const MiniPillToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () {
                Haptics.selection();
                onSelect(i);
              },
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 30,
                decoration: BoxDecoration(
                  color: i == selectedIndex
                      ? theme.colorScheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    options[i],
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: i == selectedIndex
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
