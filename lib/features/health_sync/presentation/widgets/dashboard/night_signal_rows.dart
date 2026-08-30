import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';
import 'conditions_copy.dart';

/// The "What tonight built" rows: Sleep / HRV / Resting HR vs. baseline, in
/// the same signal accents and warm delta phrasing as the overview's
/// instruments row (shared via `conditions_copy.dart`'s delta helpers).
class NightSignalRows extends StatelessWidget {
  const NightSignalRows({
    super.key,
    required this.snapshot,
    required this.baselines,
  });

  final DailyRecoverySnapshot snapshot;
  final ConditionsBaselines baselines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <_RowData>[
      _RowData(
        label: 'Sleep',
        accent: colors.primary,
        value: snapshot.sleepDurationMinutes == null
            ? '—'
            : formatHoursMinutes(snapshot.sleepDurationMinutes!),
        delta: sleepDelta(
          snapshot.sleepDurationMinutes,
          baselines.sleepMinutes,
        ),
      ),
      _RowData(
        label: 'HRV',
        accent: AppColors.accentEmeraldGreen,
        value: snapshot.hrvValue == null
            ? '—'
            : '${snapshot.hrvValue!.toStringAsFixed(0)} ms',
        delta: hrvDelta(snapshot.hrvValue, baselines.hrvValue),
      ),
      _RowData(
        label: 'Resting HR',
        accent: AppColors.accentWarningAmber,
        value: snapshot.restingHeartRateBpm == null
            ? '—'
            : '${snapshot.restingHeartRateBpm!.toStringAsFixed(0)} bpm',
        delta: rhrDelta(
          snapshot.restingHeartRateBpm,
          baselines.restingHeartRateBpm,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _SignalRow(data: rows[i]),
        ],
      ],
    );
  }
}

class _RowData {
  const _RowData({
    required this.label,
    required this.accent,
    required this.value,
    required this.delta,
  });

  final String label;
  final Color accent;
  final String value;
  final SignalDelta? delta;
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.data});

  final _RowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final deltaText = data.delta?.label ?? 'No data yet';

    return Semantics(
      label: '${data.label}: ${data.value}, $deltaText',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: data.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.x1 + 4),
            Expanded(child: Text(data.label, style: theme.textTheme.bodyLarge)),
            Text(data.value, style: theme.textTheme.labelLarge),
            const SizedBox(width: 6),
            Text(
              '· $deltaText',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
