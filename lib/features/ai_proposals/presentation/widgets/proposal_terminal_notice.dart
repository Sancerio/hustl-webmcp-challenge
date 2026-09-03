import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import 'proposal_status_chip.dart';

/// Explains why a decided proposal is read-only when its detail route is
/// revisited from activity, browser history, or a saved link.
class ProposalTerminalNotice extends StatelessWidget {
  const ProposalTerminalNotice({super.key, required this.status});

  final String status;

  String get _title => switch (status) {
    'applied' => 'This proposal was applied',
    'reverted' => 'This proposal was undone',
    'rejected' => 'This proposal was dismissed',
    _ => 'This proposal is no longer actionable',
  };

  String get _body => switch (status) {
    'applied' =>
      'Its changes are already reflected in Hustl. Review the details below.',
    'reverted' =>
      'Its applied changes were undone. Nothing can be applied from this screen.',
    'rejected' =>
      'It did not change your Hustl data. Review the dismissed proposal below.',
    _ => 'It can no longer be applied or dismissed.',
  };

  IconData get _icon => switch (status) {
    'applied' => Icons.check_circle_outline_rounded,
    'reverted' => Icons.undo_rounded,
    'rejected' => Icons.block_rounded,
    _ => Icons.schedule_rounded,
  };

  Color _accent(ColorScheme colors) => switch (status) {
    'applied' => AppColors.accentEmeraldGreen,
    'rejected' => AppColors.accentWarningAmber,
    _ => colors.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _accent(colors);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 20, color: accent),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          ProposalStatusChip(status: status),
        ],
      ),
    );
  }
}
