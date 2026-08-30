import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';

import 'body_score/overview_trend_sparkline.dart';

/// A compact trend stat — a label, a big tabular value, an optional one-line
/// cue, and a thin sparkline of the [series]. Used as the volume co-hero on the
/// Progress screen (promoting the trend out of a quiet ▲% row), and reusable
/// for any "value + direction + shape" stat.
class TrendStatCard extends StatelessWidget {
  const TrendStatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.cue,
    this.cueColor,
    this.series = const [],
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// A short direction cue, e.g. "Up 8%". Coloured by [cueColor] (emerald up /
  /// amber down — never red on data).
  final String? cue;
  final Color? cueColor;

  /// The series to sparkline. Drawn only with ≥3 points (a 1-2 point line reads
  /// as noise); otherwise just the value + cue show.
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor ?? colors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (cue != null) ...[
              const SizedBox(width: AppSpacing.x1),
              Text(
                cue!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cueColor ?? colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        if (series.length >= 3) ...[
          const SizedBox(height: AppSpacing.x1),
          OverviewTrendSparkline(dailyTotals: series, height: 30),
        ],
      ],
    );
  }
}
