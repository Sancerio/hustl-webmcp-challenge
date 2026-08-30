import 'package:flutter/material.dart';

/// §12.1: a quiet MacroFactor-style segmented selector. Flat raised track, a
/// borderless sliding indicator (no shadow), monochrome onSurface w600 for the
/// active label. Reusable across insights, weight trend, and other screens.
class SegmentedPillSelector<T> extends StatelessWidget {
  const SegmentedPillSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.labels,
  });

  /// List of option values.
  final List<T> options;

  /// Currently selected value.
  final T selected;

  /// Callback when selection changes.
  final ValueChanged<T> onSelect;

  /// Optional custom labels. If null, uses toString() on options.
  final Map<T, String>? labels;

  String _label(T option) => labels?[option] ?? option.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectedIndex = options
        .indexOf(selected)
        .clamp(0, options.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / options.length;
        return Container(
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // Borderless sliding indicator (no shadow).
              AnimatedPositioned(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: itemWidth * selectedIndex + 3,
                top: 3,
                bottom: 3,
                width: itemWidth - 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              // Option buttons
              Row(
                children: [
                  for (final option in options)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(option),
                        child: Center(
                          child: Text(
                            _label(option),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: option == selected
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
