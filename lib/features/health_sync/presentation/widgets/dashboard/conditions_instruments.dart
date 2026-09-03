import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/models/recovery_signal_availability.dart';
import 'conditions_copy.dart';

/// The three-tile "instruments" row: Sleep, HRV, Resting HR, each showing
/// today's value against its trailing baseline with a tiny up/down chevron.
///
/// Display is VALUE-FIRST: a value the snapshot actually carries always
/// renders, regardless of [signalAvailability] — availability defaults to
/// empty on cached loads / older states (see HealthOverviewState), so gating
/// the value on it would dash out a data-rich screen. Availability only
/// chooses the caption when the value is null: "No data yet" when the signal
/// isn't flowing vs "Building baseline" when it is flowing but the baseline
/// hasn't formed. The Sleep tile taps through to the "Last night" detail
/// screen.
class ConditionsInstruments extends StatelessWidget {
  const ConditionsInstruments({
    super.key,
    required this.snapshot,
    required this.baselines,
    required this.signalAvailability,
  });

  final DailyRecoverySnapshot? snapshot;
  final ConditionsBaselines baselines;
  final RecoverySignalAvailability signalAvailability;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final snap = snapshot;

    final sleepMinutes = snap?.sleepDurationMinutes;
    final hrv = snap?.hrvValue;
    final rhr = snap?.restingHeartRateBpm;

    // IntrinsicHeight (not CrossAxisAlignment.stretch alone) so the three
    // tiles equalize height safely — a stretch-only Row would ask its
    // children to fill an unbounded cross-axis extent when this row sits
    // inside a scrollable ancestor, which throws an infinite-height layout
    // error.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _InstrumentTile(
              label: 'Sleep',
              accent: colors.primary,
              value: sleepMinutes != null
                  ? formatHoursMinutes(sleepMinutes)
                  : '—',
              hasValue: sleepMinutes != null,
              delta: sleepDelta(sleepMinutes, baselines.sleepMinutes),
              available: signalAvailability.sleep,
              onTap: () => context.push('/health/night'),
            ),
          ),
          const SizedBox(width: AppSpacing.x1 + 2),
          Expanded(
            child: _InstrumentTile(
              label: 'HRV',
              accent: AppColors.accentEmeraldGreen,
              value: hrv != null ? '${hrv.toStringAsFixed(0)} ms' : '—',
              hasValue: hrv != null,
              delta: hrvDelta(hrv, baselines.hrvValue),
              available: signalAvailability.hrv,
            ),
          ),
          const SizedBox(width: AppSpacing.x1 + 2),
          Expanded(
            child: _InstrumentTile(
              label: 'Resting HR',
              accent: AppColors.accentWarningAmber,
              value: rhr != null ? '${rhr.toStringAsFixed(0)} bpm' : '—',
              hasValue: rhr != null,
              delta: rhrDelta(rhr, baselines.restingHeartRateBpm),
              available: signalAvailability.restingHeartRate,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstrumentTile extends StatelessWidget {
  const _InstrumentTile({
    required this.label,
    required this.accent,
    required this.value,
    required this.hasValue,
    required this.delta,
    required this.available,
    this.onTap,
  });

  final String label;
  final Color accent;
  final String value;
  final bool hasValue;
  final SignalDelta? delta;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Value-first caption: a real delta always wins. Without one, a present
    // value (or a flowing signal) reads "Building baseline"; only a truly
    // silent signal (no value AND not flowing) reads "No data yet".
    final deltaText =
        delta?.label ??
        (hasValue || available ? 'Building baseline' : 'No data yet');

    final content = Container(
      padding: const EdgeInsets.all(AppSpacing.x1 + 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.metricEmphasis(context)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (delta != null) ...[
                SizedBox(
                  width: 7,
                  height: 7,
                  child: CustomPaint(
                    painter: _DeltaTrianglePainter(
                      up: delta!.up,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  deltaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final semanticsLabel = '$label: $value, $deltaText';
    if (onTap == null) {
      return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: content,
      );
    }
    return Semantics(
      label: semanticsLabel,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// A tiny filled up/down chevron marking whether a value moved above or below
/// its baseline.
class _DeltaTrianglePainter extends CustomPainter {
  const _DeltaTrianglePainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (up) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DeltaTrianglePainter oldDelegate) =>
      oldDelegate.up != up || oldDelegate.color != color;
}
