import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_chip.dart';
import 'proposal_kind_visuals.dart';

/// A decided proposal's terminal status, rendered with the app's canonical
/// [AppChip] status variant (flat 10% tint, no border). Tones stay calm and
/// kind — emerald for applied, neutral for undone, muted amber for declined —
/// never the destructive red variant.
class ProposalStatusChip extends StatelessWidget {
  const ProposalStatusChip({super.key, required this.status});

  /// One of `applied`, `reverted`, `rejected` (any other value reads as a
  /// neutral "Expired" rather than crashing on an unknown status).
  final String status;

  String get _label => proposalStatusLabel(status);

  Color _color(ColorScheme colors) => switch (status) {
    'applied' => AppColors.accentEmeraldGreen,
    'rejected' => AppColors.accentWarningAmber,
    _ => colors.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    return AppChip(label: _label, color: _color(Theme.of(context).colorScheme));
  }
}
