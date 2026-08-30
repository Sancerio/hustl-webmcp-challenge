import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';

/// A compact "what you trained" heatmap built from the session's hard sets
/// — flat and borderless, one slim bar per muscle group whose fill and
/// intensity scale with hard-set volume.
class SummaryMuscleHeatmap extends StatelessWidget {
  const SummaryMuscleHeatmap({super.key, required this.credits});

  /// Hard sets per muscle group for this session (already filtered to the
  /// non-zero, non-`other` muscle groups and sorted descending by the caller).
  final Map<DisplayRegion, double> credits;

  @override
  Widget build(BuildContext context) {
    if (credits.isEmpty) return const SizedBox.shrink();

    final maxCredit = credits.values.fold<double>(0, (m, v) => v > m ? v : m);
    final accent = AppColors.accentEmeraldGreen;

    return Semantics(
      label: 'Muscles trained this session, hard sets counted',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            'Muscles trained',
            padding: EdgeInsets.only(bottom: AppSpacing.x1),
          ),
          for (final entry in credits.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RegionBar(
                label: entry.key.label,
                credit: entry.value,
                intensity: maxCredit <= 0 ? 0 : entry.value / maxCredit,
                accent: accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _RegionBar extends StatelessWidget {
  const _RegionBar({
    required this.label,
    required this.credit,
    required this.intensity,
    required this.accent,
  });

  final String label;
  final double credit;
  final double intensity;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isWhole = (credit - credit.round()).abs() < 0.05;
    final value = NumberFormatUtil.formatDouble(
      credit,
      decimalDigits: isWhole ? 0 : 1,
    );

    return Semantics(
      label: '$label: $value hard sets',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: theme.textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    Container(height: 4, color: colors.outlineVariant),
                    FractionallySizedBox(
                      widthFactor: (0.08 + 0.92 * intensity).clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        color: accent.withValues(
                          alpha: (0.35 + 0.65 * intensity).clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            SizedBox(
              width: 36,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
