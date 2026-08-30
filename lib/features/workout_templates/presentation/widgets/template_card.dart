import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../../../core/widgets/hustl_icon.dart';
import '../../../workout_templates/domain/models/workout_template.dart';
import 'template_glyph.dart';
import 'template_region.dart';

/// Wave I (Apple Fitness+ x MacroFactor): a premium template row that reads as
/// an object inside the host's grouped surface card. A soft circular holder —
/// tinted by the routine's most-trained muscle group so push / pull / legs read
/// distinctly — leads the sentence-case name, a quiet tabular meta line
/// ("N exercises · M sets"), and the description as a muted one-line subtitle —
/// closed by a kept overflow menu and a chevron affordance. No card chrome
/// lives here; the host wraps the group.
class TemplateCard extends StatelessWidget {
  final WorkoutTemplate template;

  /// The routine's most-trained muscle group (resolved from its exercises by the
  /// host), used to tint the leading holder. Null → a neutral tint.
  final TemplateRegion? region;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const TemplateCard({
    super.key,
    required this.template,
    this.region,
    this.onTap,
    this.onStart,
    this.onEdit,
    this.onDelete,
  });

  int get _exerciseCount => template.exercises
      .map((e) => (e['exerciseId'] as String?) ?? '')
      .where((s) => s.isNotEmpty)
      .length;

  int get _setCount => template.exercises.fold<int>(
    0,
    (sum, e) => sum + ((e['sets'] as int?) ?? 0),
  );

  /// A soft circular holder tinted by the routine's most-trained muscle group, with
  /// a workout-type glyph — so push / pull / legs read distinctly by colour
  /// while staying calm and scannable.
  Widget _buildLeading(ColorScheme colors) {
    final tint = templateRegionColor(region, colors);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Center(
        child: HustlIcon(
          asset: templateGlyphAsset(template.name),
          size: 22,
          color: tint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasMenu = onStart != null || onEdit != null || onDelete != null;
    final isTappable = onTap != null || onStart != null;
    final description = template.description.trim();
    final exerciseCount = _exerciseCount;
    final setCount = _setCount;

    return InkWell(
      onTap: onTap ?? onStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildLeading(colors),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  _MetaLine(exerciseCount: exerciseCount, setCount: setCount),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (hasMenu)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
                tooltip: 'Template actions',
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  switch (value) {
                    case 'start':
                      onStart?.call();
                    case 'edit':
                      onEdit?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onStart != null)
                    const PopupMenuItem(
                      value: 'start',
                      child: Text('Start workout'),
                    ),
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            if (isTappable) ...[
              const SizedBox(width: AppSpacing.x1 - 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The quiet meta strip beneath a template name: tabular exercise + set counts
/// joined by a middot, rendered in the 12px caption voice.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.exerciseCount, required this.setCount});

  final int exerciseCount;
  final int setCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabular = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final exerciseLabel = exerciseCount == 1 ? 'exercise' : 'exercises';

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$exerciseCount', style: tabular),
          TextSpan(text: ' $exerciseLabel', style: theme.textTheme.bodySmall),
          if (setCount > 0) ...[
            TextSpan(text: '  ·  ', style: theme.textTheme.bodySmall),
            TextSpan(text: '$setCount', style: tabular),
            TextSpan(text: ' sets', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
