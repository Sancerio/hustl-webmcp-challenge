part of 'body_score_screen.dart';

class _OtherRegionCallout extends StatelessWidget {
  const _OtherRegionCallout({required this.exercises});

  final List<_ExerciseContribution> exercises;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x1 + 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: AppRadius.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exercises mapped to Other',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Update these exercises with a primary muscle to move them into a specific region.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final exercise in exercises)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    '${exercise.name} · '
                    '${NumberFormatUtil.formatDouble(exercise.volume, decimalDigits: 1)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.rangeLabel});

  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return ScreenEmptyState(
      icon: Icons.insights_outlined,
      assetIcon: 'assets/icons/empty_chart.svg',
      title: 'Your balance score starts here',
      message:
          'Log a workout during $rangeLabel and we will map your training '
          'across every muscle region.',
      actionLabel: 'Log a workout',
      onAction: () => context.go('/'),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.errorContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => onRetry(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase 2 (training-balance revamp): the collapsible "Trends & detail" section
/// the radar / heat map / 0-100 evenness score / 27-muscle granularity and the
/// 4-week trend strip are demoted into. The headline IA above answers the
/// user's question; this is the optional deep-dive, collapsed by default.
class _TrendsAndDetailSection extends StatelessWidget {
  const _TrendsAndDetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: AppSpacing.x1),
        title: Text(
          'Trends & detail',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Radar, heat map, evenness score & 4-week trend',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ],
      ),
    );
  }
}
