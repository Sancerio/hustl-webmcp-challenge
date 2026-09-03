import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

import 'insights_cards.dart';

/// Inline, collapsible energy-balance card shown below the diary log. Replaces
/// the swipe page that used to hide inside the header carousel. Owns its own
/// 30-day insights future, cached on `date` so date changes don't refetch
/// needlessly or flash to a loading state.
class DiaryEnergyBalanceCard extends StatelessWidget {
  const DiaryEnergyBalanceCard({
    super.key,
    required this.insights,
    required this.showExpenditure,
    required this.onToggle,
  });

  /// Resolved insights payload, or null while loading.
  final Map<String, dynamic>? insights;
  final bool showExpenditure;
  final ValueChanged<bool> onToggle;

  String _formatKcal(double value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final energy = (insights?['energyBalance'] as Map?)
        ?.cast<String, dynamic>();
    final daysRaw = (energy?['days'] as List?) ?? const [];
    final days = daysRaw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final avgs =
        (energy?['averages'] as Map?)?.cast<String, dynamic>() ?? const {};

    final avgIntake = (avgs['intakeCalories'] as num?)?.toDouble() ?? 0;
    final avgTarget = (avgs['targetCalories'] as num?)?.toDouble() ?? 0;
    final avgTdee = (avgs['tdeeKcal'] as num?)?.toDouble() ?? 0;
    final diffTarget = (avgs['diffVsTarget'] as num?)?.toDouble();
    final diffTdee = (avgs['diffVsTdee'] as num?)?.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Energy balance',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '30-day overview',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _TargetTdeeToggle(
                showExpenditure: showExpenditure,
                onToggle: onToggle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          if (days.isEmpty)
            _EmptyEnergyBalance(loading: insights == null)
          else
            _EnergyBalanceBody(
              days: days,
              showExpenditure: showExpenditure,
              avgIntake: avgIntake,
              avgTarget: avgTarget,
              avgTdee: avgTdee,
              diff: showExpenditure ? diffTdee : diffTarget,
              formatKcal: _formatKcal,
            ),
        ],
      ),
    );
  }
}

class _EmptyEnergyBalance extends StatelessWidget {
  const _EmptyEnergyBalance({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Loading is shaped like the real chart — a small set of skeleton bars and
    // a pill row — so it reads as content arriving, not a spinner.
    if (loading) {
      return const _EnergyBalanceSkeleton();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
      child: Center(
        child: Column(
          children: [
            HustlIcon(
              asset: 'assets/icons/empty_chart.svg',
              size: 36,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Log a few more days to see your balance',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A skeleton shaped like the resolved energy-balance body: two stat pills and
/// a short row of bars of varied height, so loading reads as the chart filling
/// in rather than a blank wait.
class _EnergyBalanceSkeleton extends StatelessWidget {
  const _EnergyBalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    const heights = <double>[60, 96, 44, 110, 72, 90, 52];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              AppSkeleton(width: 72, height: 28),
              SizedBox(width: AppSpacing.x1),
              AppSkeleton(width: 72, height: 28),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final h in heights) AppSkeleton(width: 8, height: h),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnergyBalanceBody extends StatelessWidget {
  const _EnergyBalanceBody({
    required this.days,
    required this.showExpenditure,
    required this.avgIntake,
    required this.avgTarget,
    required this.avgTdee,
    required this.diff,
    required this.formatKcal,
  });

  final List<Map<String, dynamic>> days;
  final bool showExpenditure;
  final double avgIntake;
  final double avgTarget;
  final double avgTdee;
  final double? diff;
  final String Function(double) formatKcal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intake = days
        .map((d) => (d['intakeCalories'] as num?)?.toDouble() ?? 0)
        .toList();
    final compare = days.map((d) {
      final target = (d['targetCalories'] as num?)?.toDouble() ?? 0;
      final tdee = (d['tdeeKcal'] as num?)?.toDouble();
      return showExpenditure ? (tdee ?? target) : target;
    }).toList();

    final maxY = [
      ...intake,
      ...compare,
    ].fold<double>(0, (a, b) => a > b ? a : b);
    final chartMaxY = maxY <= 0 ? 2000.0 : maxY * 1.2;
    final isDeficit = (diff ?? 0) < 0;
    // A surplus is amber/neutral here, never red — over-eating is not a failure.
    final diffColor = isDeficit
        ? AppColors.accentEmeraldGreen
        : AppColors.accentWarningAmber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InsightsStatPill(
              label: 'Avg intake',
              value: avgIntake.toStringAsFixed(0),
              unit: 'kcal',
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: AppSpacing.x1),
            InsightsStatPill(
              label: showExpenditure ? 'Avg TDEE' : 'Avg target',
              value: showExpenditure
                  ? avgTdee.toStringAsFixed(0)
                  : avgTarget.toStringAsFixed(0),
              unit: 'kcal',
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: diffColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.control - 4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDeficit
                        ? Icons.trending_down_rounded
                        : Icons.trending_up_rounded,
                    size: 16,
                    color: diffColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    diff?.abs().toStringAsFixed(0) ?? '—',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: diffColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        SizedBox(
          height: 140,
          child: RepaintBoundary(
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMaxY / 2,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: chartMaxY / 2,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value >= chartMaxY) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          formatKcal(value),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(intake.length, (i) {
                  final isAbove = intake[i] > compare[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: intake[i],
                        width: 5,
                        borderRadius: BorderRadius.circular(4),
                        // Flat solid fill — colour encodes data (over=amber,
                        // within=emerald), no decorative gradient.
                        color: isAbove
                            ? AppColors.accentWarningAmber
                            : AppColors.accentEmeraldGreen,
                      ),
                    ],
                  );
                }),
                barTouchData: const BarTouchData(enabled: false),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(
              color: AppColors.accentEmeraldGreen,
              label: 'Within ${showExpenditure ? "TDEE" : "target"}',
            ),
            const SizedBox(width: AppSpacing.x2),
            _LegendItem(color: AppColors.accentWarningAmber, label: 'Over'),
          ],
        ),
      ],
    );
  }
}

class _TargetTdeeToggle extends StatelessWidget {
  const _TargetTdeeToggle({
    required this.showExpenditure,
    required this.onToggle,
  });

  final bool showExpenditure;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.control - 4),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(context, 'Target', !showExpenditure, () {
            Haptics.selection();
            onToggle(false);
          }),
          _pill(context, 'TDEE', showExpenditure, () {
            Haptics.selection();
            onToggle(true);
          }),
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control - 6),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
