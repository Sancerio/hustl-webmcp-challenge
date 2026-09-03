import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/models/proposed_food_log.dart';

/// Renders a `food_log` proposal: the day it logs to, each proposed item with its
/// portion + macros, and the meal totals. Mirrors the nutrition diff view's
/// section/card language. Approving writes these as diary entries (undoable).
class ProposalFoodLogView extends StatelessWidget {
  const ProposalFoodLogView({
    super.key,
    required this.detail,
    this.terminal = false,
  });

  final ProposalDetail detail;
  final bool terminal;

  static String _g(double v) => '${v.round()} g';
  static String _kcal(double v) => '${v.round()} kcal';
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final food = detail.proposedFoodLog;
    if (food == null || food.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(
          icon: Icons.event_available_outlined,
          text: terminal
              ? food.date == null
                    ? 'No log date was recorded in this proposal'
                    : 'Proposed for ${_date(food.date!)}'
              : food.date == null
              ? 'Logs to today'
              : 'Logs to the day of ${_date(food.date!)}',
        ),
        const SizedBox(height: AppSpacing.x2),
        const SectionHeader(
          'Items',
          padding: EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        SectionList(
          card: true,
          children: [for (final it in food.items) _ItemRow(item: it)],
        ),
        const SizedBox(height: AppSpacing.x2),
        SectionList(
          card: true,
          children: [
            _TotalRow(
              calories: food.totalCalories,
              protein: food.totalProtein,
              carbs: food.totalCarbs,
              fat: food.totalFat,
            ),
          ],
        ),
        if ((food.note ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            food.note!.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (!terminal) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Logged by your assistant — undo right after approving, or remove any '
            'entry from the diary.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

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
          Icon(icon, size: 18, color: AppColors.accentEmeraldGreen),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              text,
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final ProposedFoodItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final macros =
        'P ${item.proteinGrams.round()} · C ${item.carbsGrams.round()} · F ${item.fatGrams.round()}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.foodName, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  '${ProposalFoodLogView._g(item.servingGrams)} · $macros',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          Text(
            ProposalFoodLogView._kcal(item.calories),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'P ${protein.round()} · C ${carbs.round()} · F ${fat.round()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            ProposalFoodLogView._kcal(calories),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
