import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';

import '../../../domain/services/body_score_service.dart';

/// Result returned from [showHistoryFilterSheet].
class HistoryFilterResult {
  const HistoryFilterResult({
    required this.muscleGroups,
    required this.rangeDays,
  });

  final Set<MuscleGroup> muscleGroups;
  final int? rangeDays;
}

const List<({int? days, String label})> _rangeOptions = [
  (days: null, label: 'All time'),
  (days: 7, label: '7 days'),
  (days: 14, label: '14 days'),
  (days: 28, label: '28 days'),
  (days: 90, label: '90 days'),
  (days: 180, label: '180 days'),
  (days: 365, label: '365 days'),
];

Iterable<MuscleGroup> _groupsForRegion(DisplayRegion region) {
  return MuscleGroup.values.where((group) {
    if (region == DisplayRegion.other) {
      return group.displayRegion == region;
    }
    if (group == MuscleGroup.other || group == MuscleGroup.fullBody) {
      return false;
    }
    return group.displayRegion == region;
  });
}

/// Filter sheet for the history list. Body regions collapse into a single
/// horizontal row of chips (no nested ExpansionTile + checkbox depth), and the
/// date range is a chip row too.
Future<HistoryFilterResult?> showHistoryFilterSheet(
  BuildContext context, {
  required Set<MuscleGroup> selectedGroups,
  required int? selectedRangeDays,
}) {
  return showModalBottomSheet<HistoryFilterResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) => _HistoryFilterSheet(
      initialGroups: selectedGroups,
      initialRangeDays: selectedRangeDays,
    ),
  );
}

class _HistoryFilterSheet extends StatefulWidget {
  const _HistoryFilterSheet({
    required this.initialGroups,
    required this.initialRangeDays,
  });

  final Set<MuscleGroup> initialGroups;
  final int? initialRangeDays;

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  late Set<MuscleGroup> _groups;
  late int? _rangeDays;

  static final List<DisplayRegion> _regions = DisplayRegion.values
      .where((region) => region != DisplayRegion.other)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _groups = {...widget.initialGroups};
    _rangeDays = widget.initialRangeDays;
  }

  bool _isRegionSelected(DisplayRegion region) {
    final groups = _groupsForRegion(region).toSet();
    return groups.isNotEmpty && groups.every(_groups.contains);
  }

  void _toggleRegion(DisplayRegion region) {
    Haptics.selection();
    final groups = _groupsForRegion(region).toSet();
    setState(() {
      if (_isRegionSelected(region)) {
        _groups.removeAll(groups);
      } else {
        _groups.addAll(groups);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.x2,
        right: AppSpacing.x2,
        top: AppSpacing.x1 + 4,
        bottom: AppSpacing.x2 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filters',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: (_groups.isEmpty && _rangeDays == null)
                    ? null
                    : () => setState(() {
                        _groups.clear();
                        _rangeDays = null;
                      }),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          _Label(text: 'Body region', theme: theme),
          const SizedBox(height: AppSpacing.x1),
          Wrap(
            spacing: AppSpacing.x1,
            runSpacing: AppSpacing.x1,
            children: [
              for (final region in _regions)
                AppChip(
                  variant: AppChipVariant.filter,
                  label: region.label,
                  selected: _isRegionSelected(region),
                  onTap: () => _toggleRegion(region),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          _Label(text: 'Date range', theme: theme),
          const SizedBox(height: AppSpacing.x1),
          Wrap(
            spacing: AppSpacing.x1,
            runSpacing: AppSpacing.x1,
            children: [
              for (final option in _rangeOptions)
                AppChip(
                  variant: AppChipVariant.filter,
                  label: option.label,
                  selected: _rangeDays == option.days,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _rangeDays = option.days);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          FilledButton(
            onPressed: () => context.pop(
              HistoryFilterResult(
                muscleGroups: {..._groups},
                rangeDays: _rangeDays,
              ),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
