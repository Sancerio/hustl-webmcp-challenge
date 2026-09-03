import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/text_format.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../../../core/widgets/inline_notice.dart';
import '../../domain/models/proposal_detail.dart';

/// The card header for the proposal approval screen: a kind chip + the proposal
/// title + optional description. Shared by all proposal kinds.
class ProposalApprovalHeader extends StatelessWidget {
  const ProposalApprovalHeader({super.key, required this.detail});

  final ProposalDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final desc = detail.description?.trim();
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Amber = mutates/removes existing data (template edit, food edit/
              // removal); emerald = additive (new template, targets, food/workout
              // logs).
              AppChip(
                label: detail.isNutrition
                    ? 'Nutrition targets'
                    : detail.isFoodLog
                    ? 'Food log'
                    : detail.isFoodLogEdit
                    ? 'Edit food entry'
                    : detail.isFoodLogDelete
                    ? 'Remove food entry'
                    : detail.isWorkoutLog
                    ? 'Workout log'
                    : detail.isEdit
                    ? 'Edit template'
                    : 'New template',
                variant: AppChipVariant.status,
                color: (detail.isEdit || detail.isFoodLogRevision)
                    ? AppColors.accentWarningAmber
                    : AppColors.accentEmeraldGreen,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            formatExerciseName(detail.templateName),
            style: theme.textTheme.titleLarge,
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Hard-block notice for a stale template edit (the base version moved).
class ProposalStaleNotice extends StatelessWidget {
  const ProposalStaleNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const InlineNotice(
      icon: Icons.error_outline,
      title: 'This template changed since the proposal',
      body: 'Ask your AI to re-propose against the current version.',
    );
  }
}

/// Soft (non-blocking) notice that approving a nutrition proposal overwrites an
/// existing target for the resolved week.
class ProposalNutritionChangedNotice extends StatelessWidget {
  const ProposalNutritionChangedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const InlineNotice(
      icon: Icons.info_outline,
      title: 'You already have targets for this week',
      body: 'Approving replaces this week\'s calories and macros.',
    );
  }
}
