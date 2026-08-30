import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';

/// The combined AI starter artifact: a proposed next workout and/or a nutrition
/// target preview, both carrying the recurring **"based on:" lineage** (the
/// anti-black-box trust mark). Fed entirely from the real [ProposalDetail] —
/// rows render only for the parts the proposal actually carries.
///
/// Pure preview: the Approve / "Not now" actions live on the screen so the
/// approval logic is not forked into the card.
class StarterProposalCard extends StatelessWidget {
  const StarterProposalCard({
    super.key,
    required this.proposal,
    required this.lineageText,
  });

  final ProposalDetail proposal;

  /// The "based on:" lineage line — the recurring trust mark.
  final String lineageText;

  /// Resting-card surface: surface-ladder fill + a subtle soft shadow + card
  /// radius, no hard border (matches the rest of Hustl).
  BoxDecoration _cardDecoration(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colors.surfaceContainerHigh,
      borderRadius: AppRadius.cardRadius,
      boxShadow: [AppShadows.subtle(context)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nutrition = proposal.proposedNutrition;
    final exerciseCount = proposal.proposedExercises.isNotEmpty
        ? proposal.proposedExercises.length
        : proposal.summary.exerciseCount;
    final showWorkout = !proposal.isNutrition && exerciseCount > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: colors.primary),
              const SizedBox(width: AppSpacing.x1),
              Expanded(
                child: Text(
                  'Your starter plan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (showWorkout) ...[
            const SizedBox(height: AppSpacing.x2),
            _ProposalRow(
              icon: Icons.fitness_center_rounded,
              accent: colors.primary,
              title: 'Next workout · ${proposal.templateName}',
              subtitle: _exerciseCountLabel(exerciseCount),
            ),
          ],
          if (nutrition != null) ...[
            const SizedBox(height: AppSpacing.x2),
            _ProposalRow(
              icon: Icons.local_fire_department_rounded,
              accent: AppColors.accentEmeraldGreen,
              title: '${_grouped(nutrition.caloriesTarget)} kcal target',
              subtitleWidget: _MacroChips(
                protein: '${nutrition.proteinTarget.round()}g protein',
                carbs: '${nutrition.carbsTarget.round()}g carbs',
                fat: '${nutrition.fatTarget.round()}g fat',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.x2),
          _LineageRow(text: lineageText),
        ],
      ),
    );
  }

  static String _exerciseCountLabel(int count) => count == 1
      ? '1 exercise, tuned to your sessions'
      : '$count exercises, tuned to your sessions';

  /// Thousands-grouped integer (e.g. 2,340) for the calorie figure.
  static String _grouped(num value) {
    final n = value.round();
    final digits = n.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${n < 0 ? '-' : ''}$buffer';
  }
}

class _ProposalRow extends StatelessWidget {
  const _ProposalRow({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              if (subtitleWidget != null)
                subtitleWidget!
              else
                Text(subtitle ?? '', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Macro pills via the canonical chip vocabulary + macro color tokens.
class _MacroChips extends StatelessWidget {
  const _MacroChips({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final String protein;
  final String carbs;
  final String fat;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      children: [
        AppChip(
          variant: AppChipVariant.status,
          color: AppColors.macroProtein,
          label: protein,
        ),
        AppChip(
          variant: AppChipVariant.status,
          color: AppColors.macroCarbs,
          label: carbs,
        ),
        AppChip(
          variant: AppChipVariant.status,
          color: AppColors.macroFat,
          label: fat,
        ),
      ],
    );
  }
}

/// The recurring signature trust mark — every proposal shows its inputs. A quiet
/// inline line (not a loud bordered pill).
class _LineageRow extends StatelessWidget {
  const _LineageRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.insights_rounded, size: 15, color: colors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
