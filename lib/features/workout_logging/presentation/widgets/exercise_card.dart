import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/hustl_snack.dart';
import 'rest_timer_picker.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/utils/effort_scale.dart';
import '../../domain/utils/dropset_utils.dart';
import '../../domain/utils/superset_grouping.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/utils/number_format_util.dart';
import 'set_row.dart';
import 'set_row_layout.dart';
import 'superset_member_picker_sheet.dart';
import 'superset_palette.dart';
import 'package:uuid/uuid.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../domain/utils/warm_up_planner.dart';
import 'warm_up_planner_sheet.dart';

class ExerciseCard extends StatefulWidget {
  final WorkoutExercise exercise;
  final Function(WorkoutExercise) onExerciseUpdated;
  final void Function(int? durationSeconds) onStartRestTimer;
  final Function(String)? onExerciseDeleted;
  final Function(String)? onExerciseReplaced;

  /// The superset group this exercise belongs to, or null when ungrouped. The
  /// screen computes this once from the session's flat list (via
  /// [SupersetGrouping]) and hands it down so the card stays a pure renderer.
  final SupersetGroup? supersetGroup;

  /// Other in-session exercises that can be linked into a superset with this
  /// one (excludes self and, when adding to an existing group, current members).
  /// Empty disables the link affordance with a quiet hint.
  final List<WorkoutExercise> linkCandidates;

  /// Link [otherExerciseIds] into a NEW superset with this exercise. Called from
  /// the "Superset" chip on an ungrouped exercise.
  final void Function(List<String> otherExerciseIds)? onCreateSuperset;

  /// Add [otherExerciseIds] to this exercise's EXISTING group ("Add another").
  final void Function(List<String> otherExerciseIds)? onAddToSuperset;

