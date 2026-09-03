import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/recovery_band_copy.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/health_dashboard_copy.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/recovery_band_tint.dart';

/// A slim, quiet "Readiness" annotation for the Train home (R2). Not a second
/// ring, not a big card: a single tappable row with a small band-tinted dot, a
/// "Readiness" label, the band name (and optional score), and a one-line kind
/// band message. Tapping deep-links to the full `/health` dashboard.
///
/// [ReadinessTodaySlot] owns loading/absence gating so this row only represents
/// a usable snapshot. While calibrating it shows a gentle baseline variant; on
/// low confidence the copy softens to a rough estimate.
///
/// Color is ALWAYS paired with the band's text label (color-blind safety); the
/// dot tint comes from the domain's [RecoveryBandTint] → token mapping (warm
/// amber for Recharge, never red).
class ReadinessTodayRow extends StatelessWidget {
  const ReadinessTodayRow({super.key, required this.snapshot});

  final DailyRecoverySnapshot snapshot;

  /// Builds the row only when a usable [snapshot] is present, else `null` so the
  /// caller renders nothing. Keeps all gating in one place.
  static Widget? maybe(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null || !snapshot.hasRecoveryData) return null;
    return ReadinessTodayRow(snapshot: snapshot);
  }

  /// Whether the snapshot is still building its baseline (n/14) rather than
  /// showing a confident band.
  bool get _isCalibrating =>
      snapshot.isCalibrating || snapshot.flowBand == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bandColors = RecoveryBandColors.resolve(colors, snapshot.flowBand);

    final label = _isCalibrating
        ? (RecoveryBandCopy.calibrationLabel(snapshot) ??
              'Building your readiness baseline')
        : flowBandLabel(snapshot);
    final message = _message();
    final score = snapshot.readinessScore?.round();
    final showScore = !_isCalibrating && score != null;

    final semanticsLabel = [
      'Readiness',
      label,
      if (showScore) '$score out of 100',
      message,
      'Opens recovery details',
    ].join(', ');
    void openHealth() {
      Haptics.selection();
      context.push('/health');
    }

    return Semantics(
      container: true,
      button: true,
      onTap: openHealth,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surface,
          borderRadius: AppRadius.cardRadius,
          child: InkWell(
            borderRadius: AppRadius.cardRadius,
            onTap: openHealth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 + 4,
              ),
              child: Row(
                children: [
                  _BandDot(color: bandColors.accent),
                  const SizedBox(width: AppSpacing.x1 + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Readiness',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1),
                            Flexible(
                              child: Text(
                                showScore ? '$label · $score' : label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one-line kind band message, softened while calibrating / low
  /// confidence. Always an invitation, never a command.
  String _message() {
    if (_isCalibrating) {
      final remaining = snapshot.calibrationDaysRemaining;
      if (remaining > 0) {
        final dayWord = remaining == 1 ? 'day' : 'days';
        return 'About $remaining more $dayWord to learn your normal.';
      }
      return 'A few more nights will sharpen your readiness.';
    }
    final headline = RecoveryBandCopy.headlineForBand(snapshot.flowBand!);
    if (snapshot.confidence == RecoveryConfidence.low) {
      return 'Rough estimate — $headline';
    }
    return headline;
  }
}

/// A small band-tinted dot. Color is decorative only; the band label always
/// sits beside it so the row stays color-blind safe.
class _BandDot extends StatelessWidget {
  const _BandDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
