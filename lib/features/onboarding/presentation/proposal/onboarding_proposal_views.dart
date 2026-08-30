import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';

/// Resting-card surface shared by the magic-moment views.
BoxDecoration proposalCard(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colors.surfaceContainerHigh,
    borderRadius: AppRadius.cardRadius,
    boxShadow: [AppShadows.subtle(context)],
  );
}

/// A centered hero crest (auto-awesome in a soft primary disc) + a title and
/// subtitle. Reused at the top of the consent gate and the ready state.
class ProposalHero extends StatelessWidget {
  const ProposalHero({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 30,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// The consent step. HONEST copy: this is a first-party draft from the user's
/// OWN logs — there is no external grant to revoke. Nothing changes until the
/// user approves.
class ProposalConsentGate extends StatelessWidget {
  const ProposalConsentGate({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.x3),
      children: [
        const ProposalHero(
          title: 'Let your coach draft a plan',
          subtitle:
              'Your coach can turn what you’ve logged into a starter plan you '
              'can approve in one tap.',
        ),
        const SizedBox(height: AppSpacing.x3),
        Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: proposalCard(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: AppColors.accentEmeraldGreen,
              ),
              const SizedBox(width: AppSpacing.x1 + 4),
              Expanded(
                child: Text(
                  'Your coach drafts this from your own logs — your workouts, '
                  'nutrition, and health metrics. Nothing changes until you '
                  'approve.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        FilledButton.icon(
          onPressed: onAccept,
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Draft my plan'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.controlRadius,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        TextButton(onPressed: onDecline, child: const Text('Not now')),
      ],
    );
  }
}

/// An expandable "Why this?" — the anti-black-box detail behind the proposal,
/// built from the proposal's OWN rationale (never fabricated specifics).
class ProposalWhyThis extends StatelessWidget {
  const ProposalWhyThis({super.key, required this.proposal});

  final ProposalDetail proposal;

  List<String> _reasons() {
    final reasons = <String>[];
    final description = proposal.description?.trim();
    if (description != null && description.isNotEmpty) reasons.add(description);
    final rationale = proposal.proposedNutrition?.rationale?.trim();
    if (rationale != null && rationale.isNotEmpty) reasons.add(rationale);
    if (reasons.isEmpty) {
      reasons.add('Built from the sessions and goals you’ve logged so far.');
    }
    return reasons;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.x1),
        leading: Icon(Icons.insights_rounded, size: 20, color: colors.primary),
        title: Text(
          'Why this?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final reason in _reasons())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The "improving estimate" honesty line — sets the expectation that this is a
/// first read that sharpens with more data.
class ProposalImprovingEstimateNote extends StatelessWidget {
  const ProposalImprovingEstimateNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.trending_up_rounded,
          size: 16,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'This is your coach’s best read so far — it sharpens every time you '
            'log.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// A simple full-screen status view (loading / not-enough-data / error /
/// success) with up to two actions. Never dead-ends.
class ProposalStatusView extends StatelessWidget {
  const ProposalStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.12),
              ),
              child: busy
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(icon, size: 30, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (primaryLabel != null) ...[
              const SizedBox(height: AppSpacing.x3),
              FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(220, 48),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.controlRadius,
                  ),
                ),
                child: Text(primaryLabel!),
              ),
            ],
            if (secondaryLabel != null) ...[
              const SizedBox(height: AppSpacing.x1),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
