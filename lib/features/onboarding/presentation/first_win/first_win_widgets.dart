import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';

/// Shared premium surface for the first-win summary cards — the app's resting-
/// card treatment: surface-ladder fill + a subtle soft shadow + card radius, no
/// hard border.
BoxDecoration firstWinCard(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colors.surfaceContainerHigh,
    borderRadius: AppRadius.cardRadius,
    boxShadow: [AppShadows.subtle(context)],
  );
}

/// A premium stat tile — raised surface, a tabular emphasized numeral, a quiet
/// caption. Used for the summary stat row.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.x2,
        horizontal: AppSpacing.x1,
      ),
      decoration: firstWinCard(context),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.metricEmphasis(context)),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A static PREVIEW of the starter plan the coach will draft next. Intentionally
/// non-interactive and number-free: the real AI proposal (with concrete sessions
/// + targets) lands in a later phase. It carries the recurring "based on:"
/// lineage so the upcoming plan reads as earned from today's session, not a
/// black box.
class StarterPlanPreviewCard extends StatelessWidget {
  const StarterPlanPreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: firstWinCard(context),
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
              const _PreviewBadge(label: 'Preview'),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          const _PreviewRow(
            icon: Icons.fitness_center_rounded,
            title: 'Your next session',
            subtitle: 'Tuned to the lifts you just logged.',
          ),
          const SizedBox(height: AppSpacing.x2),
          const _PreviewRow(
            icon: Icons.local_fire_department_rounded,
            title: 'Nutrition targets',
            subtitle: 'Set once your goal is in — then they adapt.',
          ),
          const SizedBox(height: AppSpacing.x2),
          _LineageRow(
            text: 'Based on your first logged session',
            color: colors.primary,
          ),
        ],
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 18, color: colors.primary),
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
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// The recurring signature trust mark — every proposal shows its inputs. A quiet
/// inline line (not a loud bordered pill).
class _LineageRow extends StatelessWidget {
  const _LineageRow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.insights_rounded, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A simple rounded placeholder used by the loading skeletons. Decorative.
class FirstWinSkeletonBox extends StatelessWidget {
  const FirstWinSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.shape = BoxShape.rectangle,
  });

  final double height;
  final double? width;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: shape,
          borderRadius: shape == BoxShape.circle ? null : AppRadius.cardRadius,
        ),
      ),
    );
  }
}
