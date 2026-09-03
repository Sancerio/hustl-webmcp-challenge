import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/text_format.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../workout_templates/domain/models/workout_template.dart';
import '../../domain/models/proposal_detail.dart';
import 'proposal_exercise_tile.dart';

/// Classification of a diff row.
enum _DiffKind { add, change, remove, unchanged }

class _DiffRow {
  const _DiffRow(this.kind, this.exercise, {this.label});
  final _DiffKind kind;
  final Map<String, dynamic> exercise;
  final String? label;
}

/// A diff for `template_edit` proposals. `exerciseId` is a free-text name with
/// no stable per-row id, so rows are keyed by (name, occurrence-index): the Nth
/// "Bench Press" in the proposal matches the Nth in the current template, so
/// duplicate names stay distinct instead of collapsing. Still lossy on
/// rename/reorder (acceptable for v1; the server is the authority). Tints rows
/// with `AppColors` (emerald=add, amber=change, muted=remove).
class ProposalDiffView extends StatelessWidget {
  const ProposalDiffView({
    super.key,
    required this.detail,
    required this.currentTemplate,
  });

  final ProposalDetail detail;

  /// The current template fetched via TemplateRepository (null if not found).
  final WorkoutTemplate? currentTemplate;

  List<_DiffRow> _computeRows() {
    final proposed = detail.renderExercises;
    final current = (currentTemplate?.exercises ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    String nameOf(Map<String, dynamic> e) =>
        (e['exerciseId'] as String? ?? '').trim().toLowerCase();

    // Key by (name, occurrence-index) so duplicate names stay distinct: the Nth
    // entry of a given name in the proposal matches the Nth in the current
    // template, instead of all duplicates collapsing onto the first.
    final seen = <String, int>{};
    String keyOf(Map<String, dynamic> e) {
      final name = nameOf(e);
      final i = seen[name] ?? 0;
      seen[name] = i + 1;
      return '$name#$i';
    }

    final currentByKey = {for (final e in current) keyOf(e): e};
    seen.clear();
    final proposedKeys = proposed.map(keyOf).toSet();
    seen.clear();

    final rows = <_DiffRow>[];
    for (final p in proposed) {
      final existing = currentByKey[keyOf(p)];
      if (existing == null) {
        rows.add(_DiffRow(_DiffKind.add, p, label: 'New'));
      } else if (_changed(existing, p)) {
        rows.add(_DiffRow(_DiffKind.change, p, label: 'Changed'));
      } else {
        rows.add(_DiffRow(_DiffKind.unchanged, p));
      }
    }
    seen.clear();
    // Removed: in current but not proposed.
    for (final e in current) {
      if (!proposedKeys.contains(keyOf(e))) {
        rows.add(_DiffRow(_DiffKind.remove, e, label: 'Removed'));
      }
    }
    return rows;
  }

  bool _changed(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = (a['sets'] as num?)?.toInt() ?? 0;
    final sb = (b['sets'] as num?)?.toInt() ?? 0;
    final ra = (a['restTimerSeconds'] as num?)?.toInt() ?? 0;
    final rb = (b['restTimerSeconds'] as num?)?.toInt() ?? 0;
    if (sa != sb || ra != rb) return true;
    // Approved targets live in previousSets[0] (reps/weight/rpe). A target-only
    // edit (no sets/rest change) must still flag as Changed on the trust
    // surface, so compare those too — read them exactly as the tile does.
    final fa = _firstSet(a);
    final fb = _firstSet(b);
    return _repsOf(fa) != _repsOf(fb) ||
        _weightOf(fa) != _weightOf(fb) ||
        _rpeOf(fa) != _rpeOf(fb) ||
        _notesOf(a) != _notesOf(b);
  }

  /// Notes are disclosed + applied, so a notes-only edit must flag Changed.
  /// Proposed exercises carry notes top-level (toRenderMap); saved templates
  /// carry them per-set — read either.
  String _notesOf(Map<String, dynamic> e) {
    final top = (e['notes'] as String?)?.trim();
    if (top != null && top.isNotEmpty) return top;
    return (_firstSet(e)?['notes'] as String?)?.trim() ?? '';
  }

  /// The first synthesized set Map (carries reps/weight/rpe), or null.
  Map<String, dynamic>? _firstSet(Map<String, dynamic> e) {
    final sets = e['previousSets'] as List<dynamic>? ?? const [];
    final first = sets.isNotEmpty ? sets.first : null;
    return first is Map ? Map<String, dynamic>.from(first) : null;
  }

  int _repsOf(Map<String, dynamic>? set) =>
      (set?['reps'] as num?)?.toInt() ?? 0;

  double _weightOf(Map<String, dynamic>? set) =>
      (set?['weight'] as num?)?.toDouble() ?? 0.0;

  int? _rpeOf(Map<String, dynamic>? set) => (set?['rpe'] as num?)?.toInt();

  Color _toneFor(_DiffKind kind, ColorScheme colors) {
    switch (kind) {
      case _DiffKind.add:
        return AppColors.accentEmeraldGreen;
      case _DiffKind.change:
        return AppColors.accentWarningAmber;
      case _DiffKind.remove:
        return colors.onSurfaceVariant;
      case _DiffKind.unchanged:
        return colors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = _computeRows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          currentTemplate == null ? 'Proposed exercises' : 'Proposed changes',
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        SectionList(
          card: true,
          children: [
            for (final row in rows)
              ProposalExerciseTile(
                exercise: row.exercise,
                tone: _toneFor(row.kind, colors),
                trailing: row.label == null
                    ? null
                    : AppChip(
                        label: row.label!,
                        variant: AppChipVariant.status,
                        color: _toneFor(row.kind, colors),
                      ),
              ),
          ],
        ),
      ],
    );
  }

  /// A standalone tap target outside this widget builds a labeled list of
  /// new-custom exercises from [detail.resolvedExercises].
  static Widget? resolvedSnapshot(
    BuildContext context,
    ProposalDetail detail, {
    bool terminal = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final newCustom = detail.resolvedExercises
        .where((r) => r.willCreateCustom)
        .toList();
    if (newCustom.isEmpty) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: AppColors.accentWarningAmber.withValues(alpha: 0.10),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: AppColors.accentWarningAmber.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New custom exercises',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            terminal
                ? 'These names did not match the catalog at proposal time and '
                      'were included as custom exercises.'
                : 'These names don\'t match the catalog as of when this was '
                      'proposed, so they\'ll be created as custom exercises.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          for (final r in newCustom)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${formatExerciseName(r.name)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'As of proposal time.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
