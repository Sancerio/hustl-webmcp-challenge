import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../../../core/utils/date_only.dart';
import 'energy_compare_toggle.dart';
import 'nutrition_chart_kit.dart';
import 'nutrition_chart_style.dart';

/// The Insights energy-balance chart: intake bars + a Target/TDEE reference
/// line with a real date axis + legend. The plain-language verdict now leads the
/// hub as a coach recommendation above this card, so the chart carries no second
/// verdict. The Target/TDEE toggle is HONEST — with no TDEE estimate the TDEE
/// option is disabled and the comparison stays on Target (never silently drawing
/// the reference at the target while calling it TDEE).
class InsightsEnergyBalanceCard extends StatefulWidget {
  const InsightsEnergyBalanceCard({
    super.key,
    required this.energyBalance,
    required this.compareToExpenditure,
    required this.onToggleCompare,
  });

  final Map<String, dynamic> energyBalance;
  final bool compareToExpenditure;
  final ValueChanged<bool> onToggleCompare;

  @override
  State<InsightsEnergyBalanceCard> createState() =>
      _InsightsEnergyBalanceCardState();
}

class _InsightsEnergyBalanceCardState extends State<InsightsEnergyBalanceCard> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE, MMM d');

    final days = ((widget.energyBalance['days'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (days.isEmpty) return const SizedBox.shrink();

    final avgs =
        (widget.energyBalance['averages'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final avgIntake = (avgs['intakeCalories'] as num?)?.toDouble() ?? 0;
    final avgTarget = (avgs['targetCalories'] as num?)?.toDouble() ?? 0;
    final avgTdee = (avgs['tdeeKcal'] as num?)?.toDouble();
    final diffTarget = (avgs['diffVsTarget'] as num?)?.toDouble();
    final diffTdee = (avgs['diffVsTdee'] as num?)?.toDouble();

    // HONEST compare: with no TDEE estimate the TDEE mode is unavailable, so we
    // always compare to Target regardless of the stored flag.
    final hasTdee = avgTdee != null;
    final compareTdee = hasTdee && widget.compareToExpenditure;
    final compareLabel = compareTdee ? 'TDEE' : 'Target';

    final intakeColor = AppColors.accentElectricBlue;
    final referenceColor = AppColors.accentWarningAmber;

    final dates = <DateTime>[];
    final intakeBars = <double>[];
    final compareSpots = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      final intake = (days[i]['intakeCalories'] as num?)?.toDouble() ?? 0;
      final target = (days[i]['targetCalories'] as num?)?.toDouble() ?? 0;
      final tdee = (days[i]['tdeeKcal'] as num?)?.toDouble();
      final compare = compareTdee ? (tdee ?? target) : target;
      dates.add(parseLocalDateOnly(days[i]['date'] as String));
      intakeBars.add(intake);
      compareSpots.add(FlSpot(i.toDouble(), compare));
    }

    final maxY = [
      avgIntake,
      avgTarget,
      if (hasTdee) avgTdee,
      ...intakeBars,
      ...compareSpots.map((s) => s.y),
    ].reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxY <= 0 ? 1.0 : maxY * 1.12;
    final maxX = (days.length - 1).toDouble();

    final compareAvg = compareTdee ? avgTdee : avgTarget;
    final diff = compareTdee ? diffTdee : diffTarget;
    final diffText = diff == null
        ? '—'
        : '${diff >= 0 ? '+' : '−'}${diff.abs().toStringAsFixed(0)}';
    final diffColor = diff == null
        ? theme.colorScheme.onSurfaceVariant
        : (diff <= 0
              ? AppColors.accentEmeraldGreen
              : AppColors.accentWarningAmber);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x1,
        AppSpacing.x2,
        AppSpacing.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Energy balance',
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            trailing: EnergyCompareToggle(
              compareToExpenditure: widget.compareToExpenditure,
              hasTdee: hasTdee,
              onToggle: widget.onToggleCompare,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Semantics(
            label:
                'Energy balance chart. Avg intake ${avgIntake.round()} kcal '
                'vs $compareLabel ${compareAvg.round()} kcal.',
            excludeSemantics: true,
            child: RepaintBoundary(
              child: SizedBox(
                height: 214,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: BarChart(
                        BarChartData(
                          minY: 0,
                          maxY: chartMaxY,
                          alignment: BarChartAlignment.spaceAround,
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (v) =>
                                NutritionChartStyle.gridLine(theme),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: sparseDateSideTitles(
                                dates: dates,
                                theme: theme,
                              ),
                            ),
                          ),
                          barTouchData: BarTouchData(
                            handleBuiltInTouches: true,
                            touchCallback: (event, response) {
                              final group = response?.spot?.touchedBarGroup;
                              if (group == null ||
                                  !event.isInterestedForInteractions) {
                                return;
                              }
                              setState(() => _selectedIndex = group.x);
                            },
                            touchTooltipData: BarTouchTooltipData(
                              tooltipBorderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipColor: (_) =>
                                  theme.colorScheme.surfaceContainerHigh,
                              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                                '${fmt.format(dates[group.x])}\n'
                                'Intake: ${intakeBars[group.x].round()} kcal\n'
                                '$compareLabel: ${compareSpots[group.x].y.round()} kcal',
                                theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.onSurface,
                                    ) ??
                                    TextStyle(
                                      color: theme.colorScheme.onSurface,
                                    ),
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < intakeBars.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: intakeBars[i],
                                    color:
                                        (_selectedIndex == null ||
                                            _selectedIndex == i)
                                        ? intakeColor
                                        : intakeColor.withValues(alpha: 0.45),
                                    width: 6,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      bottom: 22,
                      child: IgnorePointer(
                        child: LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: maxX,
                            minY: 0,
                            maxY: chartMaxY,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            lineTouchData: const LineTouchData(enabled: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: compareSpots,
                                isCurved: false,
                                color: referenceColor,
                                barWidth: 1.5,
                                dashArray: const [3, 3],
                                dotData: const FlDotData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Row(
            children: [
              ChartLegendItem(color: intakeColor, label: 'Intake'),
              const SizedBox(width: AppSpacing.x2),
              ChartLegendItem(
                color: referenceColor,
                label: compareLabel,
                line: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          _EnergyStatRow(
            label: 'Avg intake',
            value: '${avgIntake.round()} kcal',
            valueColor: intakeColor,
          ),
          const Divider(),
          _EnergyStatRow(
            label: 'Avg $compareLabel',
            value: '${compareAvg.round()} kcal',
            valueColor: referenceColor,
          ),
          const Divider(),
          _EnergyStatRow(
            label: 'Difference',
            value: '$diffText kcal',
            valueColor: diffColor,
          ),
          if (hasTdee) ...[
            const Divider(),
            InkWell(
              onTap: () => context.push('/nutrition/expenditure'),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'View expenditure trend',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EnergyStatRow extends StatelessWidget {
  const _EnergyStatRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}
