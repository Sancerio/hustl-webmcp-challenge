import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/workout_minimize_intent.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../workout_logging/domain/utils/effort_scale.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/text_format.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';
import '../../data/services/template_sync_service.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/repositories/template_repository.dart';

class TemplateDetailScreen extends StatefulWidget {
  const TemplateDetailScreen({
    super.key,
    required this.templateId,
    this.startInEditMode = false,
  });

  final String templateId;
  final bool startInEditMode;

  @override
  State<TemplateDetailScreen> createState() => _TemplateDetailScreenState();
}

class _TemplateDetailScreenState extends State<TemplateDetailScreen> {
  final _templateRepository = GetIt.instance<TemplateRepository>();
  TemplateSyncService? get _syncService =>
      GetIt.I.isRegistered<TemplateSyncService>()
      ? GetIt.I<TemplateSyncService>()
      : null;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  WorkoutTemplate? _template;
  List<Map<String, dynamic>> _exerciseDrafts = const [];
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.startInEditMode;
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _loadTemplate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _loading = true);
    try {
      if (_syncService != null) {
        try {
          await _syncService!.syncNow();
        } catch (_) {
          // Fall back to local cache.
        }
      }
      final template = await _templateRepository.getWorkoutTemplate(
        widget.templateId,
      );
      if (!mounted) return;
      _template = template;
      if (template != null) {
        _nameController.text = template.name;
        _descriptionController.text = template.description;
        _exerciseDrafts = _cloneExercises(template.exercises);
      }
      setState(() => _loading = false);
    } catch (e, s) {
      dev.log(
        'Failed to load template',
        name: 'TemplateDetailScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      HustlSnack.show(
        context,
        'We couldn\'t load this template. Please try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  List<Map<String, dynamic>> _cloneExercises(List<dynamic> source) {
    return source.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      final previousSets = (map['previousSets'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((set) => Map<String, dynamic>.from(set))
          .toList();
      map['previousSets'] = previousSets;
      map['_templateDraftId'] =
          map['_templateDraftId']?.toString() ??
          'template-exercise-${widget.templateId}-${DateTime.now().microsecondsSinceEpoch}-${map['exerciseId'] ?? 'exercise'}';
      return map;
    }).toList();
  }

  int _setCount(Map<String, dynamic> exercise) =>
      math.max(1, (exercise['sets'] as int?) ?? 1);

  int? _targetRpe(Map<String, dynamic> exercise) {
    final previousSets = exercise['previousSets'] as List<dynamic>? ?? const [];
    final first = previousSets.isNotEmpty ? previousSets.first : null;
    if (first is Map<String, dynamic>) {
      return first['rpe'] as int?;
    }
    if (first is Map) {
      return first['rpe'] as int?;
    }
    return null;
  }

  int? _restSeconds(Map<String, dynamic> exercise) =>
      (exercise['restTimerSeconds'] as int?);

  String _exerciseSummary(Map<String, dynamic> exercise) {
    final parts = <String>['${_setCount(exercise)} sets'];
    final previousSets = exercise['previousSets'] as List<dynamic>? ?? const [];
    final reps = previousSets
        .whereType<Map>()
        .map((set) => set['reps'])
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    if (reps.isNotEmpty) {
      final uniqueReps = reps.toSet().toList()..sort();
      parts.add(
        uniqueReps.length == 1
            ? '${uniqueReps.first} reps'
            : 'reps ${reps.join('/')}',
      );
    }
    final restSeconds = _restSeconds(exercise);
    if (restSeconds != null && restSeconds > 0) {
      final minutes = restSeconds ~/ 60;
      final seconds = restSeconds % 60;
      parts.add(
        seconds == 0 ? '${minutes}m rest' : '${minutes}m ${seconds}s rest',
      );
    }
    final rir = EffortScale.rirLabelFromRpe(_targetRpe(exercise));
    if (rir != null) {
      parts.add('RIR $rir');
    }
    return parts.join(' · ');
  }

  Future<void> _addExercise() async {
    // Reuse the app's standard exercise picker (search, filters, custom-create,
    // multi-select) so the template editor matches the rest of the app instead
    // of a bespoke sheet. It pops a [WorkoutExercise] on single tap / custom
    // create, or a `List<WorkoutExercise>` on multi-select; convert each into
    // the template's starter draft Map so downstream behaviour is unchanged.
    final picked = await context.push<Object?>('/exercise_select');
    if (picked == null || !mounted) return;
    final exercises = picked is List
        ? picked.cast<WorkoutExercise>()
        : <WorkoutExercise>[picked as WorkoutExercise];
    if (exercises.isEmpty) return;
    setState(() {
      _exerciseDrafts = [
        ..._exerciseDrafts,
        for (final exercise in exercises)
          _defaultExerciseDraft(exercise.exercise.name),
      ];
    });
  }

  /// A fresh template-exercise draft for [name] with a starter 3 x 8 @ 90s rest
  /// prescription, in the Map shape `_exerciseDrafts` persists. Set ids embed
  /// the exercise name so a multi-select batch can't collide within a tick.
  Map<String, dynamic> _defaultExerciseDraft(String name) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return {
      '_templateDraftId': 'template-exercise-$stamp-$name',
      'exerciseId': name,
      'sets': 3,
      'restTimerSeconds': 90,
      // Provenance: a generic in-app 3×8 @ 0 placeholder, NOT an authored
      // target. Persisted with the template so a workout started from it can
      // fall back to the user's real last session instead of pinning "0 kg".
      'targetsArePlaceholder': true,
      'previousSets': [
        for (var i = 1; i <= 3; i++)
          {
            'id': 'template-set-$stamp-$name-$i',
            'weight': 0.0,
            'reps': 8,
            'rpe': 8,
            'setType': 'regular',
            'notes': null,
            'isCompleted': false,
            'completedAt': null,
            'isPr': false,
          },
      ],
    };
  }

  Future<void> _editExercise(int index) async {
    final exercise = _exerciseDrafts[index];
    final restController = TextEditingController(
      text: (_restSeconds(exercise) ?? 90).toString(),
    );
    final setDrafts = _cloneSetDrafts(
      exercise['previousSets'] as List<dynamic>? ?? const [],
    );
    try {
      // Use a DraggableScrollableSheet instead of AlertDialog (no overflow on phones).
      final updatedSets =
          await showModalBottomSheet<List<Map<String, dynamic>>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _TemplateExerciseEditorSheet(
              exerciseName: formatExerciseName(
                exercise['exerciseId'] as String? ?? '',
              ),
              restController: restController,
              initialSets: setDrafts,
            ),
          );
      if (updatedSets == null) return;

      final rest = math.max(15, int.tryParse(restController.text.trim()) ?? 90);
      final updated = Map<String, dynamic>.from(exercise);
      updated['sets'] = updatedSets.length;
      updated['restTimerSeconds'] = rest;
      updated['previousSets'] = updatedSets;
      // The user has now authored these targets (reps / RIR / set count), so
      // they are no longer a generic placeholder. The active workout still
      // treats all-zero template targets as prescriptions and prefers real
      // previous-session history for the Previous column when available.
      updated['targetsArePlaceholder'] = false;
      setState(() {
        _exerciseDrafts[index] = updated;
      });
    } finally {
      restController.dispose();
    }
  }

  List<Map<String, dynamic>> _cloneSetDrafts(List<dynamic> source) {
    final copied = source
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    if (copied.isNotEmpty) return copied;
    return [_newSetDraft()];
  }

  Map<String, dynamic> _newSetDraft() => {
    'id':
        'template-set-${widget.templateId}-${DateTime.now().microsecondsSinceEpoch}',
    'weight': 0.0,
    'reps': 8,
    'rpe': 8,
    'setType': 'regular',
    'notes': null,
    'isCompleted': false,
    'completedAt': null,
    'isPr': false,
  };

  Future<void> _saveTemplate() async {
    final template = _template;
    if (template == null) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      HustlSnack.show(
        context,
        'Please give your template a name.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = template.copyWith(
        name: newName,
        description: _descriptionController.text.trim(),
        exercises: _exerciseDrafts.map((exercise) {
          final cleaned = Map<String, dynamic>.from(exercise);
          cleaned.removeWhere((key, _) => key.startsWith('_'));
          return cleaned;
        }).toList(),
        updatedAt: DateTime.now(),
      );
      final saved = await _templateRepository.updateWorkoutTemplate(updated);
      if (GetIt.I.isRegistered<TemplateSyncService>()) {
        await GetIt.I<TemplateSyncService>().syncNow();
      }
      if (!mounted) return;
      setState(() {
        _template = saved;
        _editing = false;
        _saving = false;
      });
      HustlSnack.show(
        context,
        'Template saved.',
        variant: HustlSnackVariant.success,
      );
    } catch (e, s) {
      dev.log(
        'Failed to save template',
        name: 'TemplateDetailScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      HustlSnack.show(
        context,
        'We couldn\'t save your template. Please try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  void _startWorkout() {
    final template = _template;
    if (template == null || _editing) return;
    final extra = {
      'initialName': template.name,
      // Pass the template's stored prescription sets with provenance so the
      // active workout can keep "Previous" tied to actual session history.
      'initialExercises': _exerciseDrafts
          .map(
            (e) => {
              'name': e['exerciseId'] as String? ?? '',
              'sets': (e['sets'] as int?) ?? 1,
              'rest': e['restTimerSeconds'] as int?,
              'previousSets': e['previousSets'] as List<dynamic>?,
              'previousSetsAreTemplateTargets': true,
              // Provenance: template prescription targets are separate from
              // true previous-session history.
              'targetsArePlaceholder': e['targetsArePlaceholder'] == true,
            },
          )
          .toList(),
    };
    context.go('/workout_session', extra: workoutRouteExtra(context, extra));
  }

  Widget _buildHeader(ThemeData theme, WorkoutTemplate template) {
    final colors = theme.colorScheme;
    final totalSets = _exerciseDrafts.fold<int>(
      0,
      (sum, item) => sum + _setCount(item),
    );
    // Wave I: a grouped summary card carries the name, quiet meta line and a
    // real blue "Start workout" CTA; a sentence-case SectionHeader introduces
    // the exercises list. The edit form keeps the plain fields.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Template name'),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '${_exerciseDrafts.length} exercises · $totalSets sets',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit exercises'.toUpperCase(),
                    style: AppTextStyles.sectionHeader(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
          ] else ...[
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(AppSpacing.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name, style: theme.textTheme.titleLarge),
                  if (template.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      template.description,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '${_exerciseDrafts.length} exercises · $totalSets sets',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exerciseDrafts.isEmpty ? null : _startWorkout,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start workout'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              'Exercises',
              padding: EdgeInsets.only(bottom: AppSpacing.x1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseRow(
    ThemeData theme,
    Map<String, dynamic> exercise,
    int index, {
    bool editable = false,
  }) {
    final name = exercise['exerciseId'] as String? ?? '';
    // §12.4: flat divider rows — name 15/w500, 12px meta. The host list
    // supplies the hairline dividers between rows.
    return Column(
      key: ValueKey(exercise['_templateDraftId'] ?? '$name-$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          // Tap the row itself to edit targets, so the standalone "tune" icon
          // can go — leaving just a calm delete + drag handle on the right.
          onTap: editable ? () => _editExercise(index) : null,
          leading: _exerciseLeading(theme.colorScheme),
          title: Text(
            formatExerciseName(name),
            style: theme.textTheme.bodyLarge,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _exerciseSummary(exercise),
              style: theme.textTheme.bodySmall,
            ),
          ),
          trailing: editable
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Remove exercise',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _exerciseDrafts.removeAt(index);
                      }),
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_indicator,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ],
    );
  }

  /// A read-only exercise tile sized to sit inside a grouped [SectionList]
  /// card — the host supplies the hairline dividers and the card inset.
  Widget _buildExerciseTile(ThemeData theme, Map<String, dynamic> exercise) {
    final name = exercise['exerciseId'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _exerciseLeading(theme.colorScheme),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatExerciseName(name),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  _exerciseSummary(exercise),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A soft, brand-tinted circular holder with a dumbbell glyph — the same
  /// "Soft Holder" leading-visual language the templates list uses, giving every
  /// exercise row a calm, scannable anchor. The exercise drafts carry no muscle
  /// signal here, so the tint stays a neutral brand accent rather than per-region.
  Widget _exerciseLeading(ColorScheme colors) {
    final tint = colors.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Center(
        child: HustlIcon(
          asset: 'assets/icons/ic_dumbbell.svg',
          size: 20,
          color: tint,
        ),
      ),
    );
  }

  void _returnToTemplates() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // A web list-to-detail handoff uses `go` so the canonical detail owns the
    // browser URL. Replace that history entry on Back; adding another entry
    // would make the browser Back button reopen the detail that just closed.
    Router.neglect(context, () => context.go('/templates'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = _template;

    return MainScaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : BackButton(onPressed: _returnToTemplates),
        title: Text(template?.name ?? 'Template'),
        actions: [
          if (template != null && !_editing)
            IconButton(
              tooltip: 'Start workout',
              onPressed: _startWorkout,
              icon: const Icon(Icons.play_arrow),
            ),
          if (template != null)
            IconButton(
              tooltip: _editing ? 'Save template' : 'Edit template',
              onPressed: _saving
                  ? null
                  : (_editing
                        ? _saveTemplate
                        : () => setState(() => _editing = true)),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            ),
        ],
      ),
      child: _loading
          ? const HustlInlineSkeleton()
          : template == null
          ? ScreenEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Template not found',
              message: "It may have been deleted or hasn't synced yet.",
              actionLabel: 'Back to templates',
              onAction: _returnToTemplates,
            )
          : _editing
          ? ReorderableListView.builder(
              padding: EdgeInsets.zero,
              buildDefaultDragHandles: false,
              header: _buildHeader(theme, template),
              footer: _exerciseDrafts.isEmpty
                  ? _TemplateEmptyExercisesCard(
                      title: 'Add your first movement',
                      message:
                          'Pick exercises from the library and set your '
                          'targets — they will build out this template.',
                      actionLabel: 'Add exercise',
                      onAction: _addExercise,
                    )
                  : const SizedBox(height: AppSpacing.x3),
              itemCount: _exerciseDrafts.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _exerciseDrafts.removeAt(oldIndex);
                  _exerciseDrafts.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) => _buildExerciseRow(
                theme,
                _exerciseDrafts[index],
                index,
                editable: true,
              ),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildHeader(theme, template),
                if (_exerciseDrafts.isEmpty)
                  _TemplateEmptyExercisesCard(
                    title: 'No exercises here yet',
                    message:
                        'Add a few movements to this template so it is ready '
                        'to start whenever you are.',
                    actionLabel: 'Add exercises',
                    onAction: () => setState(() => _editing = true),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SectionList(
                      card: true,
                      children: [
                        for (final exercise in _exerciseDrafts)
                          _buildExerciseTile(theme, exercise),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

/// Inviting empty-exercises card for the template detail screen. Mirrors the
/// shared [ScreenEmptyState] voice — a soft blue-tinted icon holder, a
/// confident sentence-case headline, one supportive line and a single blue
/// CTA — but stays inline so it reads as a friendly section rather than a
/// full-screen takeover inside the scrolling list.
class _TemplateEmptyExercisesCard extends StatelessWidget {
  const _TemplateEmptyExercisesCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.12),
              ),
              child: HustlIcon(
                asset: 'assets/icons/empty_workout.svg',
                size: 36,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
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
            const SizedBox(height: AppSpacing.x3),
            FilledButton.icon(
              onPressed: onAction,
              icon: HustlIcon(
                asset: 'assets/icons/ic_add.svg',
                size: 18,
                color: colors.onPrimary,
              ),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.controlRadius,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DraggableScrollableSheet-based set editor — replaces the hard-coded 520px
/// AlertDialog that overflowed on phones. Uses [AppRadius.sheet] for the top
/// corners so it matches the rest of the app's modal bottom sheets.
class _TemplateExerciseEditorSheet extends StatefulWidget {
  const _TemplateExerciseEditorSheet({
    required this.exerciseName,
    required this.restController,
    required this.initialSets,
  });

  final String exerciseName;
  final TextEditingController restController;
  final List<Map<String, dynamic>> initialSets;

  @override
  State<_TemplateExerciseEditorSheet> createState() =>
      _TemplateExerciseEditorSheetState();
}

class _TemplateExerciseEditorSheetState
    extends State<_TemplateExerciseEditorSheet> {
  late List<_TemplateSetDraft> _sets;

  @override
  void initState() {
    super.initState();
    _sets = widget.initialSets
        .map((set) => _TemplateSetDraft.fromMap(set))
        .toList();
  }

  @override
  void dispose() {
    for (final set in _sets) {
      set.dispose();
    }
    super.dispose();
  }

  void _addSet() {
    setState(() {
      _sets.add(
        _TemplateSetDraft(
          id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
          reps: 8,
          rpe: 8,
          setType: 'regular',
          notes: null,
          weight: 0.0,
        ),
      );
    });
  }

  void _removeSet(int index) {
    if (_sets.length == 1) return;
    setState(() {
      final removed = _sets.removeAt(index);
      removed.dispose();
    });
  }

  List<Map<String, dynamic>> _buildResult() {
    return List<Map<String, dynamic>>.generate(_sets.length, (index) {
      final set = _sets[index];
      return {
        'id': set.id,
        'weight': set.weight,
        'reps': math.max(1, int.tryParse(set.repsController.text.trim()) ?? 1),
        // Field is RIR (0–6); persist as RPE = 10 − RIR.
        'rpe': EffortScale.rpeFromRir(
          int.tryParse(
            set.rpeController.text.trim(),
          )?.clamp(0, EffortScale.maxRir),
        ),
        'setType': set.setType,
        'notes': set.notes,
        'isCompleted': false,
        'completedAt': null,
        'isPr': false,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (sheetContext, scrollController) => Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.exerciseName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  // Rest seconds field
                  TextField(
                    controller: widget.restController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Rest seconds',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Sets', style: AppTextStyles.sectionHeader(context)),
                  const SizedBox(height: 8),
                  ...List.generate(_sets.length, (index) {
                    final set = _sets[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              'Set ${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: set.repsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Reps',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: set.rpeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'RIR',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove set',
                            onPressed: _sets.length == 1
                                ? null
                                : () => _removeSet(index),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: _addSet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add set'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // Bottom save button
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              child: FilledButton(
                onPressed: () => context.pop(_buildResult()),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateSetDraft {
  _TemplateSetDraft({
    required this.id,
    required int reps,
    required int? rpe,
    required this.setType,
    required this.notes,
    required this.weight,
  }) : repsController = TextEditingController(text: reps.toString()),
       // Field shows RIR; the stored target is RPE (RIR 2 ≡ RPE 8 default).
       rpeController = TextEditingController(
         text: (EffortScale.rirFromRpe(rpe) ?? 2).toString(),
       );

  factory _TemplateSetDraft.fromMap(Map<String, dynamic> map) {
    return _TemplateSetDraft(
      id: map['id']?.toString() ?? 'draft',
      reps: (map['reps'] as int?) ?? 8,
      rpe: map['rpe'] as int?,
      setType: map['setType']?.toString() ?? 'regular',
      notes: map['notes']?.toString(),
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final String id;
  final String setType;
  final String? notes;
  final double weight;
  final TextEditingController repsController;
  final TextEditingController rpeController;

  void dispose() {
    repsController.dispose();
    rpeController.dispose();
  }
}