  /// Remove this exercise from its superset group ("Remove from superset").
  final VoidCallback? onRemoveFromSuperset;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.onExerciseUpdated,
    required this.onStartRestTimer,
    this.onExerciseDeleted,
    this.onExerciseReplaced,
    this.supersetGroup,
    this.linkCandidates = const [],
    this.onCreateSuperset,
    this.onAddToSuperset,
    this.onRemoveFromSuperset,
  });

  /// Whether this exercise is the LAST member of its group in round order.
  /// Non-final members suppress the auto rest timer so only one shared rest
  /// fires per round (the last member starts it).
  bool get _isLastGroupMember {
    final group = supersetGroup;
    if (group == null || group.members.isEmpty) return true;
    return group.members.last.id == exercise.id;
  }

  /// 0-based index of this exercise within its group (member letter source).
  int get _memberIndex {
    final group = supersetGroup;
    if (group == null) return -1;
    return group.members.indexWhere((m) => m.id == exercise.id);
  }

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard>
    with TickerProviderStateMixin {
  final _preferencesService = GetIt.instance<PreferencesService>();
  Future<ExercisePr?>? _prFuture;

  /// The resolved value of [_prFuture], captured once it completes so the
  /// warm-up planner can seed from the PR synchronously (it must not block on
  /// the async fetch). Null until resolved, when there is no PR, or when the
  /// exercise isn't weight/reps.
  ExercisePr? _resolvedPr;

  @override
  void initState() {
    super.initState();
    // Prefetch PR for this exercise once for a snappy UI; cached by repo
    final mode = widget.exercise.exercise.loggingMode;
    if (mode == ExerciseLoggingMode.weightReps &&
        GetIt.instance.isRegistered<WorkoutRepository>()) {
      _fetchPr(widget.exercise.exercise.name);
    }
  }

  @override
  void didUpdateWidget(covariant ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh PR future if the exercise changed (e.g., replaced) or sets updated
    final oldName = oldWidget.exercise.exercise.name;
    final newName = widget.exercise.exercise.name;
    final mode = widget.exercise.exercise.loggingMode;
    if (oldName != newName || oldWidget.exercise.sets != widget.exercise.sets) {
      if (mode != ExerciseLoggingMode.weightReps) {
        _prFuture = null;
        _resolvedPr = null;
      } else if (GetIt.instance.isRegistered<WorkoutRepository>()) {
        _fetchPr(newName);
      } else {
        _prFuture = null;
        _resolvedPr = null;
      }
      // Trigger rebuild of FutureBuilder
      setState(() {});
    }
  }

  /// Kick off a PR fetch and capture its resolved value into [_resolvedPr]
  /// so the warm-up planner can seed from the PR without blocking on the
  /// future. The [_prFuture] still drives the PR chip's FutureBuilder.
  void _fetchPr(String exerciseName) {
    final future = GetIt.instance.get<WorkoutRepository>().getExercisePr(
      exerciseName,
      exerciseSlug: widget.exercise.exercise.slug,
    );
    _prFuture = future;
    _resolvedPr = null;
    // Fire-and-forget: stash the result if it resolves and we're still on
    // the same fetch. A pending PR simply means the planner skips that seed.
    // catchError keeps a failed lookup from raising an uncaught async
    // exception (the PR chip's own FutureBuilder still renders the error
    // path); _resolvedPr just stays null and the planner falls through.
    unawaited(
      future
          .then((pr) {
            if (!mounted || _prFuture != future) return;
            _resolvedPr = (pr != null && pr.isValid) ? pr : null;
          })
          .catchError((Object _) {
            if (!mounted || _prFuture != future) return;
            _resolvedPr = null;
          }),
    );
  }

  /// Briefly await the in-flight PR fetch so the warm-up planner can honour the
  /// PR-before-previous seed contract even when the lifter taps Warm-up before
  /// [_prFuture] resolves. Returns the PR when it lands within the budget (also
  /// caching it into [_resolvedPr] via the [_fetchPr] listener), or null when
  /// there is no pending fetch, it times out, or it fails — in which case the
  /// caller simply falls through to the next seed rung. Bounded so a slow/stuck
  /// lookup never hangs the tap.
  Future<ExercisePr?> _awaitPendingPr() async {
    // Already resolved (or never fetched) — nothing to wait on.
    if (_resolvedPr != null) return _resolvedPr;
    final future = _prFuture;
    if (future == null) return null;
    try {
      final pr = await future.timeout(const Duration(milliseconds: 600));
      // Guard against a stale fetch (exercise replaced mid-wait).
      if (!mounted || _prFuture != future) return null;
      return (pr != null && pr.isValid) ? pr : null;
    } catch (_) {
      // Timeout or lookup error: fall through with no PR seed.
      return null;
    }
  }

  Future<void> _saveRestTimerPreference(
    String exerciseName,
    int seconds,
  ) async {
    await _preferencesService.setExerciseRestTimer(exerciseName, seconds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggingMode = widget.exercise.exercise.loggingMode;
    final group = widget.supersetGroup;
    final isGrouped = group != null;
    final accent = isGrouped
        ? SupersetPalette.accentFor(context, group.colorIndex)
        : null;
    final isFirstMember =
        isGrouped && group.members.first.id == widget.exercise.id;

    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          curve: Curves.easeOut,
          // The body owns sizing; the per-group accent rail is a thin overlay
          // so we never wrap the column in a Row/Expanded (which would demand
          // bounded width inside AnimatedSize and break layout).
          child: Stack(
            children: [
              _buildCardBody(
                context,
                theme,
                loggingMode,
                group,
                accent,
                isFirstMember,
              ),
              if (isGrouped)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    key: const Key('supersetRail'),
                    width: 4,
                    color: accent!.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardBody(
    BuildContext context,
    ThemeData theme,
    ExerciseLoggingMode loggingMode,
    SupersetGroup? group,
    Color? accent,
    bool isFirstMember,
  ) {
    final isGrouped = group != null;
    return Column(
      children: [
        // Exercise header with action chips replacing the overflow menu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group header chip on the first member only.
              if (isGrouped && isFirstMember) ...[
                _SupersetHeaderChip(label: group.label, accent: accent!),
                const SizedBox(height: 8),
              ],
              Text(
                widget.exercise.exercise.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.exercise.exercise.muscles.join(', '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_prFuture != null)
                FutureBuilder<ExercisePr?>(
                  future: _prFuture,
                  builder: (context, snapshot) {
                    final pr = snapshot.data;
                    if (pr != null && !pr.isValid) {
                      return _buildActionChips(context, theme, null);
                    }
                    return _buildActionChips(context, theme, pr);
                  },
                )
              else
                _buildActionChips(context, theme, null),
            ],
          ),
        ),

        // The per-set "Previous" column shows last session's value inline.

        // Current session sets
        Column(
          children: [
            // Sets table header. Mirrors the data row's column geometry EXACTLY
            // (same inner padding + the shared SetRowLayout widths/spacers) so
            // every label lines up above its column. The "Set" column header
            // sits above the tappable set badge (which doubles as the set-type
            // selector); there is no longer a separate type-button slot.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetRowLayout.rowPadding,
                0,
                SetRowLayout.rowPadding,
                8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: SetRowLayout.setColumnWidth,
                    child: Center(
                      child: Text(
                        'Set',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: SetRowLayout.previousLeadingGap),
                  // "Prev" header sits above the flexible Previous column. Kept
                  // short so the compact label never wraps on a narrow phone.
                  // Mirrors the data row's [Expanded] Previous cell EXACTLY, so
                  // the fixed-width "kg"/"Reps" headers below stay centered over
                  // their fields at every width.
                  Expanded(
                    child: Text(
                      'Prev',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (loggingMode != ExerciseLoggingMode.durationOnly) ...[
                    SizedBox(
                      width: SetRowLayout.weightFieldWidth,
                      child: Center(
                        child: Text(
                          loggingMode == ExerciseLoggingMode.distanceDuration
                              ? 'km'
                              : 'kg',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SetRowLayout.weightTrailingGap),
                  ],
                  SizedBox(
                    width: loggingMode == ExerciseLoggingMode.weightReps
                        ? SetRowLayout.repsFieldWidth
                        : SetRowLayout.durationFieldWidth,
                    child: Center(
                      child: Text(
                        loggingMode == ExerciseLoggingMode.weightReps
                            ? 'Reps'
                            : 'Time',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: SetRowLayout.completionLeadingGap),
                  // Empty slot above the completion button column.
                  const SizedBox(width: SetRowLayout.completionButtonWidth),
                ],
              ),
            ),
            // Set rows (full-bleed backgrounds inside card)
            ...(() {
              final sets = widget.exercise.sets;
              final previousSessionSets = widget.exercise.previousSessionSets;
              final previousWarmups = previousSessionSets
                  ?.where((set) => set.setType == SetType.warmup)
                  .toList();
              // Work sets exclude drops too: drops map to previous drops via
              // their parent's working position, not the flat work-set run.
              final previousWorkSets = previousSessionSets
                  ?.where(
                    (set) =>
                        set.setType != SetType.warmup &&
                        set.parentSetId == null,
                  )
                  .toList();
              int workingSetIndex = -1;
              int warmupIndex = -1;
              // The working ordinal of the most recent parent, so a drop can
              // borrow it for its `3.1 / 3.2` label.
              int currentParentOrdinal = 0;
              // Member letter for round labels (A1, B1…) on grouped
              // exercises. -1 / null when ungrouped → numeric ordinals.
              final memberIdx = widget._memberIndex;
              final memberLetter = memberIdx >= 0
                  ? SupersetGrouping.memberLetter(memberIdx)
                  : null;
              final rows = <Widget>[];
              for (var setIndex = 0; setIndex < sets.length; setIndex++) {
                final set = sets[setIndex];
                final isDrop =
                    set.setType == SetType.dropset && set.parentSetId != null;
                if (isDrop) {
                  // Drops do NOT advance the working ordinal: the dropset reads
                  // as ONE working set in the "Set" column.
                } else if (set.setType != SetType.warmup) {
                  workingSetIndex++;
                  currentParentOrdinal = workingSetIndex + 1;
                } else {
                  warmupIndex++;
                }
                final setId = set.id;
                final prevCompleted =
                    setIndex > 0 && sets[setIndex - 1].isCompleted;
                final nextCompleted =
                    setIndex < sets.length - 1 &&
                    sets[setIndex + 1].isCompleted;
                WorkoutSet? previousSet;
                if (set.setType == SetType.warmup) {
                  if (previousWarmups != null &&
                      warmupIndex < previousWarmups.length) {
                    previousSet = previousWarmups[warmupIndex];
                  }
                } else if (isDrop) {
                  previousSet = _previousDropFor(set);
                } else {
                  if (previousWorkSets != null &&
                      workingSetIndex < previousWorkSets.length) {
                    previousSet = previousWorkSets[workingSetIndex];
                  }
                }

                // Drop label: `<parentOrdinal>.<dropIndex>` (e.g. 3.1, 3.2).
                final dropLabel = isDrop
                    ? '$currentParentOrdinal.${set.dropIndex ?? 1}'
                    : null;

                rows.add(
                  _PrFlash(
                    // PR flash is a sibling overlay keyed off the set so a
                    // false->true PR transition pulses the row. The inner
                    // SetRow keeps its own ValueKey, inputs and structure.
                    isPr: set.isCompleted && set.isPr,
                    child: SetRow(
                      key: ValueKey(setId),
                      setIndex: setIndex,
                      // Working ordinals re-derive over non-warm-up sets
                      // only, so two warm-ups + three work sets read
                      // `W W 1 2 3`. Warm-up / drop rows ignore this (badge).
                      displayOrdinal: workingSetIndex + 1,
                      isDrop: isDrop,
                      // Drops show `3.1`; grouped working sets show a round
                      // label (A1, B2…); warm-up rows keep their W badge.
                      displayLabel: isDrop
                          ? dropLabel
                          : (memberLetter != null &&
                                set.setType != SetType.warmup)
                          ? '$memberLetter${workingSetIndex + 1}'
                          : null,
                      onSetTypeChanged: (draft, type) =>
                          _handleSetTypeChanged(setId, type, draft: draft),
                      set: set,
                      exerciseKind: widget.exercise.exercise.kind,
                      loggingMode: widget.exercise.exercise.loggingMode,
                      previousSet: previousSet,
                      isPreviousCompleted: prevCompleted,
                      isNextCompleted: nextCompleted,
                      onSetUpdated: (updatedSet) {
                        final updatedSets = [...widget.exercise.sets];
                        final idx = updatedSets.indexWhere(
                          (s) => s.id == setId,
                        );
                        if (idx < 0) return;
                        updatedSets[idx] = updatedSet;
                        widget.onExerciseUpdated(
                          widget.exercise.copyWith(sets: updatedSets),
                        );
                      },
                      onSetCompleted: (set) => _onSetCompletedById(set, setId),
                      onSetUncompleted: (set) =>
                          _onSetUncompletedById(set, setId),
                      onSetDeleted: () => _deleteSetById(setId),
                    ),
                  ),
                );

                // After the LAST drop of a parent, surface a single indented
                // "Add drop" affordance so drops 2..n are one tap each.
                final nextSet = setIndex < sets.length - 1
                    ? sets[setIndex + 1]
                    : null;
                final isLastDropOfParent =
                    isDrop &&
                    (nextSet == null || nextSet.parentSetId != set.parentSetId);
                if (isLastDropOfParent) {
                  rows.add(_buildAddDropButton(context, set.parentSetId!));
                }
              }
              return rows;
            })(),

            // Quiet hint when there are no sets yet, so the collapsed
            // list never reads as a layout glitch.
            if (widget.exercise.sets.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                child: Text(
                  'No sets yet — add your first one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            // Add set button (keep padded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addSet,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add set'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Removed unused _buildPreviousSetRow helper

  void _openExerciseInfo(BuildContext context) {
    final slug = widget.exercise.exercise.canonicalKey;
    if (slug != null && slug.isNotEmpty) {
      context.push('/exercise_library/$slug?tab=0');
      return;
    }
    context.push(
      '/exercise_detail',
      extra: {'exercise': widget.exercise.exercise, 'initialTabIndex': 0},
    );
  }

  void _openExerciseRecords(BuildContext context) {
    final slug = widget.exercise.exercise.canonicalKey;
    if (slug != null && slug.isNotEmpty) {
      context.push('/exercise_library/$slug?tab=1');
      return;
    }
    context.push(
      '/exercise_detail',
      extra: {'exercise': widget.exercise.exercise, 'initialTabIndex': 1},
    );
  }

  Widget _buildActionChips(
    BuildContext context,
    ThemeData theme,
    ExercisePr? pr,
  ) {
    final isGrouped = widget.supersetGroup != null;
    // The superset chip is shown when there is any link path: either this
    // exercise is grouped (manage it) or there are candidates to link.
    final canSuperset =
        isGrouped ||
        (widget.onCreateSuperset != null && widget.linkCandidates.isNotEmpty);
    return _ExerciseActionChips(
      exercise: widget.exercise,
      exercisePr: pr,
      isInSuperset: isGrouped,
      showSupersetChip: canSuperset,
      onInfo: () => _openExerciseInfo(context),
      onViewRecords: pr != null ? () => _openExerciseRecords(context) : null,
      onWarmUp: () => _openWarmUpPlanner(context),
      onSuperset: canSuperset ? () => _handleSupersetChip(context) : null,
      onReplace: widget.onExerciseReplaced != null
          ? () => _handleReplaceExercise(context)
          : null,
      onRestTimer: () => _handleRestTimerSelection(context),
      onDelete: widget.onExerciseDeleted != null
          ? () => _showDeleteConfirmation(context, theme)
          : null,
    );
  }

  /// Entry point for the "Superset" chip. Ungrouped exercises open a picker to
  /// create a group; grouped exercises open a small manage sheet ("Add another"
  /// / "Remove from superset").
  Future<void> _handleSupersetChip(BuildContext context) async {
    if (widget.supersetGroup == null) {
      await _openCreateSupersetPicker(context);
    } else {
      await _openManageSupersetSheet(context);
    }
  }

  Future<void> _openCreateSupersetPicker(BuildContext context) async {
    final onCreate = widget.onCreateSuperset;
    if (onCreate == null) return;
    final picked = await showSupersetMemberPicker(
      context,
      candidates: widget.linkCandidates,
      title: 'Create a superset',
      confirmLabel: 'Group as superset',
      confirmVerb: 'Group',
    );
    if (picked == null || picked.isEmpty) return;
    onCreate(picked);
  }

  Future<void> _openManageSupersetSheet(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onAddToSuperset != null &&
                  widget.linkCandidates.isNotEmpty)
                ListTile(
                  key: const Key('supersetAddAnother'),
                  leading: Icon(
                    Icons.add_link,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Add another'),
                  onTap: () {
                    sheetContext.pop();
                    // ignore: discarded_futures
                    _openAddToSupersetPicker(context);
                  },
                ),
              if (widget.onRemoveFromSuperset != null)
                ListTile(
                  key: const Key('supersetRemove'),
                  leading: Icon(Icons.link_off, color: theme.colorScheme.error),
                  title: Text(
                    'Remove from superset',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    sheetContext.pop();
                    widget.onRemoveFromSuperset!();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAddToSupersetPicker(BuildContext context) async {
    final onAdd = widget.onAddToSuperset;
    if (onAdd == null) return;
    final picked = await showSupersetMemberPicker(
      context,
      candidates: widget.linkCandidates,
      title: 'Add to superset',
      confirmLabel: 'Add to superset',
      confirmVerb: 'Add',
      countOffset: 0,
    );
    if (picked == null || picked.isEmpty) return;
    onAdd(picked);
  }

  void _handleReplaceExercise(BuildContext context) {
    if (widget.onExerciseReplaced == null) {
      return;
    }
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onExerciseReplaced!(widget.exercise.id);
    });
  }

  Future<void> _handleRestTimerSelection(BuildContext context) async {
    final picked = await showRestTimerPicker(
      context,
      initialSeconds: widget.exercise.restTimerSeconds ?? 90,
    );
    if (picked != null) {
      final updated = widget.exercise.copyWith(restTimerSeconds: picked);
      await _saveRestTimerPreference(widget.exercise.exercise.name, picked);
      widget.onExerciseUpdated(updated);
    }
  }

  Future<void> _openWarmUpPlanner(BuildContext context) async {
    final kind = widget.exercise.exercise.kind;
    // Gate on the WEIGHT-BASED logging mode, not the kind: duration-only
    // strength moves (Wall Sit, Plank) still report `kind == strength` but hide
    // weight and treat reps as seconds, so a kg %-ladder must not apply. Cardio
    // and distance/duration are excluded for the same reason (no kg to ramp).
    if (!warmUpSupportsLogging(widget.exercise.exercise.loggingMode)) {
      HustlSnack.show(
        context,
        'Warm-up planning is only available for weight-based exercises for now.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }

    final isAssisted = kind == ExerciseKind.assisted;
    final hasExistingWarmUps = widget.exercise.sets.any(
      (set) => set.setType == SetType.warmup,
    );

    // Honour the PR-before-previous seed contract: if the PR fetch is still in
    // flight (tap landed before it resolved), briefly await it so the planner
    // opens anchored to the PR instead of falling through to previous-session
    // data. The wait is bounded so a slow/stuck lookup never hangs the tap; on
    // timeout or error we fall through with whatever rungs are available. A
    // resolved current working set always wins, so this only matters when there
    // is no current set to seed from.
    final prResolved = await _awaitPendingPr();

    if (!mounted || !context.mounted) return;

    // Resolve the seed by priority — current set -> PR -> previous session. The
    // PR is read from [_resolvedPr] (now populated if the bounded wait above
    // landed it). A null seed is fine: the planner still opens and the lifter
    // types a target. The gate that demanded a logged working set is gone.
    final pr = _resolvedPr ?? prResolved;
    final seed = resolveWarmUpSeed(
      currentSets: widget.exercise.sets,
      previousSessionSets: widget.exercise.previousSessionSets,
      prWeight: pr?.weight,
      prReps: pr?.reps,
      isAssisted: isAssisted,
    );

    final result = await showWarmUpPlannerSheet(
      context,
      seed: seed,
      isAssisted: isAssisted,
      hasExistingWarmUps: hasExistingWarmUps,
    );

    if (!mounted || result == null) return;
    if (!context.mounted) return;

    _applyWarmUpSuggestions(context, result.suggestions);
  }

  void _applyWarmUpSuggestions(
    BuildContext context,
    List<WarmUpSuggestion> selections,
  ) {
    // Snapshot the prior sets so the confirmation toast can offer one-tap undo.
    final previousSets = List<WorkoutSet>.from(widget.exercise.sets);
    final hadWarmUps = previousSets.any((set) => set.setType == SetType.warmup);
    final filtered = selections.where((s) => s.selected).toList();
    // Warm-ups always prepend ahead of the working sets; they're excluded from
    // volume/PR elsewhere, so this ordering is the whole contract.
    final baseSets = widget.exercise.sets.where(
      (set) => set.setType != SetType.warmup,
    );

    if (filtered.isEmpty) {
      widget.onExerciseUpdated(
        widget.exercise.copyWith(sets: baseSets.toList()),
      );
      if (hadWarmUps && context.mounted) {
        HustlSnack.show(
          context,
          'Removed warm-up sets',
          variant: HustlSnackVariant.success,
          actionLabel: 'Undo',
          onAction: () => widget.onExerciseUpdated(
            widget.exercise.copyWith(sets: previousSets),
          ),
        );
      }
      return;
    }

    final warmUpSets = filtered.map((suggestion) {
      return WorkoutSet(
        id: const Uuid().v4(),
        weight: suggestion.weight,
        reps: suggestion.reps,
        setType: SetType.warmup,
        isCompleted: false,
        isPr: false,
      );
    }).toList();

    widget.onExerciseUpdated(
      widget.exercise.copyWith(sets: [...warmUpSets, ...baseSets]),
    );

    if (context.mounted) {
      final count = warmUpSets.length;
      HustlSnack.show(
        context,
        'Added $count warm-up set${count == 1 ? '' : 's'}',
        variant: HustlSnackVariant.success,
        actionLabel: 'Undo',
        onAction: () => widget.onExerciseUpdated(
          widget.exercise.copyWith(sets: previousSets),
        ),
      );
    }
  }

  /// Map a drop to the matching drop from the previous session: same parent
  /// position (working ordinal) and same dropIndex, when available.
  WorkoutSet? _previousDropFor(WorkoutSet drop) {
    final previousSessionSets = widget.exercise.previousSessionSets;
    if (previousSessionSets == null) return null;
    final parentId = drop.parentSetId;
    if (parentId == null) return null;

    // The parent's working position in the CURRENT session (0-based over
    // non-warm-up parents), so we can find the previous session's drops hanging
    // off the parent at the same position.
    final currentParents = widget.exercise.sets
        .where((s) => s.setType != SetType.warmup && s.parentSetId == null)
        .toList();
    final parentPos = currentParents.indexWhere((s) => s.id == parentId);
    if (parentPos < 0) return null;

    final previousParents = previousSessionSets
        .where((s) => s.setType != SetType.warmup && s.parentSetId == null)
        .toList();
    if (parentPos >= previousParents.length) return null;
    final previousParentId = previousParents[parentPos].id;

    final previousDrops = DropsetUtils.dropsFor(
      previousSessionSets,
      previousParentId,
    );
    final dropIdx = drop.dropIndex ?? 1;
    if (dropIdx - 1 < previousDrops.length) {
      return previousDrops[dropIdx - 1];
    }
    return null;
  }

  void _onSetCompletedById(WorkoutSet set, String setId) {
    final index = widget.exercise.sets.indexWhere((s) => s.id == setId);
    if (index < 0) return;
    // ignore: discarded_futures
    _onSetCompleted(set, index);
  }

  void _onSetUncompletedById(WorkoutSet set, String setId) {
    final index = widget.exercise.sets.indexWhere((s) => s.id == setId);
    if (index < 0) return;
    _onSetUncompleted(set, index);
  }

  /// Remove a set by id. Deleting a dropset PARENT cascade-deletes its drops;
  /// deleting a single drop removes just that drop and renumbers the rest.
  void _deleteSetById(String setId) {
    final sets = widget.exercise.sets;
    final removed = sets.firstWhere(
      (s) => s.id == setId,
      orElse: () => sets.isNotEmpty
          ? sets.first
          : const WorkoutSet(id: '', weight: 0, reps: 0),
    );
    final isParentWithDrops =
        removed.parentSetId == null &&
        DropsetUtils.dropsFor(sets, setId).isNotEmpty;

    var updatedSets = sets.where((s) {
      if (s.id == setId) return false;
      // Cascade: a parent's drops go with it.
      if (isParentWithDrops && s.parentSetId == setId) return false;
      return true;
    }).toList();

    // Renumber remaining drops so a deleted middle drop never leaves a gap.
    updatedSets = DropsetUtils.renumberDrops(updatedSets);
    widget.onExerciseUpdated(widget.exercise.copyWith(sets: updatedSets));
  }

  /// Card-owned set-type change. Encapsulates the dropset structural rules so
  /// the set row stays a pure renderer:
  /// - "Drop set" on a working set (parentSetId == null) APPENDS a child drop.
  /// - "Regular" on a dropset PARENT strips its drops (confirm if any logged).
  /// - "Regular"/other on a drop un-links just that drop back to a normal set.
  /// - anything else re-types the row in place (warm-up / failure / superset).
  Future<void> _handleSetTypeChanged(
    String setId,
    SetType type, {
    WorkoutSet? draft,
  }) async {
    final sets = widget.exercise.sets;
    final index = sets.indexWhere((s) => s.id == setId);
    if (index < 0) return;
    final originalSet = sets[index];
    final set = draft?.id == setId ? draft! : originalSet;
    final isDrop =
        originalSet.setType == SetType.dropset &&
        originalSet.parentSetId != null;

    // Picking "Drop set" on a working set starts a dropset off it.
    if (type == SetType.dropset && !isDrop) {
      _addDrop(setId, parentDraft: set);
      return;
    }

    // Picking a non-drop type on a drop un-links it back to a standalone set.
    if (isDrop && type != SetType.dropset) {
      final unlinked = _withFailureRir(
        set.copyWith(setType: type, parentSetId: null, dropIndex: null),
        type,
      );
      final updatedSets = [...sets];
      updatedSets[index] = unlinked;
      widget.onExerciseUpdated(
        widget.exercise.copyWith(sets: DropsetUtils.renumberDrops(updatedSets)),
      );
      return;
    }

    // Picking "Regular" (or any non-dropset) on a dropset PARENT strips drops.
    final parentHasDrops = DropsetUtils.dropsFor(sets, setId).isNotEmpty;
    if (parentHasDrops && type != SetType.dropset) {
      await _stripDropsFromParent(setId, type, parentDraft: set);
      return;
    }

    // Default: re-type this row in place.
    final updatedSets = [...sets];
    updatedSets[index] = _withFailureRir(set.copyWith(setType: type), type);
    widget.onExerciseUpdated(widget.exercise.copyWith(sets: updatedSets));
  }

  /// Failure == RIR 0 (no reps left): a set typed to failure also logs RIR 0 in
  /// the SAME update, so type and effort never desync. Non-failure types keep
  /// their existing RPE untouched.
  WorkoutSet _withFailureRir(WorkoutSet s, SetType type) =>
      type == SetType.failure ? s.copyWith(rpe: EffortScale.rpeFromRir(0)) : s;

  /// Append one child drop beneath the working set [parentId], pre-filled with
  /// weight ≈ parent − 15% and reps = parent.reps. Routes through the same
  /// onExerciseUpdated persist/sync path as every other set mutation.
  void _addDrop(String parentId, {WorkoutSet? parentDraft}) {
    final sets = [...widget.exercise.sets];
    final parentIndex = sets.indexWhere((s) => s.id == parentId);
    if (parentIndex < 0) return;
    if (parentDraft?.id == parentId) sets[parentIndex] = parentDraft!;
    final parent = sets[parentIndex];

    final existingDrops = DropsetUtils.dropsFor(sets, parentId);
    final nextDropIndex = existingDrops.length + 1;

    final newDrop = WorkoutSet(
      id: const Uuid().v4(),
      weight: DropsetUtils.suggestedDropWeight(parent.weight),
      reps: parent.reps,
      setType: SetType.dropset,
      isCompleted: false,
      isPr: false,
      parentSetId: parentId,
      dropIndex: nextDropIndex,
    );

    // Insert right after the parent's existing drop run so the block stays
    // contiguous in list order.
    var insertAt = parentIndex + 1;
    while (insertAt < sets.length &&
        sets[insertAt].setType == SetType.dropset &&
        sets[insertAt].parentSetId == parentId) {
      insertAt++;
    }
    final updatedSets = [...sets];
    updatedSets.insert(insertAt, newDrop);
    widget.onExerciseUpdated(
      widget.exercise.copyWith(sets: DropsetUtils.renumberDrops(updatedSets)),
    );
  }

  /// Strip all drops from [parentId] and set the parent's type to [parentType].
  /// Quietly confirms (via snackbar undo) when any drop has logged data so the
  /// lifter never loses work in a one-way trap.
  Future<void> _stripDropsFromParent(
    String parentId,
    SetType parentType, {
    WorkoutSet? parentDraft,
  }) async {
    final previousSets = List<WorkoutSet>.from(widget.exercise.sets);
    final parentIndex = previousSets.indexWhere((s) => s.id == parentId);
    if (parentIndex >= 0 && parentDraft?.id == parentId) {
      previousSets[parentIndex] = parentDraft!;
    }
    final drops = DropsetUtils.dropsFor(previousSets, parentId);
    final anyLogged = drops.any(
      (d) => d.isCompleted || d.reps > 0 || d.weight.abs() > 0,
    );

    final updatedSets = previousSets
        .where((s) => !(s.parentSetId == parentId))
        .map(
          (s) => s.id == parentId
              ? _withFailureRir(s.copyWith(setType: parentType), parentType)
              : s,
        )
        .toList();

    widget.onExerciseUpdated(
      widget.exercise.copyWith(sets: DropsetUtils.renumberDrops(updatedSets)),
    );

    if (anyLogged && context.mounted) {
      final count = drops.length;
      HustlSnack.show(
        context,
        'Removed $count drop${count == 1 ? '' : 's'}',
        variant: HustlSnackVariant.success,
        actionLabel: 'Undo',
        onAction: () => widget.onExerciseUpdated(
          widget.exercise.copyWith(sets: previousSets),
        ),
      );
    }
  }

  /// Single indented full-width "Add drop" affordance under a dropset block,
  /// mirroring the "Add set" button so drops 2..n are one tap each.
  Widget _buildAddDropButton(BuildContext context, String parentId) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('addDrop-$parentId'),
      padding: const EdgeInsets.fromLTRB(40, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _addDrop(parentId),
          icon: const Icon(Icons.arrow_downward, size: 16),
          label: const Text('Add drop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.tertiary,
            side: BorderSide(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addSet() async {
    final nextIndex = widget.exercise.sets.length;
    final previousSets = widget.exercise.previousSessionSets;
    WorkoutSet? templateSet;
    if (previousSets != null && previousSets.isNotEmpty) {
      final previousIndex = nextIndex < previousSets.length
          ? nextIndex
          : previousSets.length - 1;
      templateSet = previousSets[previousIndex];
    }

    // Create a new set with a unique id, pre-filling from the previous session
    final newSet = WorkoutSet(
      id: const Uuid().v4(),
      weight: templateSet?.weight ?? 0.0,
      reps: templateSet?.reps ?? 0,
      rpe: templateSet?.rpe,
      setType: templateSet?.setType ?? SetType.regular,
      notes: templateSet?.notes,
      isCompleted: false,
      isPr: false,
    );

    // Update the exercise with the new set
    final updatedExercise = widget.exercise.copyWith(
      sets: [...widget.exercise.sets, newSet],
    );

    // Call the callback to update the parent
    widget.onExerciseUpdated(updatedExercise);
  }

  Future<void> _onSetCompleted(WorkoutSet set, int index) async {
    final existing = widget.exercise.sets[index];
    final wasAlreadyCompleted = existing.isCompleted;
    final completedSet = set.copyWith(
      isCompleted: true,
      completedAt: wasAlreadyCompleted ? existing.completedAt : DateTime.now(),
      // Clear PR immediately; async check below re-applies true when eligible.
      isPr: false,
    );

    // Update UI immediately; PR calculation runs async to avoid completion jank.
    final updatedSets = List<WorkoutSet>.from(widget.exercise.sets);
    updatedSets[index] = completedSet;
    widget.onExerciseUpdated(widget.exercise.copyWith(sets: updatedSets));

    if (!wasAlreadyCompleted) {
      // Confirm haptic the moment a set is committed. If the async PR check
      // below promotes this set to a NEW PR, a celebrate haptic fires there
      // instead (one cue per moment). Fire-and-forget; respects user prefs.
      Haptics.confirm();

      // Warm-ups use short/no rest: suppress the auto rest timer when the set
      // just completed OR the next set is a warm-up. Only the first true
      // working set kicks off the normal rest.
      final completedIsWarmup = completedSet.setType == SetType.warmup;
      final nextSet = index + 1 < updatedSets.length
          ? updatedSets[index + 1]
          : null;
      final nextIsWarmup = nextSet?.setType == SetType.warmup;
      // Drops have little/no rest by definition: suppress auto-start when the
      // completed set is a drop OR the next row is a drop (so a parent flows
      // straight into its drop). Normal rest fires only after the FINAL drop,
      // where the next row is no longer a drop of the same parent.
      final completedIsDrop =
          completedSet.setType == SetType.dropset &&
          completedSet.parentSetId != null;
      final nextIsDrop =
          nextSet?.setType == SetType.dropset && nextSet?.parentSetId != null;
      // Supersets share ONE rest per round: only the last group member starts
      // the timer. Non-final members suppress auto-start so the lifter flows
      // A1 → B1 → (rest) → A2 → B2 without a rest wedged between members.
      final suppressForGroup =
          widget.supersetGroup != null && !widget._isLastGroupMember;
      if (_preferencesService.shouldAutoStartRestTimer &&
          !completedIsWarmup &&
          !nextIsWarmup &&
          !completedIsDrop &&
          !nextIsDrop &&
          !suppressForGroup) {
        widget.onStartRestTimer(widget.exercise.restTimerSeconds);
      }
    }

    unawaited(_maybeUpdatePr(completedSet));
  }

  Future<void> _maybeUpdatePr(WorkoutSet completedSet) async {
    if (widget.exercise.exercise.loggingMode !=
        ExerciseLoggingMode.weightReps) {
      return;
    }

    // Warm-up sets and dropset drops are never eligible for a PR (mirrors the
    // repo PR guards); skip before any estimate runs so a light warm-up or a
    // lighter drop can't pollute records. Only the heavy top set wins.
    if (completedSet.setType == SetType.warmup ||
        completedSet.setType == SetType.dropset) {
      return;
    }

    final kind = widget.exercise.exercise.kind;
    final isStrength = kind == ExerciseKind.strength;
    final isAssisted = kind == ExerciseKind.assisted;
    if (!(isStrength || isAssisted)) return;

    final hasValidWeight =
        (isStrength && completedSet.weight > 0) ||
        (isAssisted && completedSet.weight < 0);
    if (!GetIt.instance.isRegistered<WorkoutRepository>()) return;
    if (!hasValidWeight || completedSet.reps <= 0) return;

    final repo = GetIt.instance<WorkoutRepository>();
    final isPr = await repo.checkIfSetIsPR(
      widget.exercise.exercise.name,
      completedSet,
      exerciseSlug: widget.exercise.exercise.slug,
    );

    _applyPrResult(completedSet: completedSet, isPr: isPr);
  }

  void _applyPrResult({
    required WorkoutSet completedSet,
    required bool isPr,
    int attempt = 0,
  }) {
    if (!mounted) return;

    final sets = widget.exercise.sets;
    final idx = sets.indexWhere((s) => s.id == completedSet.id);
    if (idx < 0) return;

    final current = sets[idx];

    // Parent may not have rebuilt yet when the async PR check returns quickly.
    if (!current.isCompleted) {
      if (attempt < 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _applyPrResult(
            completedSet: completedSet,
            isPr: isPr,
            attempt: attempt + 1,
          );
        });
      }
      return;
    }

    // Drop stale async results when the set changed after completion.
    if (current.completedAt != completedSet.completedAt ||
        current.weight != completedSet.weight ||
        current.reps != completedSet.reps) {
      return;
    }
    if (current.isPr == isPr) return;

    // A completed set just turned into a NEW PR: celebrate (heavy) haptic
    // instead of the standard completion confirm fired upstream. Fire-and-forget.
    if (isPr && current.isCompleted) {
      Haptics.celebrate();
    }

    final updatedSets = List<WorkoutSet>.from(sets);
    updatedSets[idx] = current.copyWith(isPr: isPr);
    widget.onExerciseUpdated(widget.exercise.copyWith(sets: updatedSets));
  }

  void _onSetUncompleted(WorkoutSet set, int index) {
    // Create a copy of the sets list
    final List<WorkoutSet> updatedSets = List.from(widget.exercise.sets);

    // Mark the current set as not completed and not a PR
    final uncompletedSet = set.copyWith(isCompleted: false, isPr: false);
    updatedSets[index] = uncompletedSet;

    final updatedExercise = widget.exercise.copyWith(sets: updatedSets);
    widget.onExerciseUpdated(updatedExercise);
  }

  // Add helper method for showing delete confirmation
  void _showDeleteConfirmation(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete exercise',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "${widget.exercise.exercise.name}" from this workout?',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          FilledButton(
            onPressed: () {
              context.pop();
              widget.onExerciseDeleted!(widget.exercise.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Wraps a set row and plays a brief, one-shot highlight when the wrapped set
/// becomes a NEW personal record. Purely additive feel: the pulse is a
/// non-interactive overlay (it never intercepts taps, shifts layout, or alters
/// the row's structure/keys/inputs) and is fully suppressed under reduce-motion.
class _PrFlash extends StatefulWidget {
  const _PrFlash({required this.isPr, required this.child});

  final bool isPr;
  final Widget child;

  @override
  State<_PrFlash> createState() => _PrFlashState();
}

class _PrFlashState extends State<_PrFlash> {
  // Bumped on each false->true PR transition so flutter_animate replays the
  // one-shot pulse for this exact moment only.
  int _pulseKey = 0;

  @override
  void didUpdateWidget(covariant _PrFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPr && !oldWidget.isPr) {
      _pulseKey++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final showPulse = widget.isPr && !reduceMotion && _pulseKey > 0;

    final colors = Theme.of(context).colorScheme;

    // The row stays the first child of a stable Stack so its element identity,
    // SetRowController and inputs are never re-parented by the flash toggling
    // on or off. The pulse is a separate, non-interactive, self-fading overlay.
    return Stack(
      children: [
        widget.child,
        if (showPulse)
          Positioned.fill(
            child: IgnorePointer(
              child:
                  Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: colors.primary.withValues(alpha: 0.16),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                      )
                      // Plays once, then settles to fully transparent — keeps
                      // pumpAndSettle()-based tests deterministic.
                      .animate(key: ValueKey<int>(_pulseKey))
                      .fadeIn(duration: AppMotion.fast)
                      .then()
                      .fadeOut(
                        duration: AppMotion.emphasized,
                        curve: AppMotion.exitCurve,
                      ),
            ),
          ),
      ],
    );
  }
}

class _ExerciseActionChips extends StatelessWidget {
  final WorkoutExercise exercise;
  final ExercisePr? exercisePr;
  final bool isInSuperset;
  final bool showSupersetChip;
  final VoidCallback onInfo;
  final VoidCallback onWarmUp;
  final VoidCallback? onSuperset;
  final VoidCallback? onReplace;
  final VoidCallback onRestTimer;
  final VoidCallback? onDelete;
  final VoidCallback? onViewRecords;

  const _ExerciseActionChips({
    required this.exercise,
    required this.exercisePr,
    required this.isInSuperset,
    required this.showSupersetChip,
    required this.onInfo,
    required this.onWarmUp,
    required this.onSuperset,
    required this.onReplace,
    required this.onRestTimer,
    required this.onDelete,
    required this.onViewRecords,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warmUpCount = exercise.sets
        .where((set) => set.setType == SetType.warmup)
        .length;
    final hasWarmUps = warmUpCount > 0;
    final timerLabel = _formatTimerLabel(exercise.restTimerSeconds);
    final chipBackground = theme.colorScheme.surfaceContainerHigh.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.32,
    );
    final chipBorder = theme.colorScheme.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.35,
    );
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
      letterSpacing: 0.05,
    );
    final maybePr = exercisePr;
    final pr = (maybePr != null && maybePr.isValid) ? maybePr : null;
    final prLabel = pr != null
        ? _formatPrLabel(pr, exercise.exercise.kind)
        : null;

    final chips = <Widget>[
      _buildActionChip(
        context,
        key: const ValueKey('chip-info'),
        icon: Icons.info_outline,
        label: 'Info',
        onPressed: onInfo,
        chipBackground: chipBackground,
        chipBorder: chipBorder,
        labelStyle: labelStyle,
      ),
      _buildWarmupChip(
        context,
        hasWarmUps: hasWarmUps,
        warmUpCount: warmUpCount,
        chipBackground: chipBackground,
        chipBorder: chipBorder,
        labelStyle: labelStyle,
      ),
      if (showSupersetChip)
        _buildSupersetChip(
          context,
          chipBackground: chipBackground,
          chipBorder: chipBorder,
          labelStyle: labelStyle,
        ),
      _buildActionChip(
        context,
        key: const ValueKey('chip-swap'),
        icon: Icons.swap_horiz,
        label: 'Replace',
        onPressed: onReplace,
        chipBackground: chipBackground,
        chipBorder: chipBorder,
        labelStyle: labelStyle,
      ),
      _buildActionChip(
        context,
        key: const ValueKey('chip-rest-timer'),
        icon: Icons.timer_outlined,
        label: timerLabel,
        onPressed: onRestTimer,
        chipBackground: chipBackground,
        chipBorder: chipBorder,
        labelStyle: labelStyle,
      ),
      if (pr != null && prLabel != null)
        _buildActionChip(
          context,
          key: const ValueKey('chip-pr'),
          icon: Icons.emoji_events_rounded,
          label: prLabel,
          onPressed: onViewRecords,
          chipBackground: chipBackground,
          chipBorder: chipBorder,
          labelStyle: labelStyle,
        ),
      _buildActionChip(
        context,
        key: const ValueKey('chip-more'),
        icon: Icons.more_horiz,
        label: 'Options',
        onPressed: onDelete != null
            ? () => _showMoreSheet(context, theme, onDelete!)
            : null,
        chipBackground: chipBackground,
        chipBorder: chipBorder,
        labelStyle: labelStyle,
      ),
    ];

    // Surface every secondary action at once: a Wrap flows the chips onto
    // (typically) two rows so nothing hides behind a non-obvious horizontal
    // scroll. The chips share one density (see _buildActionChip and the
    // FilterChips below) so the rows sit on a clean baseline, and "Options"
    // stays last so any wrap break falls on the wide variable chips
    // (Timer / PR) rather than leaving a ragged mid-row gap.
    return Wrap(
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  Widget _buildActionChip(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color chipBackground,
    required Color chipBorder,
    required TextStyle? labelStyle,
  }) {
    return ActionChip(
      key: key,
      avatar: Icon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: chipBackground,
      shape: StadiumBorder(side: BorderSide(color: chipBorder)),
      labelStyle: labelStyle,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // Match the FilterChips' compact density so a wrapped action row sits on
      // one clean baseline (mixed ActionChip/FilterChip heights read as ragged).
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildWarmupChip(
    BuildContext context, {
    required bool hasWarmUps,
    required int warmUpCount,
    required Color chipBackground,
    required Color chipBorder,
    required TextStyle? labelStyle,
  }) {
    final theme = Theme.of(context);
    // Warm-up is a set TYPE, not an interactive control, so its selected
    // state renders amber — matching the W keyboard key and set-number badge
    // — instead of the blue every other selected chip uses. Blue stays
    // reserved for interactive/commit controls (active filter chips, Done).
    final warmupInk = AppColors.warmupInk(context);
    final warmupTint = AppColors.accentWarningAmber.withValues(
      alpha: AppColors.setTypeTintAlpha(context),
    );
    return FilterChip(
      key: const ValueKey('chip-warmup'),
      avatar: Icon(
        Icons.fitness_center,
        size: 18,
        color: hasWarmUps ? warmupInk : theme.colorScheme.primary,
      ),
      label: Text(hasWarmUps ? 'Warm-up ($warmUpCount)' : 'Warm-up'),
      selected: hasWarmUps,
      onSelected: (_) => onWarmUp(),
      backgroundColor: chipBackground,
      selectedColor: warmupTint,
      checkmarkColor: warmupInk,
      shape: StadiumBorder(side: BorderSide(color: chipBorder)),
      labelStyle: hasWarmUps
          ? theme.textTheme.labelLarge?.copyWith(color: warmupInk)
          : labelStyle,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      showCheckmark: false,
    );
  }

  Widget _buildSupersetChip(
    BuildContext context, {
    required Color chipBackground,
    required Color chipBorder,
    required TextStyle? labelStyle,
  }) {
    final theme = Theme.of(context);
    return FilterChip(
      key: const ValueKey('chip-superset'),
      avatar: Icon(
        Icons.link,
        size: 18,
        color: isInSuperset
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.primary,
      ),
      label: Text(isInSuperset ? 'In superset' : 'Superset'),
      selected: isInSuperset,
      onSelected: onSuperset == null ? null : (_) => onSuperset!.call(),
      backgroundColor: chipBackground,
      selectedColor: theme.colorScheme.secondaryContainer,
      shape: StadiumBorder(side: BorderSide(color: chipBorder)),
      labelStyle: isInSuperset
          ? theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            )
          : labelStyle,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      showCheckmark: false,
    );
  }

  String? _formatPrLabel(ExercisePr pr, ExerciseKind kind) {
    final units = switch (kind) {
      ExerciseKind.cardio => 'km',
      ExerciseKind.assisted => 'kg',
      ExerciseKind.strength => 'kg',
    };
    final weightStr = NumberFormatUtil.formatWeight(pr.weight);
    return 'PR $weightStr$units × ${pr.reps}';
  }

  static String _formatTimerLabel(int? seconds) {
    if (seconds == null) {
      return 'Timer';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0 && remainingSeconds > 0) {
      return 'Timer ${minutes}m ${remainingSeconds}s';
    }
    if (minutes > 0) {
      return 'Timer ${minutes}m';
    }
    return 'Timer ${remainingSeconds}s';
  }

  static Future<void> _showMoreSheet(
    BuildContext context,
    ThemeData theme,
    VoidCallback onDelete,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: theme.colorScheme.error,
                  size: 22,
                ),
                title: Text(
                  'Remove exercise',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  context.pop();
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small, quiet pill on the first member of a group naming the kind
/// ("Superset" / "Giant set" / "Circuit"), tinted with the group's accent.
class _SupersetHeaderChip extends StatelessWidget {
  const _SupersetHeaderChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('supersetHeaderChip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
