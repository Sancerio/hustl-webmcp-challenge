import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../learn/domain/learn_articles.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/usecases/recovery_band_copy.dart';
import 'conditions_copy.dart';
import 'conditions_sky_painter.dart';
import 'health_dashboard_copy.dart';

/// The "Conditions Report" hero: recovery as mountain weather. A painted sky
/// of ridgelines under a sun/cloud that encodes the readiness band, the band
/// word as a large display headline, and — the Ledger-direction steal — a
/// one-sentence data-woven lede. Beneath the painting, unchanged in substance
/// from the previous ring hero: the readiness number, the confidence chip,
/// and the "How we read this" affordance.
class ConditionsHero extends StatelessWidget {
  const ConditionsHero({
    super.key,
    required this.snapshot,
    required this.sleepBaselineMinutes,
    required this.hrvBaseline,
    required this.rhrBaseline,
  });

  final DailyRecoverySnapshot? snapshot;
  final double? sleepBaselineMinutes;
  final double? hrvBaseline;
  final double? rhrBaseline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final snap = snapshot;
    final isCalibrating =
        snap == null || snap.isCalibrating || snap.flowBand == null;
    final band = snap?.flowBand;

    final headline = isCalibrating
        ? (RecoveryBandCopy.calibrationLabel(snap) ?? 'Building your baseline')
        : '${band!.displayLabel}.';

    final lede = isCalibrating
        ? null
        : conditionsLede(
            snap,
            sleepBaselineMinutes: sleepBaselineMinutes,
            hrvBaseline: hrvBaseline,
            rhrBaseline: rhrBaseline,
          );
    final subline = lede ?? coachHeadline(snap);

    final confidenceText = RecoveryBandCopy.confidenceLabel(snap?.confidence);
    final hasReadiness = snap?.readinessScore != null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The painted sky + band-word content is summarized as one
          // semantics node; the confidence chip and "How we read this" link
          // below are LEFT OUTSIDE this node (they carry their own semantics)
          // so assistive tech can still discover and activate them.
          Semantics(
            label: [
              isCalibrating ? headline : 'Today\'s conditions: $headline',
              if (hasReadiness) '${snap!.readinessScore!.round()} readiness',
              confidenceText,
            ].join(', '),
            excludeSemantics: true,
            child: SizedBox(
              height: 196,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ConditionsSkyPainter(
                        mood: skyMoodForBand(isCalibrating ? null : band),
                        sun: AppColors.accentWarningAmber,
                        // Slightly tinted off the hero's surface canvas so
                        // the cloud reads as an object in front of the sun
                        // rather than a bite out of its disc (which reads as
                        // a crescent moon).
                        cloudFill: Color.lerp(
                          colors.surface,
                          colors.surfaceContainerHighest,
                          .55,
                        )!,
                        cloudOutline: colors.outlineVariant,
                        ridgeFillNear: Color.lerp(
                          colors.surface,
                          colors.surfaceContainerHighest,
                          .55,
                        )!,
                        ridgeFillFar: Color.lerp(
                          colors.surface,
                          colors.surfaceContainerHighest,
                          .85,
                        )!,
                        ridgeOutline: colors.outlineVariant,
                        ridgeEcho: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.x2,
                    right: AppSpacing.x2,
                    bottom: AppSpacing.x2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Today's conditions".toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          headline,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.1,
                            height: 1.0,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subline,
                          // The lede is the hero's payload — let it wrap
                          // rather than truncate mid-sentence. Three lines
                          // covers the longest all-signal composition at
                          // narrow phone widths.
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              AppSpacing.x1,
              AppSpacing.x2,
              AppSpacing.x2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Readiness + confidence on the left, "Last night" on the
                // right — kept off the Wrap below so four elements never
                // compete for the same line on a narrow phone.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.x1,
                        runSpacing: AppSpacing.x1 / 2,
                        children: [
                          Text(
                            hasReadiness
                                ? 'Readiness ${snap!.readinessScore!.round()}'
                                : 'Readiness —',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _ConfidenceChip(label: confidenceText),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x1),
                    const _LastNightLink(),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1 / 2),
                const _LearnMoreLink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A quiet, discrete "Learn more" link that opens the recovery & readiness
/// explainer — unchanged in substance from the previous hero.
class _LearnMoreLink extends StatelessWidget {
  const _LearnMoreLink();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const label = RecoveryBandCopy.learnMoreLabel;
    return Semantics(
      button: true,
      label: '$label about recovery and readiness',
      child: InkWell(
        onTap: () => context.push('/learn/$recoveryAndReadinessSlug'),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 14, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero's entry point into the "Last night" detail screen.
class _LastNightLink extends StatelessWidget {
  const _LastNightLink();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Last night — see the full detail',
      child: InkWell(
        onTap: () => context.push('/health/night'),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Last night',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
