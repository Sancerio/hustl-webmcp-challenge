import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/models/proposed_food_log_revision.dart';

/// Renders a `food_log_edit` / `food_log_delete` proposal: the entry being revised,
/// and either the per-field before→after diff (edit) or a removal notice (delete).
/// Mirrors the food-log view's section/card language. Approving applies the change
/// (undoable); deleting removes the entry.
class ProposalFoodLogRevisionView extends StatelessWidget {
  const ProposalFoodLogRevisionView({
    super.key,
    required this.detail,
    this.terminal = false,
  });

  final ProposalDetail detail;
  final bool terminal;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final revision = detail.proposedFoodLogRevision;
    if (revision == null) return const SizedBox.shrink();

    final isDelete = revision.isDelete;
    final tint = isDelete
        ? AppColors.accentWarningAmber
        : AppColors.accentEmeraldGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(
          tint: tint,
          icon: isDelete ? Icons.delete_outline : Icons.edit_note_outlined,
          text: terminal
              ? isDelete
                    ? 'Proposed removal: "${revision.foodName}"'
                    : 'Proposed changes to "${revision.foodName}"'
              : isDelete
              ? 'Removes "${revision.foodName}" from your diary'
              : 'Updates "${revision.foodName}" in your diary',
        ),
        if (revision.date != null) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Logged ${_date(revision.date!)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.x2),
        if (isDelete)
          SectionList(
            card: true,
            children: [
              _DeleteRow(
                name: revision.foodName,
                calories: revision.currentCalories,
              ),
            ],
          )
        else ...[
          const SectionHeader(
            'Changes',
            padding: EdgeInsets.only(bottom: AppSpacing.x1),
          ),
          SectionList(
            card: true,
            children: [for (final c in revision.changes) _ChangeRow(change: c)],
          ),
        ],
        if (!terminal) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            isDelete
                ? 'Suggested by your assistant — undo right after approving if it '
                      'was wrong.'
                : 'Suggested by your assistant — undo right after approving, or edit '
                      'the entry from the diary.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.tint});

  final IconData icon;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final FoodFieldChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label takes a small share; the value column gets the rest so a long
          // rename (food names can be up to 200 chars) wraps onto multiple lines
          // instead of overflowing on a narrow phone.
          Expanded(
            flex: 2,
            child: Text(
              change.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(flex: 5, child: _value(theme, colors)),
        ],
      ),
    );
  }

  Widget _value(ThemeData theme, ColorScheme colors) {
    if (!change.changed) {
      return Text(
        change.from,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodyMedium,
      );
    }
    // from → to as wrapping rich text: stays on one line for short numeric values,
    // breaks across lines (right-aligned) for long values like a renamed food.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: change.from,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              child: Icon(
                Icons.arrow_forward,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          TextSpan(
            text: change.to,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.end,
    );
  }
}

class _DeleteRow extends StatelessWidget {
  const _DeleteRow({required this.name, this.calories});

  final String name;
  final double? calories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
          if (calories != null) ...[
            const SizedBox(width: AppSpacing.x1),
            Text(
              '${calories!.round()} kcal',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
