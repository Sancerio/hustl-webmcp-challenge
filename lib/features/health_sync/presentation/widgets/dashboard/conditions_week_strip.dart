import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/daily_recovery_snapshot.dart';
import 'recovery_band_tint.dart';

/// The seven-day "conditions" strip: one dot per day (last 7, today last and
/// ring-highlighted), filled with that day's band tint. Days with no band
/// render as a hollow outline dot. Entirely data-driven — the weekday initial
/// under each dot comes from the day's own [DateTime.weekday], never from a
/// fixed assumption about which day is "today".
class ConditionsWeekStrip extends StatelessWidget {
  const ConditionsWeekStrip({super.key, required this.snapshots});

  /// Any-length list of recovery snapshots, ascending by date. The last 7 are
  /// shown; the very last entry is treated as "today".
  final List<DailyRecoverySnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final days = snapshots.length > 7
        ? snapshots.sublist(snapshots.length - 7)
        : snapshots;
    final today = days.isEmpty ? null : days.last;

    // No internal "Past week" title — the section title is owned by the
    // dashboard's SectionHeader; only the compact band legend renders here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _LegendKey(band: RecoveryFlowBand.charged),
            _LegendKey(band: RecoveryFlowBand.ready),
            _LegendKey(band: RecoveryFlowBand.steady),
            _LegendKey(band: RecoveryFlowBand.recharge),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final day in days)
              _DayDot(day: day, isToday: identical(day, today)),
          ],
        ),
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.band});

  final RecoveryFlowBand band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bandColors = RecoveryBandColors.resolve(colors, band);

    return Semantics(
      label: band.displayLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            key: ValueKey('conditions-week-legend-${band.name}'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bandColors.accent,
            ),
            child: const SizedBox.square(dimension: 8),
          ),
          const SizedBox(width: 5),
          Text(
            band.displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.isToday});

  final DailyRecoverySnapshot day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final band = day.flowBand;
    // intl's DateFormat doesn't expose a distinct narrow ("W") weekday symbol
    // in the pinned package version — take the first character of the full
    // weekday name instead, still entirely data-driven from the day's date.
    final letter = DateFormat('EEEE').format(day.date.toLocal())[0];

    return Semantics(
      label: band == null
          ? '${DateFormat('EEEE').format(day.date.toLocal())}: no reading'
          : '${DateFormat('EEEE').format(day.date.toLocal())}: ${band.displayLabel}${isToday ? ', today' : ''}',
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: band == null
                  ? Colors.transparent
                  : RecoveryBandColors.resolve(colors, band).accent,
              border: Border.all(
                color: isToday ? colors.onSurface : colors.outlineVariant,
                width: isToday ? 2 : 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            letter,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
