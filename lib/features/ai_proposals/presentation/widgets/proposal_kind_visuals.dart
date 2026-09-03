import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/proposal_summary.dart';

/// Kind → icon/label/tint vocabulary shared by [ProposalInboxRow] and the
/// history row, so both surfaces read as siblings rather than inventing a
/// second visual language. Lifted verbatim from the inbox row's original
/// `_icon()`/`_kindLabel()`/tile-tint logic.

String proposalKindLabel(ProposalSummary proposal) {
  if (proposal.isNutrition) return 'Nutrition';
  if (proposal.isFoodLog) return 'Food log';
  if (proposal.isFoodLogEdit) return 'Food edit';
  if (proposal.isFoodLogDelete) return 'Food removal';
  if (proposal.isWorkoutLog) return 'Workout log';
  return proposal.isEdit ? 'Edit' : 'New template';
}

IconData proposalKindIcon(ProposalSummary proposal) {
  if (proposal.isNutrition) return Icons.restaurant_outlined;
  if (proposal.isFoodLog) return Icons.lunch_dining_outlined;
  if (proposal.isFoodLogEdit) return Icons.edit_note_outlined;
  if (proposal.isFoodLogDelete) return Icons.delete_outline;
  if (proposal.isWorkoutLog) return Icons.fitness_center_outlined;
  return proposal.isEdit ? Icons.edit_outlined : Icons.auto_awesome_outlined;
}

Color proposalKindTint(ProposalSummary proposal) {
  return proposal.isEdit
      ? AppColors.accentWarningAmber
      : AppColors.accentEmeraldGreen;
}

/// The human-readable label for a decided proposal's terminal [status], shared
/// by the history row's Semantics and [ProposalStatusChip] so the two can't
/// drift. Unknown values read as a neutral "Expired".
String proposalStatusLabel(String status) => switch (status) {
  'applied' => 'Applied',
  'reverted' => 'Undone',
  'rejected' => 'Declined',
  _ => 'Expired',
};
