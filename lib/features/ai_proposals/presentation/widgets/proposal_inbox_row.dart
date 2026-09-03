import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/models/proposal_summary.dart';
import 'proposal_kind_visuals.dart';

/// A single inbox row: an icon holder, the template name + a summary line, and
/// a chevron. Stale (needs-re-propose) rows swap the chevron for an amber hint.
class ProposalInboxRow extends StatelessWidget {
  const ProposalInboxRow({
    super.key,
    required this.proposal,
    required this.onTap,
    this.isStale = false,
    this.isBusy = false,
  });

  final ProposalSummary proposal;
  final VoidCallback onTap;
  final bool isStale;
  final bool isBusy;

  String _meta() {
    final kindLabel = proposalKindLabel(proposal);
    final summary = proposal.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return '$kindLabel · $summary';
    }
    // Nutrition + food logs/revisions have no exercise list, so don't assume a count.
    if (proposal.isNutrition) return '$kindLabel · Calories & macros';
    if (proposal.isFoodLog) return '$kindLabel · Food entries';
    if (proposal.isFoodLogRevision) return kindLabel;
    final n = proposal.exerciseCount;
    final ex = '$n exercise${n == 1 ? '' : 's'}';
    return '$kindLabel · $ex';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = proposalKindTint(proposal);

    return Semantics(
      container: true,
      button: true,
      label: '${proposal.templateName}. ${_meta()}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: isBusy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    proposalKindIcon(proposal),
                    size: 20,
                    color: tint,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
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
                        isStale
                            ? 'Template changed — needs re-propose'
                            : _meta(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isStale
                              ? AppColors.accentWarningAmber
                              : colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isStale ? Icons.error_outline : Icons.chevron_right,
                    size: 20,
                    color: isStale
                        ? AppColors.accentWarningAmber
                        : colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
