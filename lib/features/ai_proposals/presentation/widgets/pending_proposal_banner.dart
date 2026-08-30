import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../services/proposal_events_service.dart';

/// A compact global banner that appears when there are pending AI proposals.
/// Tapping it opens the inbox. Mirrors `ActiveWorkoutBanner` (mounted above the
/// bottom nav in `app_shell.dart`), but is driven entirely by the
/// `ValueNotifier<int>` on [ProposalEventsService] — so it costs nothing when
/// the count is zero and updates reactively on poll/approve/reject.
class PendingProposalBanner extends StatelessWidget {
  const PendingProposalBanner({super.key, this.includeBottomSafeArea = true});

  final bool includeBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final events = GetIt.instance.isRegistered<ProposalEventsService>()
        ? GetIt.instance<ProposalEventsService>()
        : null;
    if (events == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: events.pendingCount,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        final label = count == 1
            ? '1 change to review'
            : '$count changes to review';
        return SafeArea(
          top: false,
          bottom: includeBottomSafeArea,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              0,
              AppSpacing.x2,
              AppSpacing.x1,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.cardRadius,
                boxShadow: [AppShadows.medium(context)],
              ),
              child: InkWell(
                borderRadius: AppRadius.cardRadius,
                onTap: () => context.push('/proposals'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x1 + 2,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_awesome_outlined,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI proposals',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.push('/proposals'),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
