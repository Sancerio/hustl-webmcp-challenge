import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';

/// Reserves the adherence card's height while it loads so the content below
/// never jumps when the (separately-fetched) weekly adherence resolves.
class AdherenceCardSlot extends StatelessWidget {
  const AdherenceCardSlot({super.key, required this.future});

  final Future<Map<String, dynamic>> future;

  // Matches the loaded card's intrinsic height (header + bar + day dots + pad).
  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) {
            final colors = Theme.of(context).colorScheme;
            return Container(
              height: _height,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: AppRadius.cardRadius,
              ),
            );
          }
          return InsightsAdherenceCard(payload: snap.data!);
        },
      ),
    );
  }
}

class InsightsAdherenceCard extends StatelessWidget {
  const InsightsAdherenceCard({super.key, required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeklyScore = (payload['weeklyScore'] as num?)?.toDouble();
    final days = (payload['days'] as List?) ?? const [];
    if (weeklyScore == null) return const SizedBox.shrink();

    final clamped = weeklyScore.clamp(0.0, 1.0);
    final pctValue = (clamped * 100).roundToDouble();
    final pct = pctValue.toStringAsFixed(0);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Weekly adherence',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              AnimatedMetricText(
                value: pctValue,
                suffix: '%',
                style: AppTextStyles.metricEmphasis(
                  context,
                ).copyWith(color: theme.colorScheme.primary),
                semanticsLabel: 'Weekly adherence',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Weekly adherence $pct%',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 4,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: clamped,
                      child: ColoredBox(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final d in days.whereType<Map>())
                _DayDot(score: (d['score'] as num?)?.toDouble()),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.score});

  final double? score;

  @override
  Widget build(BuildContext context) {
    final s = score ?? 0;
    // Neutral ladder: good -> emerald, partial -> amber, missed -> muted.
    final color = s >= 0.85
        ? AppColors.accentEmeraldGreen
        : (s >= 0.65
              ? AppColors.accentWarningAmber
              : Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35));
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
