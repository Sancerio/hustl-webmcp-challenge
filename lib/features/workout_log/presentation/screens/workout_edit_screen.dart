import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../workout_logging/presentation/widgets/exercise_card.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';

class WorkoutEditScreen extends StatefulWidget {
  final String sessionId;

  const WorkoutEditScreen({super.key, required this.sessionId});

  @override
  State<WorkoutEditScreen> createState() => _WorkoutEditScreenState();
}

class _WorkoutEditScreenState extends State<WorkoutEditScreen> {
  final _repo = GetIt.instance<WorkoutRepository>();
  final _uuid = const Uuid();

  WorkoutSession? _session;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  WorkoutSession? _lastSaved; // snapshot to support undo after save
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await _repo.getWorkoutSession(widget.sessionId);
      if (!mounted) return;
      if (s == null) {
        setState(() {
          _loading = false;
          _loadError = 'Workout not found';
        });
        HustlSnack.show(
          context,
          'We couldn\'t find that workout.',
          variant: HustlSnackVariant.warning,
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/history');
        }
        return;
      }
      setState(() {
        _session = s;
        _lastSaved = s;
        _loading = false;
        _loadError = null;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Error loading workout: $e';
      });
      HustlSnack.show(
        context,
        'We couldn\'t load this workout. $e',
        variant: HustlSnackVariant.error,
      );
    }
  }

  Future<void> _save() async {
    if (_session == null) return;
    setState(() => _saving = true);
    try {
      final previous = _lastSaved;
      await _repo.updateWorkoutSession(_session!);
      // Recompute PR flags across history after edits
      await _repo.recomputeAllPrFlags();
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _lastSaved = _session!;
      });
      HustlSnack.show(
        context,
        'Workout saved.',
        variant: HustlSnackVariant.success,
        actionLabel: previous != null ? 'Undo' : null,
        onAction: previous != null
            ? () async {
                try {
                  await _repo.updateWorkoutSession(previous);
                  await _repo.recomputeAllPrFlags();
                  if (!mounted) return;
                  setState(() {
                    _session = previous;
                    _lastSaved = previous;
                    _dirty = false;
                  });
                  HustlSnack.show(
                    context,
                    'Changes reverted.',
                    variant: HustlSnackVariant.success,
                  );
                } catch (e) {
                  if (!mounted) return;
                  HustlSnack.show(
                    context,
                    'We couldn\'t undo that change. $e',
                    variant: HustlSnackVariant.error,
                  );
                }
              }
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'We couldn\'t save your workout. $e',
        variant: HustlSnackVariant.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateSession(WorkoutSession newSession) {
    setState(() {
      _session = newSession;
      _dirty = true;
    });
  }

  /// Confirms discarding unsaved edits before leaving the screen.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes. Leave without saving them?',
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted && context.canPop()) {
      context.pop();
    }
  }

  Future<void> _pickStart() async {
    if (_session == null) return;
    final dt = _session!.startTime;
    final date = await showDatePicker(
      context: context,
      initialDate: dt,
      firstDate: DateTime(2010),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dt),
    );
    if (time == null) return;
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final end = _session!.endTime;
    if (end != null && picked.isAfter(end)) {
      HustlSnack.show(
        context,
        'Start time can\'t be after the end time.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    _updateSession(_session!.copyWith(startTime: picked));
  }

  Future<void> _pickEnd() async {
    if (_session == null) return;
    final current = _session!.endTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: _session!.startTime,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(_session!.startTime)) {
      HustlSnack.show(
        context,
        'End time can\'t be before the start time.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    _updateSession(_session!.copyWith(endTime: picked));
  }

  Future<void> _addExercise() async {
    if (_session == null) return;
    final result = await context.push<WorkoutExercise>('/exercise_select');
    if (!mounted) return;
    if (result != null) {
      final updated = _session!.addExercise(result.copyWith(id: _uuid.v4()));
      _updateSession(updated);
    }
  }

  Future<void> _replaceExercise(String exerciseId) async {
    if (_session == null) return;
    final index = _session!.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) return;
    final original = _session!.exercises[index];
    final replacement = await context.push<WorkoutExercise>('/exercise_select');
    if (!mounted) return;
    if (replacement != null) {
      final updated = original.copyWith(
        exercise: replacement.exercise,
        // Keep existing sets to avoid accidental loss
        sets: original.sets,
      );
      final list = [..._session!.exercises];
      list[index] = updated;
      _updateSession(_session!.copyWith(exercises: list));
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date = DateFormat.yMMMd().format(local);
    final time = DateFormat.jm().format(local);
    return '$date • $time';
  }

  Widget _buildLoadError(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.x1 + 4),
              Text(
                _loadError ?? 'Unable to load workout.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.x2),
              Wrap(
                spacing: AppSpacing.x1 + 4,
                runSpacing: AppSpacing.x1 + 4,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/history'),
                    icon: const Icon(Icons.history),
                    label: const Text('History'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final appBar = AppBar(
      title: const Text('Edit workout'),
      centerTitle: true,
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      // Adaptive leading: a back button when pushed (the normal case, from the
      // summary screen), the account avatar at a root. Matches History /
      // Progress / Body Score rather than the bare Material BackButton.
      leading: const HustlMenuButton(),
      actions: [
        if (_dirty)
          IconButton(
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Icon(Icons.save, color: theme.colorScheme.primary),
          ),
      ],
    );

    if (_loading) {
      return MainScaffold(appBar: appBar, child: const HustlInlineSkeleton());
    }

    if (_session == null) {
      return MainScaffold(appBar: appBar, child: _buildLoadError(context));
    }

    final session = _session!;
    return PopScope(
      // Guard against losing unsaved edits on back/swipe.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: MainScaffold(
        appBar: appBar,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x2,
              AppSpacing.x4,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  // A stable Column (deliberately not StaggeredEntrance): this
                  // body holds live TextFormFields that setState on every
                  // keystroke. A staggered entrance swaps each child from an
                  // animated wrapper to a raw widget after its first play,
                  // reparenting the fields and dropping focus/selection
                  // mid-typing. Reliable text entry wins over a one-time
                  // flourish on an edit form.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: _buildSections(theme, session),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The body spine (Wave I): flat SectionHeader-titled groups —
  /// Details -> Notes -> Exercises — built from premium surface cards and
  /// tappable rows, no bordered one-offs.
  List<Widget> _buildSections(ThemeData theme, WorkoutSession session) {
    return [
      const SectionHeader('Details', padding: EdgeInsets.zero),
      const SizedBox(height: AppSpacing.x1),
      _GroupCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: session.name,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Workout name',
                hintText: 'Name this workout',
              ),
              onChanged: (v) => _updateSession(session.copyWith(name: v)),
            ),
            const SizedBox(height: AppSpacing.x2),
            _DateTimeRow(
              asset: 'assets/icons/ic_calendar.svg',
              label: 'Start',
              value: _formatDateTime(session.startTime),
              onTap: _pickStart,
            ),
            const Divider(),
            _DateTimeRow(
              asset: 'assets/icons/ic_timer.svg',
              label: 'End',
              value: _formatDateTime(session.endTime ?? DateTime.now()),
              onTap: _pickEnd,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.x3),
      const SectionHeader('Notes', padding: EdgeInsets.zero),
      const SizedBox(height: AppSpacing.x1),
      _GroupCard(
        child: TextFormField(
          initialValue: session.notes ?? '',
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Add notes about this workout',
          ),
          onChanged: (v) => _updateSession(
            session.copyWith(notes: v.trim().isEmpty ? null : v.trim()),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.x3),
      SectionHeader(
        'Exercises',
        padding: EdgeInsets.zero,
        trailing: FilledButton.icon(
          onPressed: _addExercise,
          icon: HustlIcon(
            asset: 'assets/icons/ic_add.svg',
            size: 18,
            color: theme.colorScheme.onPrimary,
          ),
          label: const Text('Add'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: AppSpacing.x1,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.x1),
      if (session.exercises.isEmpty)
        ScreenEmptyState(
          icon: Icons.fitness_center,
          assetIcon: 'assets/icons/empty_workout.svg',
          title: 'No exercises yet',
          message: 'Add an exercise to start editing sets.',
          actionLabel: 'Add exercise',
          onAction: _addExercise,
        )
      else ...[
        for (final ex in session.exercises)
          ExerciseCard(
            key: ValueKey(ex.id),
            exercise: ex,
            onExerciseUpdated: (updated) {
              final idx = session.exercises.indexWhere(
                (e) => e.id == updated.id,
              );
              if (idx == -1) return;
              final list = [...session.exercises];
              list[idx] = updated;
              _updateSession(session.copyWith(exercises: list));
            },
            onStartRestTimer: (_) {}, // no-op: do not start timers in edit
            onExerciseDeleted: (id) {
              final list = session.exercises.where((e) => e.id != id).toList();
              _updateSession(session.copyWith(exercises: list));
            },
            onExerciseReplaced: (id) => _replaceExercise(id),
          ),
        const SizedBox(height: AppSpacing.x1),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: _addExercise,
            icon: HustlIcon(
              asset: 'assets/icons/ic_add.svg',
              size: 18,
              color: theme.colorScheme.primary,
            ),
            label: const Text('Add another'),
          ),
        ),
      ],
    ];
  }
}

/// A flat premium grouped card (Wave I): `colorScheme.surface`, card radius,
/// `AppSpacing` padding, no border — the shared object look used across Train,
/// the diary, and the exercise detail screen.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: AppSpacing.cardPadding,
      child: child,
    );
  }
}

/// A clean, tappable date/time row inside the Details card: a tokenized leading
/// glyph, a label with the formatted date·time value, and a trailing chevron.
class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.asset,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String asset;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
          child: Row(
            children: [
              HustlIcon(asset: asset, size: 20, color: colors.primary),
              const SizedBox(width: AppSpacing.x1 + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
