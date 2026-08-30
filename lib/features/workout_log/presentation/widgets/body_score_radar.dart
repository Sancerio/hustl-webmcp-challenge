import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/number_format_util.dart';
import '../../domain/models/muscle_group.dart';

class BodyScoreRadar extends StatefulWidget {
  const BodyScoreRadar({
    super.key,
    required this.scoresByMuscleGroup,
    required this.weeklyTargetsByMuscleGroup,
    this.weeklyTotals,
    this.maxPercent = 150,
    this.targetPercent = 100,
    this.maxTicks = 4,
  });

  /// Muscle-group scores expressed as percentages of the weekly goal.
  final Map<MuscleGroup, double> scoresByMuscleGroup;

  /// Weekly goals (in hard sets) for each muscle group.
  final Map<MuscleGroup, double> weeklyTargetsByMuscleGroup;

  /// Weekly-equivalent hard sets accumulated per muscle group for the current view.
  final Map<MuscleGroup, double>? weeklyTotals;

  /// Maximum percentage rendered on the radar chart.
  final double maxPercent;

  /// Target percentage used to render a reference ring (typically 100%).
  final double targetPercent;

  /// Number of tick rings rendered for the chart grid.
  final int maxTicks;

  @override
  State<BodyScoreRadar> createState() => _BodyScoreRadarState();
}

class _BodyScoreRadarState extends State<BodyScoreRadar> {
  _RadarTooltipData? _tooltip;

  static const List<DisplayRegion> _regions = [
    DisplayRegion.chest,
    DisplayRegion.back,
    DisplayRegion.shoulders,
    DisplayRegion.arms,
    DisplayRegion.core,
    DisplayRegion.legs,
  ];

  Map<DisplayRegion, _RegionAggregate> get _aggregates {
    final Map<DisplayRegion, _RegionAggregate> aggregates = {
      for (final region in DisplayRegion.values)
        region: _RegionAggregate.zero(),
    };

    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      final double target = widget.weeklyTargetsByMuscleGroup[group] ?? 0.0;
      if (target <= 0) continue;
      final double total =
          widget.weeklyTotals?[group] ??
          _deriveTotal(
            target: target,
            percent: widget.scoresByMuscleGroup[group] ?? 0.0,
          );
      final next = aggregates[region] ?? _RegionAggregate.zero();
      aggregates[region] = next.copyWith(
        total: next.total + total,
        target: next.target + target,
        byGroupTotal: {...next.byGroupTotal, group: total},
        byGroupTarget: {...next.byGroupTarget, group: target},
      );
    }

