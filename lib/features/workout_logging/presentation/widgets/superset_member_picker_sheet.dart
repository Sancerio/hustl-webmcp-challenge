import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';
import '../../domain/models/workout_exercise.dart';

/// Lightweight picker that lets the lifter link one or more other in-session
/// exercises into a superset. Used both when creating a group from an ungrouped
/// exercise ("Superset" chip) and when adding members to an existing group
/// ("Add another"). Returns the selected exercise ids, or null on cancel.
///
/// [title] is the sheet heading. [confirmLabel] is the idle/min-selection CTA
/// label; once enough are selected the CTA reflects a count using [confirmVerb]
/// (e.g. "Group 3 exercises"). [countOffset] is added to the selection size to
/// form that count: the "create" flow forms a group that also includes the
/// originating exercise, so it passes 1 ("Group 3" for two picks); the "add"
/// flow just adds the picks, so it passes 0 ("Add 2"). [minSelection] is how
/// many picks the action needs before it enables.
Future<List<String>?> showSupersetMemberPicker(
  BuildContext context, {
  required List<WorkoutExercise> candidates,
  required String title,
  required String confirmLabel,
  String confirmVerb = 'Group',
  int countOffset = 1,
  int minSelection = 1,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _SupersetMemberPickerSheet(
        candidates: candidates,
        title: title,
        confirmLabel: confirmLabel,
        confirmVerb: confirmVerb,
        countOffset: countOffset,
        minSelection: minSelection,
      );
    },
  );
}

class _SupersetMemberPickerSheet extends StatefulWidget {
  const _SupersetMemberPickerSheet({
    required this.candidates,
    required this.title,
    required this.confirmLabel,
    required this.confirmVerb,
    required this.countOffset,
    required this.minSelection,
  });

  final List<WorkoutExercise> candidates;
  final String title;
  final String confirmLabel;
  final String confirmVerb;
  final int countOffset;
  final int minSelection;

  @override
  State<_SupersetMemberPickerSheet> createState() =>
      _SupersetMemberPickerSheetState();
}

class _SupersetMemberPickerSheetState
    extends State<_SupersetMemberPickerSheet> {
  final Set<String> _selected = <String>{};

  void _toggle(String id) {
    Haptics.selection();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final count = _selected.length;
    final canConfirm = count >= widget.minSelection;
    // The CTA count: for "Group" this is the resulting group size (picks plus
    // the originating exercise); for "Add" it is just the picks.
    final ctaCount = count + widget.countOffset;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.x3,
          right: AppSpacing.x3,
          top: AppSpacing.x1 + 2,
          bottom: mediaQuery.viewInsets.bottom + AppSpacing.x2,
        ),
        child: ResponsiveCenter(
          maxContentWidth: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              // --- Header: icon chip + title + helper, tight rhythm ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: AppRadius.controlRadius,
                    ),
                    child: Icon(
                      Icons.link_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1 + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'Pick the exercises to perform back-to-back with '
                          'this one.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2 + 4),
              if (widget.candidates.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.x1 + 4),
                      Expanded(
                        child: Text(
                          'Add another exercise to the workout first, then '
                          'group them.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: mediaQuery.size.height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: widget.candidates.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.x1),
                    itemBuilder: (context, index) {
                      final candidate = widget.candidates[index];
                      return _MemberTile(
                        key: ValueKey('superset-pick-${candidate.id}'),
                        candidate: candidate,
                        selected: _selected.contains(candidate.id),
                        onTap: () => _toggle(candidate.id),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.x3),
              // --- Primary CTA: reflects the resulting group size ---
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('superset-picker-confirm'),
                  onPressed: canConfirm
                      ? () {
                          Haptics.confirm();
                          context.pop(_selected.toList());
                        }
                      : null,
                  child: Text(
                    canConfirm
                        ? '${widget.confirmVerb} $ctaCount exercises'
                        : widget.confirmLabel,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single polished, full-row-tappable exercise row. The name is the hero, the
/// muscles ride alongside as quiet secondary text, and the selected state is a
/// crisp accent fill + check — mirroring the warm-up planner's rung tile rather
/// than a stock checkbox.
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final WorkoutExercise candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muscles = candidate.exercise.muscles;
    final selectedColor = colors.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: candidate.exercise.name,
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.enterCurve,
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.10)
              : colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.55)
                : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.cardRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 + 4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.exercise.name,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (muscles.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            muscles.join(', '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  // Crisp selected state: accent fill + check, not a checkbox.
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.enterCurve,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? selectedColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? selectedColor : colors.outline,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: colors.onPrimary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
