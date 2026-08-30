import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/models/proposal_summary.dart';
import 'proposal_kind_visuals.dart';
import 'proposal_status_chip.dart';

/// A single history row: mirrors [ProposalInboxRow]'s glyph-tile + title +
/// meta layout, but the trailing column shows the clock time stacked over
/// either an inline Undo action (still-revertable applied log rows) or a
/// [ProposalStatusChip]. When a row is undone the Undo→chip swap animates.
class ProposalHistoryRow extends StatelessWidget {
  const ProposalHistoryRow({
    super.key,
    required this.proposal,
    required this.isBusy,
    required this.onUndo,
  });

  final ProposalSummary proposal;
  final bool isBusy;
  final VoidCallback onUndo;

  /// The visible meta line leads with the summary payload. Unlike the pending
  /// inbox (whose rows open a detail screen), history rows don't tap through —
  /// the truncated summary is all the user gets, so we don't spend its first
  /// ~10 chars re-stating the kind the glyph tile already shows. Falls back to
  /// the kind label when there's no summary. (Screen readers still get the kind
  /// via the row's Semantics label below.)
  String _meta() {
    final summary = proposal.summary?.trim();
    final base = summary != null && summary.isNotEmpty
        ? summary
        : proposalKindLabel(proposal);
    return proposal.isFirstPartyWebAutoLog ? 'Web auto-log · $base' : base;
  }

  // Clock time within the row's day group (e.g. "2:14 PM"); the day header
  // carries the date. Tabular figures let the times align down the trailing edge.
  static final DateFormat _clock = DateFormat('h:mm a');

  Widget _trailingAction(ThemeData theme) {
    if (isBusy) {
      return const SizedBox(
        key: ValueKey('busy'),
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (proposal.isRevertable) {
      // Kept as its own semantics node (an actionable button) — the row's
      // descriptive label lives on the outer Semantics container.
      return TextButton(
        key: const ValueKey('undo'),
        onPressed: onUndo,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentElectricBlue,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text('Undo'),
      );
    }
    return ExcludeSemantics(
      key: ValueKey('chip-${proposal.status}'),
      child: ProposalStatusChip(status: proposal.status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = proposalKindTint(proposal);
    final time = proposal.decidedAt ?? proposal.createdAt;
    final meta = _meta();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      container: true,
      label:
          '${proposal.templateName}. ${proposalKindLabel(proposal)}. '
          '$meta. ${proposalStatusLabel(proposal.status)} ${_clock.format(time)}.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(proposalKindIcon(proposal), size: 20, color: tint),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.templateName,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    _clock.format(time),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : AppMotion.medium,
                  switchInCurve: AppMotion.enterCurve,
                  switchOutCurve: AppMotion.exitCurve,
                  transitionBuilder: appFadeSlideTransition,
                  child: _trailingAction(theme),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
