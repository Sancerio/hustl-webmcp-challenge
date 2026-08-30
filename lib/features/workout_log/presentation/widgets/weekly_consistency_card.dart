import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:intl/intl.dart';

String weeklyConsistencyWeekKey(DateTime date) {
  final week = _isoWeekNumber(date);
  return '${date.year}-W${week.toString().padLeft(2, '0')}';
}

DateTime weeklyConsistencyWeekStartFromKey(String key) {
  final parts = key.split('-W');
  if (parts.length != 2) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  final year = int.tryParse(parts[0]);
  final week = int.tryParse(parts[1]);
  if (year == null || week == null) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return _startOfIsoWeek(year, week);
}

Map<String, int> aggregateWorkoutsPerIsoWeek(Iterable<DateTime> workoutDates) {
  final countsByWeek = <String, int>{};
  for (final date in workoutDates) {
    final key = weeklyConsistencyWeekKey(date);
    countsByWeek.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  return countsByWeek;
}

List<MapEntry<String, int>> buildRecentWeeklyConsistencySeries({
  required int weekCount,
  required DateTime now,
  required Map<String, int> countsByWeek,
}) {
  if (weekCount <= 0) {
    return const <MapEntry<String, int>>[];
  }

  final anchorWeekStart = weeklyConsistencyWeekStartFromKey(
    weeklyConsistencyWeekKey(now),
  );
  return List<MapEntry<String, int>>.generate(weekCount, (index) {
    final weeksBack = weekCount - 1 - index;
    final weekStart = anchorWeekStart.subtract(Duration(days: 7 * weeksBack));
    final key = weeklyConsistencyWeekKey(weekStart);
    return MapEntry<String, int>(key, countsByWeek[key] ?? 0);
  });
}

class WeeklyConsistencyCard extends StatelessWidget {
  const WeeklyConsistencyCard({
    required this.countsByWeek,
    required this.weeklyGoal,
    required this.now,
    required this.onGoalChanged,
    super.key,
  });

  final Map<String, int> countsByWeek;
  final int weeklyGoal;
  final DateTime now;
  final Future<void> Function(int goal) onGoalChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final last8 = buildRecentWeeklyConsistencySeries(
      weekCount: 8,
      now: now,
      countsByWeek: countsByWeek,
    );
    final maxCount =
        (last8
                .map((entry) => entry.value)
                .fold<int>(0, (p, c) => c > p ? c : p))
            .clamp(3, 10);

    final goalHits = last8.where((entry) => entry.value >= weeklyGoal).length;
    // No sessions land in the last 8 weeks — an empty 8-bar grid reads dead, so
    // we add a kind prompt beneath it inviting the next session.
    final hasRecentActivity = last8.any((entry) => entry.value > 0);
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < last8.length; i++) {
      final entry = last8[i];
      final meetsGoal = entry.value >= weeklyGoal;
      // Wave I (data-as-hero): goal-met weeks fill in solid primary blue (the
      // data-viz highlight); missed weeks stay a quiet faint-blue track — never
      // stark white, never red, never crossed out.
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entry.value.toDouble(),
              // Slim bars, square-ish 2px radius (not pills).
              width: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(2),
              ),
              color: meetsGoal
                  ? colorScheme.primary
                  : colorScheme.primary.withValues(alpha: 0.28),
            ),
          ],
        ),
      );
    }

    // Sentence-case section voice (shared SectionHeader) + edge-to-edge chart.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Weekly consistency',
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
          trailing: _GoalChip(
            weeklyGoal: weeklyGoal,
            onPressed: () async {
              final goal = await _showGoalDialog(context, weeklyGoal);
              if (goal == null || goal == weeklyGoal) {
                return;
              }
              await onGoalChanged(goal);
            },
          ),
        ),
        RepaintBoundary(
          child: Semantics(
            label:
                'Weekly workout counts over the last 8 weeks. '
                'Hit goal $goalHits of 8 weeks.',
            child: SizedBox(
              height: 140,
              child: BarChart(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    // §12.4: at most a few hairline gridlines.
                    horizontalInterval: ((maxCount + 1) / 2).clamp(1, 10),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        // §12.4: 11px axis labels (labelSmall).
                        getTitlesWidget: (value, meta) => Text(
                          meta.formattedValue,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= last8.length) {
                            return const SizedBox.shrink();
                          }
                          final weekStart = weeklyConsistencyWeekStartFromKey(
                            last8[index].key,
                          );
                          return Text(
                            DateFormat('M/d').format(weekStart),
                            style: theme.textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: groups,
                  minY: 0,
                  maxY: (maxCount + 1).toDouble(),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: weeklyGoal.toDouble(),
                        // §12.4: target line is a dotted 1px hairline — quiet,
                        // not color-shouting (the met signal is the bar flip).
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                        strokeWidth: 1,
                        dashArray: [2, 3],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (_) => 'Goal',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!hasRecentActivity) ...[
          const SizedBox(height: AppSpacing.x1),
          Row(
            children: [
              Icon(Icons.bolt_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Log a workout this week to start your first streak.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<int?> _showGoalDialog(BuildContext context, int currentGoal) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        int tempGoal = currentGoal;
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Set weekly goal'),
          content: StatefulBuilder(
            builder: (ctx, setStateDialog) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => setStateDialog(
                      () => tempGoal = (tempGoal - 1).clamp(1, 14),
                    ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$tempGoal/wk', style: theme.textTheme.titleLarge),
                  IconButton(
                    onPressed: () => setStateDialog(
                      () => tempGoal = (tempGoal + 1).clamp(1, 14),
                    ),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => ctx.pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => ctx.pop(tempGoal),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

int _isoWeekNumber(DateTime date) {
  final jan4 = DateTime(date.year, 1, 4);
  final start = jan4.subtract(Duration(days: jan4.weekday - DateTime.monday));
  return ((date.difference(start).inDays) / 7).floor() + 1;
}

DateTime _startOfIsoWeek(int year, int week) {
  final jan4 = DateTime(year, 1, 4);
  final startOfWeek1 = jan4.subtract(
    Duration(days: jan4.weekday - DateTime.monday),
  );
  return startOfWeek1.add(Duration(days: (week - 1) * 7));
}

/// The weekly-goal affordance. Styled as a tonal, outlined chip with an
/// edit-pencil so it reads unmistakably as "tap to change your goal" — a plain
/// colored TextButton didn't signal that it was editable, and this is the only
/// place to set the goal after onboarding.
class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.weeklyGoal, required this.onPressed});

  final int weeklyGoal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Weekly goal, $weeklyGoal per week. Edit.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.primary.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Goal: $weeklyGoal/wk',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 14, color: colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
