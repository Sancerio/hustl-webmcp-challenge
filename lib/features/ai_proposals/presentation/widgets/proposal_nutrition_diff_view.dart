import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../nutrition_tracker/domain/models/nutrition_target_plan.dart';
import '../../domain/models/proposal_detail.dart';

/// Renders a `nutrition_targets` proposal: the resolved week, the proposed
/// calories + protein/carbs/fat, and — when a current week target exists — the
/// delta per metric. The proposal is already reconciled (carbs balanced to
/// calories) + floor-clamped server-side at propose time, so these numbers are
/// exactly what approval persists; a footnote states that.
class ProposalNutritionDiffView extends StatelessWidget {
  const ProposalNutritionDiffView({
    super.key,
    required this.detail,
    required this.currentPlan,
    this.terminal = false,
  });

  final ProposalDetail detail;

  /// The current week's target plan (null if none exists yet).
  final NutritionTargetPlan? currentPlan;
  final bool terminal;

  /// Monday of the user's current LOCAL week (weekday: Mon=1 .. Sun=7).
  static DateTime _currentWeekMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _g(double v) => '${v.round()} g';
  static String _kcal(double v) => '${v.round()} kcal';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final n = detail.proposedNutrition;
    if (n == null) {
      return const SizedBox.shrink();
    }
    final cur = terminal ? null : currentPlan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!terminal) ...[
          // The week resolved from the user's LOCAL today — the same week approval
          // applies to (the backend resolves it from the local date the app sends).
          _WeekBanner(weekStart: _currentWeekMonday()),
          const SizedBox(height: AppSpacing.x2),
        ],
        SectionHeader(
          terminal || cur == null ? 'Proposed targets' : 'Proposed changes',
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        SectionList(
          card: true,
          children: [
            _MetricRow(
              label: 'Calories',
              proposed: _kcal(n.caloriesTarget),
              current: cur == null ? null : _kcal(cur.caloriesTarget),
              delta: cur == null ? null : n.caloriesTarget - cur.caloriesTarget,
              unit: 'kcal',
            ),
            _MetricRow(
              label: 'Protein',
              proposed: _g(n.proteinTarget),
              current: cur == null ? null : _g(cur.proteinTarget),
              delta: cur == null ? null : n.proteinTarget - cur.proteinTarget,
              unit: 'g',
            ),
            _MetricRow(
              label: 'Carbs',
              proposed: _g(n.carbsTarget),
              current: cur == null ? null : _g(cur.carbsTarget),
              delta: cur == null ? null : n.carbsTarget - cur.carbsTarget,
              unit: 'g',
            ),
            _MetricRow(
              label: 'Fat',
              proposed: _g(n.fatTarget),
              current: cur == null ? null : _g(cur.fatTarget),
              delta: cur == null ? null : n.fatTarget - cur.fatTarget,
              unit: 'g',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          terminal
              ? 'These are the calorie and macro targets included in the proposal.'
              : 'These are the exact targets that will be saved — carbs are balanced to '
                    'your calories, and calories stay within your target floor.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        if ((detail.proposedNutrition?.rationale ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x1),
          _Rationale(text: detail.proposedNutrition!.rationale!.trim()),
        ],
      ],
    );
  }
}

class _WeekBanner extends StatelessWidget {
  const _WeekBanner({required this.weekStart});

  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: AppColors.accentEmeraldGreen.withValues(alpha: 0.10),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 18,
            color: AppColors.accentEmeraldGreen,
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              'Applies to the week of '
              '${ProposalNutritionDiffView._date(weekStart)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.proposed,
    required this.current,
    required this.delta,
    required this.unit,
  });

  final String label;
  final String proposed;
  final String? current;
  final double? delta;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final d = delta;
    final rounded = d == null ? 0 : d.round();
    final hasDelta = d != null && rounded != 0;
    final tone = rounded > 0
        ? AppColors.accentEmeraldGreen
        : AppColors.accentWarningAmber;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                proposed,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (current != null && hasDelta)
                Text(
                  '$current → ${rounded > 0 ? '+' : ''}$rounded $unit',
                  style: theme.textTheme.labelSmall?.copyWith(color: tone),
                )
              else if (current != null)
                Text(
                  'No change',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rationale extends StatelessWidget {
  const _Rationale({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
