import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// Empty state widget for Progress screen when no workouts exist.
class ProgressEmptyState extends StatelessWidget {
  const ProgressEmptyState({
    super.key,
    required this.hasWorkoutsInOtherRanges,
    required this.onLogWorkout,
    this.onClearFilter,
  });

  /// True if the user has workouts but none in the selected date range.
  final bool hasWorkoutsInOtherRanges;
  final VoidCallback onLogWorkout;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (hasWorkoutsInOtherRanges) {
      return _buildNoWorkoutsInRange(theme, colorScheme);
    }

    return _buildNoWorkoutsAtAll(theme, colorScheme);
  }

  Widget _buildNoWorkoutsAtAll(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.10),
                  ),
                  child: HustlIcon(
                    asset: 'assets/icons/empty_chart.svg',
                    size: 32,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  'Your progress starts here',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'Log your first workout and watch your charts, PRs, and insights come to life.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x3),
                FilledButton.icon(
                  onPressed: onLogWorkout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x3,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.controlRadius,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Log a workout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoWorkoutsInRange(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.10),
                  ),
                  child: HustlIcon(
                    asset: 'assets/icons/ic_calendar.svg',
                    size: 32,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  'No workouts in this period',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'Widen the date range to see earlier sessions, or log a new one.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x3),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  children: [
                    if (onClearFilter != null)
                      OutlinedButton(
                        onPressed: onClearFilter,
                        child: const Text('Show all time'),
                      ),
                    FilledButton.icon(
                      onPressed: onLogWorkout,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.controlRadius,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Log workout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