    return aggregates;
  }

  static double _deriveTotal({
    required double target,
    required double percent,
  }) {
    if (target <= 0) return 0.0;
    return (percent / 100.0) * target;
  }

  void _handleTouch(FlTouchEvent event, RadarTouchResponse? response) {
    if (!event.isInterestedForInteractions || response?.touchedSpot == null) {
      if (_tooltip != null) {
        setState(() => _tooltip = null);
      }
      return;
    }
    final spot = response!.touchedSpot!;
    // Dataset index 0 is the target ring, index 1 is the actual data.
    if (spot.touchedDataSetIndex != 1) {
      if (_tooltip != null) {
        setState(() => _tooltip = null);
      }
      return;
    }
    final index = spot.touchedRadarEntryIndex;
    if (index < 0 || index >= _regions.length) {
      if (_tooltip != null) {
        setState(() => _tooltip = null);
      }
      return;
    }
    final region = _regions[index];
    final aggregates = _aggregates;
    final regionAggregate = aggregates[region] ?? _RegionAggregate.zero();

    final double actual = regionAggregate.total;
    final double target = regionAggregate.target;
    final double percent = target > 0 ? (actual / target) * 100.0 : 0.0;

    final String actualLabel = NumberFormatUtil.formatDouble(
      actual.clamp(0.0, double.maxFinite),
      decimalDigits: (actual - actual.round()).abs() < 0.05 ? 0 : 1,
    );
    final String targetLabel = NumberFormatUtil.formatDouble(
      target.clamp(0.0, double.maxFinite),
      decimalDigits: (target - target.round()).abs() < 0.05 ? 0 : 1,
    );
    final String percentLabel = NumberFormatUtil.formatDouble(
      percent,
      decimalDigits: 0,
    );

    final buffer = StringBuffer()
      ..write(
        '${region.label} $actualLabel / $targetLabel hard sets ($percentLabel%)',
      );

    final groups = MuscleGroup.values
        .where((group) => group.displayRegion == region)
        .where(
          (group) =>
              group != MuscleGroup.other && group != MuscleGroup.fullBody,
        )
        .where(
          (group) => (widget.weeklyTargetsByMuscleGroup[group] ?? 0.0) > 0.0,
        )
        .toList(growable: false);
    if (groups.isNotEmpty) {
      for (final group in groups) {
        final groupActual = regionAggregate.byGroupTotal[group] ?? 0.0;
        final groupTarget = regionAggregate.byGroupTarget[group] ?? 0.0;
        final groupPercent = groupTarget > 0
            ? (groupActual / groupTarget) * 100.0
            : 0.0;
        final groupActualLabel = NumberFormatUtil.formatDouble(
          groupActual.clamp(0.0, double.maxFinite),
          decimalDigits: (groupActual - groupActual.round()).abs() < 0.05
              ? 0
              : 1,
        );
        final groupTargetLabel = NumberFormatUtil.formatDouble(
          groupTarget.clamp(0.0, double.maxFinite),
          decimalDigits: (groupTarget - groupTarget.round()).abs() < 0.05
              ? 0
              : 1,
        );
        final groupPercentLabel = NumberFormatUtil.formatDouble(
          groupPercent,
          decimalDigits: 0,
        );
        buffer
          ..write('\n• ${group.label}: $groupActualLabel / $groupTargetLabel')
          ..write(' ($groupPercentLabel%)');
      }
    }

    final text = buffer.toString();
    setState(() {
      _tooltip = _RadarTooltipData(text: text, position: spot.offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggregates = _aggregates;

    final orderedValues = [
      for (final region in _regions)
        (((aggregates[region]?.percent ?? 0.0).clamp(0.0, widget.maxPercent) /
                    widget.maxPercent)
                .clamp(0.0, 1.0))
            .toDouble(),
    ];

    final targetRatio = (widget.targetPercent / widget.maxPercent).clamp(
      0.0,
      1.0,
    );

    final semanticsDescription = _regions
        .map(
          (region) =>
              '${region.label}: ${NumberFormatUtil.formatDouble(aggregates[region]?.percent ?? 0, decimalDigits: 0)}% of weekly goal',
        )
        .join(', ');

    final chart = ExcludeSemantics(
      child: RadarChart(
        RadarChartData(
          radarTouchData: RadarTouchData(
            touchCallback: _handleTouch,
            touchSpotThreshold: 28,
          ),
          radarBackgroundColor: Colors.transparent,
          radarBorderData: BorderSide.none,
          radarShape: RadarShape.polygon,
          // Wave G §12.4: thin hairline grid — the instrument is quiet.
          gridBorderData: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          tickBorderData: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
          tickCount: widget.maxTicks,
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          titlePositionPercentageOffset: 0.1,
          titleTextStyle: theme.textTheme.labelSmall,
          getTitle: (index, angle) {
            final region = _regions[index];
            return RadarChartTitle(text: region.label, angle: angle);
          },
          dataSets: [
            // Target ring: dashed-thin reference (the goal-met reference).
            RadarDataSet(
              fillColor: Colors.transparent,
              borderColor: theme.colorScheme.outlineVariant.withValues(
                alpha: 0.6,
              ),
              borderWidth: 1,
              entryRadius: 0,
              dataEntries: [
                for (int i = 0; i < orderedValues.length; i++)
                  RadarEntry(value: targetRatio),
              ],
            ),
            // Data polygon: thin blue line over a faint flat fill (≤10%).
            RadarDataSet(
              borderColor: theme.colorScheme.primary,
              fillColor: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderWidth: 1.5,
              entryRadius: 0,
              dataEntries: [
                for (final value in orderedValues) RadarEntry(value: value),
              ],
            ),
          ],
        ),
      ),
    );

    return Semantics(
      label: 'Training balance distribution',
      value: semanticsDescription,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              chart,
              if (_tooltip != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _RadarTooltip(tooltip: _tooltip!),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RadarTooltipData {
  const _RadarTooltipData({required this.text, required this.position});

  final String text;
  final Offset position;
}

class _RegionAggregate {
  const _RegionAggregate({
    required this.total,
    required this.target,
    required this.byGroupTotal,
    required this.byGroupTarget,
  });

  final double total;
  final double target;
  final Map<MuscleGroup, double> byGroupTotal;
  final Map<MuscleGroup, double> byGroupTarget;

  double get percent => target > 0 ? (total / target) * 100.0 : 0.0;

  static _RegionAggregate zero() => const _RegionAggregate(
    total: 0.0,
    target: 0.0,
    byGroupTotal: {},
    byGroupTarget: {},
  );

  _RegionAggregate copyWith({
    double? total,
    double? target,
    Map<MuscleGroup, double>? byGroupTotal,
    Map<MuscleGroup, double>? byGroupTarget,
  }) {
    return _RegionAggregate(
      total: total ?? this.total,
      target: target ?? this.target,
      byGroupTotal: byGroupTotal ?? this.byGroupTotal,
      byGroupTarget: byGroupTarget ?? this.byGroupTarget,
    );
  }
}

class _RadarTooltip extends StatelessWidget {
  const _RadarTooltip({required this.tooltip});

  final _RadarTooltipData tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final dx = (tooltip.position.dx / constraints.maxWidth).clamp(0.0, 1.0);
        final dy = (tooltip.position.dy / constraints.maxHeight).clamp(
          0.0,
          1.0,
        );
        final alignment = Alignment(dx * 2 - 1, dy * 2 - 1);
        return Align(
          alignment: alignment,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -1.2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh.withValues(
                  alpha: 0.95,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  tooltip.text,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
