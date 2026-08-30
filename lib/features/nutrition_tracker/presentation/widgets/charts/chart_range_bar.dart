import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../segmented_pill_selector.dart';
import 'chart_granularity.dart';

/// The selector row shared by the trend screens: the range pills
/// (1W/1M/3M/6M/1Y/All) take the width, with the granularity dropdown ("D / W /
/// M") pinned to the right, matching the reference.
class ChartRangeBar extends StatelessWidget {
  const ChartRangeBar({
    super.key,
    required this.rangeOptions,
    required this.selectedRange,
    required this.rangeLabels,
    required this.onSelectRange,
    required this.granularities,
    required this.selectedGranularity,
    required this.onSelectGranularity,
  });

  final List<int> rangeOptions;
  final int selectedRange;
  final Map<int, String> rangeLabels;
  final ValueChanged<int> onSelectRange;

  final List<ChartGranularity> granularities;
  final ChartGranularity selectedGranularity;
  final ValueChanged<ChartGranularity> onSelectGranularity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SegmentedPillSelector<int>(
            options: rangeOptions,
            selected: selectedRange,
            onSelect: onSelectRange,
            labels: rangeLabels,
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        _GranularityDropdown(
          granularities: granularities,
          selected: selectedGranularity,
          onSelect: onSelectGranularity,
        ),
      ],
    );
  }
}

class _GranularityDropdown extends StatelessWidget {
  const _GranularityDropdown({
    required this.granularities,
    required this.selected,
    required this.onSelect,
  });

  final List<ChartGranularity> granularities;
  final ChartGranularity selected;
  final ValueChanged<ChartGranularity> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = granularities.length > 1;

    final pill = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected.shortLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: enabled ? colors.onSurfaceVariant : colors.outlineVariant,
          ),
        ],
      ),
    );

    if (!enabled) {
      return Semantics(label: 'Granularity ${selected.menuLabel}', child: pill);
    }

    return PopupMenuButton<ChartGranularity>(
      tooltip: 'Granularity',
      initialValue: selected,
      onSelected: onSelect,
      position: PopupMenuPosition.under,
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      itemBuilder: (context) => [
        for (final g in granularities)
          PopupMenuItem<ChartGranularity>(
            value: g,
            child: Text(
              g.menuLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: g == selected ? FontWeight.w600 : FontWeight.w400,
                color: g == selected ? colors.primary : colors.onSurface,
              ),
            ),
          ),
      ],
      child: pill,
    );
  }
}
