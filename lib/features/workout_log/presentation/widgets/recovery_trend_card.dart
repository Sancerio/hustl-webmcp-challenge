import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/recovery_band_tint.dart';

/// A compact "Recovery trend" entry on Progress (spec "Insights trend"). Shows
/// the last few days as small band-tinted bars (height ∝ readiness, color ∝
/// band) so the trend is visible outside the buried `/health` dashboard, and
/// deep-links there for the full view.
///
/// Distinct from Body balance / Body Score: this is the acute, daily recovery
/// signal. Strictly additive — [maybe] returns `null` when there is no usable
/// recovery data, so Progress renders exactly as today.
class RecoveryTrendCard extends StatelessWidget {
  const RecoveryTrendCard({super.key, required this.snapshots, this.onTap});

  /// Recovery snapshots, oldest → newest. Only those carrying recovery signal
  /// are shown; the most recent few are drawn as bars.
  final List<DailyRecoverySnapshot> snapshots;

  /// Override the default `/health` navigation (used in tests).
  final VoidCallback? onTap;

  /// How many trailing days to draw.
  static const int _maxBars = 10;

  /// Builds the card only when there is at least one snapshot carrying recovery
  /// signal, else `null` so the caller renders nothing.
  static Widget? maybe(
    List<DailyRecoverySnapshot> snapshots, {
    VoidCallback? onTap,
  }) {
    final usable = snapshots.where((s) => s.hasRecoveryData).toList();
    if (usable.isEmpty) return null;
    return RecoveryTrendCard(snapshots: usable, onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final usable = snapshots.where((s) => s.hasRecoveryData).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final recent = usable.length > _maxBars
        ? usable.sublist(usable.length - _maxBars)
        : usable;
    final latest = recent.last;
    final latestBand = latest.flowBand?.displayLabel;
    final subtitle = latestBand != null
        ? 'Last ${recent.length} days · latest $latestBand'
        : 'Last ${recent.length} days';

    return Semantics(
      button: true,
      label: 'Recovery trend, $subtitle, opens recovery details',
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.cardRadius,
            onTap: () {
              Haptics.selection();
              if (onTap != null) {
                onTap!();
              } else {
                context.push('/health');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recovery trend',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: theme.textTheme.bodySmall),
                        const SizedBox(height: AppSpacing.x1),
                        _BandSparkline(snapshots: recent),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Icon(
                    Icons.chevron_right_rounded,
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
}

/// A tiny band-tinted bar sparkline. Each bar's height tracks readiness and its
/// color the band (warm amber for low, never red) via the token mapping. Purely
/// decorative; the latest band is named in text beside it for color-blind safety.
class _BandSparkline extends StatelessWidget {
  const _BandSparkline({required this.snapshots});

  final List<DailyRecoverySnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final snapshot in snapshots)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Bar(
                color: RecoveryBandColors.resolve(
                  colors,
                  snapshot.flowBand,
                ).accent,
                fraction: _fractionFor(snapshot),
              ),
            ),
        ],
      ),
    );
  }

  /// Bar height as a fraction of the track, from the readiness score (0–100),
  /// floored so even a low day stays visible. Falls back to a mid value when a
  /// score is absent.
  double _fractionFor(DailyRecoverySnapshot snapshot) {
    final score = snapshot.readinessScore ?? snapshot.recoveryScore;
    if (score == null) return 0.5;
    return (score / 100).clamp(0.18, 1.0);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.fraction});

  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: 26,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: fraction,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
