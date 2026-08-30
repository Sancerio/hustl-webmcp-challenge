import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:collection/collection.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/mini_pill_toggle.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:hustl_app/core/widgets/video_player_widget.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/config/api_config.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/utils/time_format_util.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/utils/muscle_group_mapper.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/muscle_figure.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_charts.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/segmented_pill_selector.dart';
import '../../domain/services/exercise_record_service.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../widgets/custom_exercise_form.dart';
import '../../domain/repositories/exercise_repository.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;
  final int initialTabIndex;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    this.initialTabIndex = 0,
  });

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  late bool _isFavorite;
  final PreferencesService _prefs = GetIt.instance<PreferencesService>();
  late Exercise _exercise;
  bool _isCustom = false;
  bool _debugMode = false;
  bool _generatingOverview = false;
  bool _generatingHowTo = false;
  bool _addingToMine = false;

  /// Single shared future for workout sessions — both Record and History tabs
  /// read from this so the DB/network round-trip only happens once per screen visit.
  Future<List<WorkoutSession>>? _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _exercise = widget.exercise;
    _isFavorite = _prefs.isExerciseFavorite(_exercise.name);
    _isCustom = _exercise.visibility != ExerciseVisibility.catalog;
    _ensureCustomFlag();
    _loadDebugMode();
    // Prime the sessions cache immediately so tabs don't need to wait.
    _sessionsFuture = GetIt.instance<WorkoutRepository>().getWorkoutSessions();
  }

  void _refreshSessions() {
    if (!mounted) return;
    setState(() {
      _sessionsFuture = GetIt.instance<WorkoutRepository>()
          .getWorkoutSessions();
    });
  }

  Future<void> _ensureCustomFlag() async {
    try {
      if (!GetIt.I.isRegistered<ExerciseRepository>()) return;
      final repo = GetIt.I<ExerciseRepository>();
      final customList = await repo.getCustomExercises();
      final byId = _exercise.id == null
          ? null
          : customList.firstWhereOrNull((e) => e.id == _exercise.id);
      final byName = customList.firstWhereOrNull(
        (e) => e.name.toLowerCase() == _exercise.name.toLowerCase(),
      );
      final flag = byId != null || byName != null;
      if (mounted && flag != _isCustom) {
        setState(() => _isCustom = flag);
      }
    } catch (_) {
      // ignore; default remains
    }
  }

  Future<void> _loadDebugMode() async {
    try {
      final enabled = await _prefs.getDebugMode();
      if (mounted) setState(() => _debugMode = enabled);
    } catch (_) {}
  }

  void _showSnack(
    String message, {
    HustlSnackVariant variant = HustlSnackVariant.info,
  }) {
    if (!mounted) return;
    HustlSnack.show(
      context,
      message,
      variant: variant,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _generateOverview() async {
    if (_isCustom) {
      _showSnack(
        'Not available for custom exercises',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    if (!GetIt.I.isRegistered<ExerciseRepository>()) {
      _showSnack(
        'Exercise repository not available',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    final repo = GetIt.I<ExerciseRepository>();
    if (repo is! ExerciseRepositoryDebug) {
      _showSnack(
        'Debug generation unavailable',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    setState(() => _generatingOverview = true);
    try {
      final updated = await repo.generateOverviewDebug(_exercise);
      if (!mounted) return;
      setState(() {
        _exercise = _exercise.copyWith(description: updated.description);
      });
      _showSnack('Overview generated', variant: HustlSnackVariant.success);
    } catch (e) {
      debugPrint('Failed to generate overview: $e');
      final msg = e.toString();
      if (msg.contains('Not authenticated')) {
        _showSnack(
          'You need to sign in to do that',
          variant: HustlSnackVariant.error,
        );
      } else {
        _showSnack(
          'Couldn\'t generate the overview',
          variant: HustlSnackVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingOverview = false);
    }
  }

  Future<void> _generateHowTo() async {
    if (_isCustom) {
      _showSnack(
        'Not available for custom exercises',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    if (!GetIt.I.isRegistered<ExerciseRepository>()) {
      _showSnack(
        'Exercise repository not available',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    final repo = GetIt.I<ExerciseRepository>();
    if (repo is! ExerciseRepositoryDebug) {
      _showSnack(
        'Debug generation unavailable',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    setState(() => _generatingHowTo = true);
    try {
      final updated = await repo.generateHowToDebug(_exercise);
      if (!mounted) return;
      setState(() {
        _exercise = _exercise.copyWith(
          steps: updated.steps,
          cues: updated.cues,
        );
      });
      _showSnack('How to generated', variant: HustlSnackVariant.success);
    } catch (e) {
      debugPrint('Failed to generate how-to: $e');
      final msg = e.toString();
      if (msg.contains('Not authenticated')) {
        _showSnack(
          'You need to sign in to do that',
          variant: HustlSnackVariant.error,
        );
      } else {
        _showSnack(
          'Couldn\'t generate the how-to',
          variant: HustlSnackVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingHowTo = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final nowFav = await _prefs.toggleFavoriteExercise(_exercise.name);
    if (!mounted) return;
    setState(() => _isFavorite = nowFav);
    HustlSnack.show(
      context,
      nowFav ? 'Added to favorites' : 'Removed from favorites',
      variant: HustlSnackVariant.success,
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _addToMyExercises() async {
    if (_addingToMine) return;
    if (!GetIt.I.isRegistered<ExerciseRepository>()) {
      _showSnack(
        'Exercise repository not available',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    setState(() => _addingToMine = true);
    try {
      final repo = GetIt.I<ExerciseRepository>();
      final customList = await repo.getCustomExercises();
      final existing = customList.firstWhereOrNull(
        (e) => e.name.toLowerCase() == _exercise.name.toLowerCase(),
      );
      if (existing != null) {
        if (!mounted) return;
        setState(() {
          _exercise = existing;
          _isCustom = true;
        });
        _showSnack('Already in My Exercises');
        return; // info — it was already there, nothing changed
      }

      const uuid = Uuid();
      final copy = Exercise(
        id: uuid.v4(),
        name: _exercise.name,
        muscles: _exercise.muscles,
        imageUrl: _exercise.imageUrl,
        description: _exercise.description,
        steps: _exercise.steps,
        cues: _exercise.cues,
        instructions: _exercise.instructions,
        equipment: _exercise.equipment,
        difficulty: _exercise.difficulty,
        videoUrl: _exercise.videoUrl,
        tags: _exercise.tags,
        isFavorite: _exercise.isFavorite,
        kind: _exercise.kind,
        loggingMode: _exercise.loggingMode,
        visibility: ExerciseVisibility.private,
      );
      final saved = await repo.addCustomExercise(copy);
      if (!mounted) return;
      setState(() {
        _exercise = saved;
        _isCustom = true;
      });
      _showSnack('Added to My Exercises', variant: HustlSnackVariant.success);
    } catch (e) {
      debugPrint('Failed to add to my exercises: $e');
      _showSnack(
        'Couldn\'t add to My Exercises',
        variant: HustlSnackVariant.error,
      );
    } finally {
      if (mounted) setState(() => _addingToMine = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            _exercise.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          systemOverlayStyle: theme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          leading: const HustlMenuButton(),
          actions: [
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.star : Icons.star_border,
                color: _isFavorite
                    ? AppColors.accentWarningAmber
                    : colorScheme.onSurface,
              ),
              onPressed: _toggleFavorite,
            ),
            if (_isCustom)
              IconButton(
                icon: Icon(Icons.edit, color: colorScheme.onSurface),
                tooltip: 'Edit',
                onPressed: _onEdit,
              ),
            if (_isCustom)
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                tooltip: 'Delete',
                onPressed: _onDelete,
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Record'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: ResponsiveCenter(
          maxContentWidth: 800,
          child: TabBarView(
            children: [
              _buildDetailsTab(context),
              _ExerciseRecordTab(
                exercise: _exercise,
                sessionsFuture: _sessionsFuture,
                onRefreshSessions: _refreshSessions,
              ),
              _ExerciseHistoryTab(
                exercise: _exercise,
                sessionsFuture: _sessionsFuture,
                onRetry: _refreshSessions,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Details tab — a single quiet spine of a hero card followed by
  /// SectionHeader-titled content blocks, wrapped in a once-per-session
  /// staggered entrance. The app bar carries the only exercise name (D1); the
  /// hero leads with the muscle figure (or video/image) rather than a repeated
  /// heading.
  Widget _buildDetailsTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasDescription =
        _exercise.description != null &&
        _exercise.description!.trim().isNotEmpty;
    final hasInstructions =
        _exercise.instructions != null &&
        _exercise.instructions!.trim().isNotEmpty;

    final sections = <Widget>[
      _ExerciseHeroCard(
        exercise: _exercise,
        difficultyColor: _exercise.difficulty == null
            ? null
            : _getDifficultyColor(_exercise.difficulty!, colorScheme),
      ),
      if (_exercise.visibility == ExerciseVisibility.public && !_isCustom) ...[
        const SizedBox(height: AppSpacing.x3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: _addingToMine ? null : _addToMyExercises,
            icon: _addingToMine
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('Add to My Exercises'),
          ),
        ),
      ],
      if (_exercise.muscles.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('Muscles worked', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        _MusclesWorked(
          exercise: _exercise,
          // The figure already leads the hero unless a video took its place;
          // only show the inline figure here when the hero is the video.
          showFigure: _hasVideo,
        ),
      ],
      if (hasDescription) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('Overview', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        _OverviewCard(markdown: _exercise.description!),
      ],
      if (_exercise.steps.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('How to', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        _InstructionListCard(items: _exercise.steps, numbered: true),
      ] else if (hasInstructions) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('How to', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        _InstructionMarkdownCard(markdown: _exercise.instructions!),
      ],
      if (_exercise.cues.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('Coaching cues', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        _InstructionListCard(items: _exercise.cues, numbered: false),
      ],
      if (_exercise.tags.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.x3),
        const SectionHeader('Tags', padding: EdgeInsets.zero),
        const SizedBox(height: AppSpacing.x1),
        Wrap(
          spacing: AppSpacing.x1,
          runSpacing: AppSpacing.x1,
          children: [
            for (final tag in _exercise.tags)
              AppChip(
                label: tag,
                variant: AppChipVariant.data,
                icon: Icons.tag,
              ),
          ],
        ),
      ],
      // Dev-only generators, gated behind debug mode and pushed to the bottom
      // so they never read as content next to the real Overview / How-to.
      if (_debugMode && ApiConfig.debugExerciseGenerationEnabled) ...[
        const SizedBox(height: AppSpacing.x3),
        Wrap(
          spacing: AppSpacing.x1,
          runSpacing: AppSpacing.x1,
          children: [
            FilledButton.tonalIcon(
              onPressed: (_isCustom || _generatingOverview || _generatingHowTo)
                  ? null
                  : _generateOverview,
              icon: _generatingOverview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: const Text('Generate overview'),
            ),
            FilledButton.tonalIcon(
              onPressed: (_isCustom || _generatingOverview || _generatingHowTo)
                  ? null
                  : _generateHowTo,
              icon: _generatingHowTo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.format_list_numbered),
              label: const Text('Generate how-to'),
            ),
          ],
        ),
      ],
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x4,
        ),
        children: [
          StaggeredEntrance(
            animationKey:
                'exercise_detail_'
                '${_exercise.canonicalKey ?? _exercise.name.toLowerCase()}',
            children: sections,
          ),
        ],
      ),
    );
  }

  bool get _hasVideo {
    final videoUrl = _exercise.videoUrl?.trim();
    return videoUrl != null && videoUrl.isNotEmpty;
  }

  // Helper method to get color based on difficulty. Beginner reads emerald
  // (tertiary), Intermediate amber. Advanced uses full-strength amber — red
  // stays reserved for destructive/failure (Wave I).
  Color _getDifficultyColor(String difficulty, ColorScheme colorScheme) {
    final bool isDark = colorScheme.brightness == Brightness.dark;
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return colorScheme.tertiary;
      case 'intermediate':
        return AppColors.accentWarningAmber.withValues(
          alpha: isDark ? 0.85 : 1,
        );
      case 'advanced':
        return AppColors.accentWarningAmber;
      default:
        return colorScheme.primary;
    }
  }

  Future<void> _onEdit() async {
    final updated = await showCustomExerciseForm(context, initial: _exercise);
    if (!mounted || updated == null) return;
    setState(() {
      _exercise = updated;
      _isFavorite = _prefs.isExerciseFavorite(_exercise.name);
    });
    HustlSnack.show(
      context,
      'Custom exercise updated',
      variant: HustlSnackVariant.success,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete Custom Exercise?'),
          content: const Text(
            'This removes the exercise from your library. Past workouts remain unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => ctx.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(cs.onErrorContainer),
                backgroundColor: WidgetStatePropertyAll(cs.errorContainer),
              ),
              onPressed: () => ctx.pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      if (!GetIt.I.isRegistered<ExerciseRepository>()) return;
      final repo = GetIt.I<ExerciseRepository>();
      await repo.removeCustomExercise(_exercise);
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Custom exercise deleted',
        variant: HustlSnackVariant.success,
        duration: const Duration(seconds: 2),
      );
      final router = GoRouter.maybeOf(context);
      if (router != null && router.canPop()) {
        context.pop();
      } else if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      dev.log(
        'Failed to delete custom exercise',
        name: 'ExerciseDetailScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      HustlSnack.show(
        context,
        'We couldn\'t delete this exercise. Please try again.',
        variant: HustlSnackVariant.error,
        duration: const Duration(seconds: 3),
      );
    }
  }
}

class _ExerciseRecordTab extends StatefulWidget {
  final Exercise exercise;

  /// Shared sessions future from the parent screen — avoids a redundant fetch.
  final Future<List<WorkoutSession>>? sessionsFuture;

  /// Called when the tab wants to re-fetch (e.g. pull-to-refresh), so the
  /// parent can update [sessionsFuture] for both tabs.
  final VoidCallback? onRefreshSessions;

  const _ExerciseRecordTab({
    required this.exercise,
    this.sessionsFuture,
    this.onRefreshSessions,
  });

  @override
  State<_ExerciseRecordTab> createState() => _ExerciseRecordTabState();
}

class _ExerciseRecordTabState extends State<_ExerciseRecordTab> {
  final _service = const ExerciseRecordService();
  final _prefs = GetIt.instance<PreferencesService>();

  Future<List<WorkoutSession>>? _future;
  int? _lastSignature;
  List<RecordEntry>? _cachedEntries;
  RecordEntry? _cachedPr;
  Map<String, double>? _cachedChart;
  TimeGroup _group = TimeGroup.day;
  bool _use1Rm = false;
  QuickDateRange? _quickRange;
  DateTimeRange? _dateRange;

  ExerciseLoggingMode get _mode => widget.exercise.loggingMode;
  bool get _isWeightReps => _mode == ExerciseLoggingMode.weightReps;
  bool get _isDistanceDuration => _mode == ExerciseLoggingMode.distanceDuration;
  bool get _isDurationOnly => _mode == ExerciseLoggingMode.durationOnly;

  String get _primaryUnit => _isDistanceDuration
      ? 'km'
      : _isWeightReps
      ? 'kg'
      : '';

  String _formatPrimaryValue(double value) {
    if (_isDurationOnly) {
      return TimeFormatUtil.formatMmSs(value.round());
    }
    if (_isDistanceDuration) {
      return NumberFormatUtil.formatDouble(
        value,
        decimalDigits: value % 1 != 0 ? 1 : 0,
      );
    }
    return NumberFormatUtil.formatWeight(value);
  }

  String _formatSecondaryValue(int reps) {
    return _isDistanceDuration
        ? TimeFormatUtil.formatMmSs(reps)
        : reps.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadPrefsAndData();
  }

  @override
  void didUpdateWidget(covariant _ExerciseRecordTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final exerciseChanged = oldWidget.exercise != widget.exercise;
    final futureChanged = oldWidget.sessionsFuture != widget.sessionsFuture;
    if (exerciseChanged) {
      _lastSignature = null;
      _cachedEntries = null;
      _cachedPr = null;
      _cachedChart = null;
    }
    if (exerciseChanged || futureChanged) {
      setState(() {
        _future =
            widget.sessionsFuture ??
            GetIt.instance<WorkoutRepository>().getWorkoutSessions();
      });
    }
  }

  Future<void> _loadPrefsAndData() async {
    final results = await Future.wait<Object?>([
      _prefs.getRecordTimeGroupIndex(),
      _prefs.getRecordUse1Rm(),
      _prefs.getRecordQuickRangeIndex(),
    ]);
    final groupIndex = results[0] as int?;
    final use1rm = results[1] as bool? ?? false;
    final rangeIndex = results[2] as int?;
    if (!mounted) return;
    setState(() {
      if (groupIndex != null &&
          groupIndex >= 0 &&
          groupIndex < TimeGroup.values.length) {
        _group = TimeGroup.values[groupIndex];
      }
      _use1Rm = _isWeightReps ? use1rm : false;
      if (rangeIndex != null &&
          rangeIndex >= 0 &&
          rangeIndex < QuickDateRange.values.length) {
        _quickRange = QuickDateRange.values[rangeIndex];
        _dateRange = quickDateRange(_quickRange!);
      } else {
        _quickRange = null;
        _dateRange = null;
      }
      // Use the shared future from parent when available.
      _future =
          widget.sessionsFuture ??
          GetIt.instance<WorkoutRepository>().getWorkoutSessions();
    });
  }

  Future<void> _refresh() async {
    // Notify parent so both tabs get fresh data.
    widget.onRefreshSessions?.call();
    setState(() {
      _future =
          widget.sessionsFuture ??
          GetIt.instance<WorkoutRepository>().getWorkoutSessions();
    });
    await _future;
  }

  void _maybeRecomputeCache(List<WorkoutSession> sessions) {
    // Apply date range filter if selected
    final filtered = filterSessionsByDate(sessions, _dateRange);
    final useEstimated1Rm = _isWeightReps && _use1Rm;
    // Compute a signature that captures relevant inputs
    final sig = _computeSignature(filtered, useEstimated1Rm);
    if (_lastSignature == sig &&
        _cachedEntries != null &&
        _cachedChart != null) {
      return;
    }
    final entries = _service.buildEntries(filtered, widget.exercise);
    // Choose a sensible default grouping based on time span when first loading
    if (_cachedEntries == null && entries.isNotEmpty) {
      final days = entries.last.date.difference(entries.first.date).inDays;
      _group = days <= 7
          ? TimeGroup.day
          : days <= 90
          ? TimeGroup.week
          : TimeGroup.month;
    }
    final pr = _service.findPersonalRecord(entries, widget.exercise);
    final chart = _service.generateChartData(
      entries,
      group: _group,
      useEstimated1Rm: useEstimated1Rm,
      exercise: widget.exercise,
    );
    _lastSignature = sig;
    _cachedEntries = entries;
    _cachedPr = pr;
    _cachedChart = chart;
  }

  int _computeSignature(List<WorkoutSession> sessions, bool useEstimated1Rm) {
    return Object.hashAll([
      sessions.length,
      ...sessions.map(
        (s) => (s.lastUpdatedAt ?? s.startTime).millisecondsSinceEpoch,
      ),
      _group.index,
      useEstimated1Rm,
      _quickRange?.index ?? -1,
      (widget.exercise.canonicalKey ?? widget.exercise.name.toLowerCase()),
    ]);
  }

  String _labelForRange(QuickDateRange r) {
    switch (r) {
      case QuickDateRange.last2Weeks:
        return '2w';
      case QuickDateRange.last1Month:
        return '1m';
      case QuickDateRange.last3Months:
        return '3m';
      case QuickDateRange.last6Months:
        return '6m';
      case QuickDateRange.last1Year:
        return '1y';
    }
  }

  Widget _buildRecordEmpty(BuildContext context) {
    return ScreenEmptyState(
      assetIcon: 'assets/icons/empty_chart.svg',
      icon: Icons.emoji_events_outlined,
      title: 'No records yet',
      message:
          'Log this exercise in a workout and your PR and progress chart appear '
          'here.',
      actionLabel: 'Start a workout',
      onAction: () =>
          context.go('/workout_session', extra: workoutRouteExtra(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkoutSession>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const HustlInlineSkeleton();
        }
        if (snapshot.hasError) {
          return ScreenEmptyState(
            icon: Icons.error_outline,
            title: "We couldn't load your records",
            message: 'Something interrupted the load. Give it another go.',
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }
        final data = snapshot.data ?? const <WorkoutSession>[];
        _maybeRecomputeCache(data);
        final entries = _cachedEntries ?? const <RecordEntry>[];
        if (entries.isEmpty) {
          return _buildRecordEmpty(context);
        }

        final pr = _cachedPr;
        if (pr == null) {
          return _buildRecordEmpty(context);
        }
        final chartData = _cachedChart ?? const <String, double>{};
        final primaryUnit = _primaryUnit;

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final chartHeight = (MediaQuery.of(context).size.height * 0.25).clamp(
          160.0,
          280.0,
        );

        final prCount = _service.countPrSets(data, widget.exercise);
        final lastPr = _service.lastPrDate(data, widget.exercise);

        final milestoneIndices = _service.prMilestoneIndices(chartData);
        final show1Rm = _isWeightReps && _use1Rm;
        final nextTarget = _service.suggestNextTarget(
          chartData,
          widget.exercise,
        );
        final nextTargetLabel = show1Rm
            ? 'Next target · est. 1RM'
            : 'Next target';
        final targetUnit = _isDistanceDuration ? 'km' : (show1Rm ? '' : 'kg');
        final nextTargetValue = nextTarget == null
            ? null
            : (targetUnit.isEmpty
                  ? _formatPrimaryValue(nextTarget)
                  : '${_formatPrimaryValue(nextTarget)} $targetUnit');

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Quick ranges
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _RangeChip(
                      label: 'All',
                      selected: _quickRange == null,
                      onSelected: () {
                        setState(() {
                          _quickRange = null;
                          _dateRange = null;
                          // Force recompute
                          _lastSignature = null;
                        });
                        _prefs.setRecordQuickRangeIndex(null);
                      },
                    ),
                    for (final r in QuickDateRange.values) ...[
                      const SizedBox(width: 8),
                      _RangeChip(
                        label: _labelForRange(r),
                        selected: _quickRange == r,
                        onSelected: () {
                          setState(() {
                            _quickRange = r;
                            _dateRange = quickDateRange(r);
                            _lastSignature = null;
                          });
                          _prefs.setRecordQuickRangeIndex(r.index);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _RecordHighlight(
                title: 'Personal record',
                value: _isDurationOnly
                    ? _formatPrimaryValue(pr.set.reps.toDouble())
                    : '${_formatPrimaryValue(pr.set.weight)} $primaryUnit × ${_formatSecondaryValue(pr.set.reps)}',
                // Count up the leading PR weight numeral only when it reads
                // cleanly as a grouped integer (weight × reps). Distance/duration
                // formats (decimals, km, mm:ss) stay static.
                heroValue: (_isWeightReps && pr.set.weight % 1 == 0)
                    ? pr.set.weight
                    : null,
                heroSuffix:
                    ' $primaryUnit × ${_formatSecondaryValue(pr.set.reps)}',
                helperText: 'Best set on record',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(label: 'PRs', value: prCount.toString()),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: _MiniStat(
                      label: 'Last PR',
                      value: lastPr == null
                          ? '—'
                          : DateFormat.yMMMd().format(lastPr.toLocal()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (nextTargetValue != null)
                _MiniStat(label: nextTargetLabel, value: nextTargetValue),
              const SizedBox(height: 12),
              SegmentedPillSelector<TimeGroup>(
                options: TimeGroup.values,
                selected: _group,
                labels: const {
                  TimeGroup.day: 'Day',
                  TimeGroup.week: 'Week',
                  TimeGroup.month: 'Month',
                },
                onSelect: (selected) {
                  if (selected == _group) return;
                  setState(() {
                    _group = selected;
                    if (_cachedEntries != null) {
                      _cachedChart = _service.generateChartData(
                        _cachedEntries!,
                        group: _group,
                        useEstimated1Rm: _isWeightReps && _use1Rm,
                        exercise: widget.exercise,
                      );
                    }
                  });
                  _prefs.setRecordTimeGroupIndex(_group.index);
                },
              ),
              const SizedBox(height: 12),
              // Time range is the most-changed dimension, so it keeps the
              // full-width segmented control above. The Weight/Est. 1RM metric
              // is a secondary refinement, demoted to a compact header toggle so
              // the two controls don't stack into a confusing "double tab".
              if (_isWeightReps) ...[
                SectionHeader(
                  'Trend',
                  padding: EdgeInsets.zero,
                  trailing: MiniPillToggle(
                    options: const ['Weight', 'Est. 1RM'],
                    selectedIndex: _use1Rm ? 1 : 0,
                    onSelect: (i) {
                      final v = i == 1;
                      if (v == _use1Rm) return;
                      setState(() {
                        _use1Rm = v;
                        if (_cachedEntries != null) {
                          _cachedChart = _service.generateChartData(
                            _cachedEntries!,
                            group: _group,
                            useEstimated1Rm: _use1Rm,
                            exercise: widget.exercise,
                          );
                        }
                      });
                      _prefs.setRecordUse1Rm(_use1Rm);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 12),
              RepaintBoundary(
                child: SizedBox(
                  height: chartHeight,
                  child: LineChartTimeSeries(
                    data: chartData,
                    group: _group,
                    yUnit: _isDurationOnly ? 's' : (show1Rm ? '' : primaryUnit),
                    highlightIndices: milestoneIndices,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Sentence-case section heading for the records list.
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0, top: 4.0),
                child: Text(
                  'Records',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              // One grouped surface card with hairline-divided rows — best set
              // per session, the PR row flagged with a blue trophy. Replaces the
              // old zebra DataTable / bordered compact list.
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = entries.length - 1; i >= 0; i--) ...[
                      if (i < entries.length - 1) const Divider(),
                      () {
                        final e = entries[i];
                        final isPr =
                            identical(e, pr) ||
                            (e.set.weight == pr.set.weight &&
                                e.set.reps == pr.set.reps &&
                                e.date == pr.date);
                        final dateStr = DateFormat.yMMMd().format(
                          e.date.toLocal(),
                        );
                        final primaryStr = _isDurationOnly
                            ? _formatPrimaryValue(e.set.reps.toDouble())
                            : _formatPrimaryValue(e.set.weight);
                        final secondaryStr = _isDurationOnly
                            ? null
                            : _formatSecondaryValue(e.set.reps);
                        final oneRmStr = show1Rm
                            ? NumberFormatUtil.formatDouble(
                                _service.estimate1Rm(e.set.weight, e.set.reps),
                              )
                            : null;
                        final summary = _isDurationOnly
                            ? primaryStr
                            : '$primaryStr $primaryUnit × $secondaryStr';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              if (isPr) ...[
                                Icon(
                                  Icons.emoji_events,
                                  color: colorScheme.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  dateStr,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              // The summary, effort gauge, and 1RM label can
                              // together outgrow a narrow row (e.g. a PR set
                              // with logged effort while the 1RM label is
                              // showing). Wrap so the trailing cluster reflows
                              // onto a second line instead of overflowing.
                              Flexible(
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      summary,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                    if (e.set.rpe != null)
                                      EffortReserveGauge(rpe: e.set.rpe),
                                    if (show1Rm && oneRmStr != null)
                                      Text(
                                        '1RM $oneRmStr',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Record-tab hero (Wave I — "data as hero"): a single elevated card with
/// a blue trophy ring on the left and the personal-record value as a big
/// tabular numeral on the right.
class _RecordHighlight extends StatelessWidget {
  final String title;
  final String value;
  final String helperText;

  /// When provided, the leading PR numeral counts up (0 → target as data
  /// loads) while [heroSuffix] (e.g. ` kg × 5`) stays static. Falls back to the
  /// plain [value] string when null (e.g. duration-only mm:ss, which can't be
  /// grouped). Reduce-motion is handled by [AnimatedMetricText] (it snaps).
  final double? heroValue;
  final String heroSuffix;

  const _RecordHighlight({
    required this.title,
    required this.value,
    required this.helperText,
    this.heroValue,
    this.heroSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final heroValueStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 30,
      height: 1.05,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final valueWidget = heroValue == null
        ? Text(value, style: heroValueStyle)
        : AnimatedMetricText(
            value: heroValue!,
            grouped: true,
            suffix: heroSuffix,
            style: heroValueStyle,
            semanticsLabel: title,
          );

    return Semantics(
      label: title,
      value: value,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppProgressRing(
                progress: 1,
                size: 104,
                strokeWidth: 11,
                color: colorScheme.primary,
                trackColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
                child: HustlIcon(
                  asset: 'assets/icons/ic_trophy.svg',
                  size: 34,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    valueWidget,
                    const SizedBox(height: 4),
                    Text(
                      helperText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // §12.1: flat filter chip — blue 10% tint + blue w600 when selected.
    return AppChip(
      label: label,
      variant: AppChipVariant.filter,
      selected: selected,
      onTap: onSelected,
    );
  }
}

class _ExerciseHistoryTab extends StatelessWidget {
  final Exercise exercise;

  /// Shared sessions future from the parent screen — avoids a redundant fetch.
  final Future<List<WorkoutSession>>? sessionsFuture;

  /// Asks the parent to re-fetch sessions (used by the error "Try again").
  final VoidCallback? onRetry;

  const _ExerciseHistoryTab({
    required this.exercise,
    this.sessionsFuture,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final mode = exercise.loggingMode;
    final isDistanceDuration = mode == ExerciseLoggingMode.distanceDuration;
    final isDurationOnly = mode == ExerciseLoggingMode.durationOnly;
    // Fall back to a direct repo call only if no shared future was provided.
    final future =
        sessionsFuture ??
        GetIt.instance<WorkoutRepository>().getWorkoutSessions();
    return FutureBuilder<List<WorkoutSession>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const HustlInlineSkeleton();
        }
        if (snapshot.hasError) {
          return ScreenEmptyState(
            icon: Icons.error_outline,
            title: "We couldn't load your history",
            message: 'Something interrupted the load. Give it another go.',
            actionLabel: 'Try again',
            onAction: onRetry,
          );
        }
        final sessions = (snapshot.data ?? const <WorkoutSession>[])
            .where((s) => s.isCompleted)
            .toList();
        final items = <_HistoryItem>[];
        final targetName = exercise.name;
        final targetSlug = exercise.slug;
        String formatPrimary(double value) {
          if (isDistanceDuration) {
            return NumberFormatUtil.formatDouble(
              value,
              decimalDigits: value % 1 != 0 ? 1 : 0,
            );
          }
          return NumberFormatUtil.formatWeight(value);
        }

        String formatSecondary(int reps) =>
            (isDistanceDuration || isDurationOnly)
            ? TimeFormatUtil.formatMmSs(reps)
            : reps.toString();
        for (final s in sessions) {
          final ex = s.exercises.firstWhereOrNull(
            (e) =>
                e.exercise.matchesIdentity(name: targetName, slug: targetSlug),
          );
          if (ex == null) continue;
          final completedSets = ex.sets
              .where((x) => x.isCompleted)
              .toList(growable: false);
          if (completedSets.isEmpty) {
            // Skip sessions where the exercise was added but never logged.
            continue;
          }
          final best = completedSets.reduce((a, b) {
            if (isDurationOnly) {
              return b.reps > a.reps ? b : a;
            }
            if (isDistanceDuration) {
              if (b.weight != a.weight) return b.weight > a.weight ? b : a;
              // For same distance, prefer faster time.
              return b.reps < a.reps ? b : a;
            }
            return (b.weight > a.weight ||
                    (b.weight == a.weight && b.reps > a.reps))
                ? b
                : a;
          });
          items.add(_HistoryItem(session: s, best: best));
        }
        items.sort(
          (a, b) => b.session.startTime.compareTo(a.session.startTime),
        );
        if (items.isEmpty) {
          return const ScreenEmptyState(
            assetIcon: 'assets/icons/empty_history.svg',
            icon: Icons.history,
            title: 'No history yet',
            message:
                'Once you log this exercise in a workout, every session shows '
                'up here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final it = items[i];
            final date = it.session.startTime.toLocal();
            // Resolve exercise for this session to list all sets
            final ex = it.session.exercises.firstWhereOrNull(
              (e) => e.exercise.matchesIdentity(
                name: targetName,
                slug: targetSlug,
              ),
            );
            final sets =
                (ex?.sets.where((s) => s.isCompleted).toList() ??
                const <WorkoutSet>[]);
            final scheme = Theme.of(context).colorScheme;
            final metricStyle = Theme.of(context).textTheme.labelMedium
                ?.copyWith(
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
            // Each set is a fixed-height aligned row (metric left, effort gauge
            // right) with a hairline between rows — the same rhythm the Records
            // list uses — so the reserve gauges line up in a clean column down
            // the session rather than ragged shrink-wrapped chips.
            final setRows = <Widget>[];
            for (var si = 0; si < sets.length; si++) {
              if (si > 0) {
                setRows.add(
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: scheme.outlineVariant,
                  ),
                );
              }
              final s = sets[si];
              setRows.add(
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 34),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            isDurationOnly
                                ? formatSecondary(s.reps)
                                : '${formatPrimary(s.weight)} ${isDistanceDuration ? 'km' : 'kg'} × ${formatSecondary(s.reps)}',
                            style: metricStyle,
                          ),
                        ),
                        if (s.rpe != null) EffortReserveGauge(rpe: s.rpe),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                isThreeLine: true,
                title: Text(
                  '${DateFormat.yMMMd().format(date)} • ${DateFormat('h:mm a').format(date)}',
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: setRows,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: () {
                  final r = GoRouter.maybeOf(context);
                  r?.push(
                    '/summary/${it.session.id}',
                    extra: {
                      'highlightExerciseKey':
                          exercise.canonicalKey ?? exercise.name.toLowerCase(),
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _HistoryItem {
  final WorkoutSession session;
  final WorkoutSet? best;
  _HistoryItem({required this.session, required this.best});
}

class _InstructionMarkdownCard extends StatelessWidget {
  final String markdown;
  const _InstructionMarkdownCard({required this.markdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: AppSpacing.cardPadding,
      child: MarkdownBody(
        data: markdown,
        styleSheet: MarkdownStyleSheet(
          strong: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          p: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            height: 1.6,
          ),
          listBullet: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _InstructionListCard extends StatelessWidget {
  final List<String> items;
  final bool numbered;

  const _InstructionListCard({required this.items, required this.numbered});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget leading(int index) {
      if (!numbered) {
        return Icon(
          Icons.check_circle_outline,
          size: 18,
          color: colorScheme.primary,
        );
      }
      return Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          '${index + 1}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      child: Column(
        children: [
          for (final entry in items.asMap().entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading(entry.key),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Resolves an exercise's flat `muscles` string list into mapped [MuscleGroup]s
/// for the figure, keeping the raw labels for chip display. Pure for testability.
class _ResolvedMuscles {
  const _ResolvedMuscles({required this.groups, required this.labels});

  /// SVG-renderable muscle groups (unmappable strings dropped from the figure).
  final Set<MuscleGroup> groups;

  /// Display labels — mapped muscles use [MuscleGroup.label], unmapped strings
  /// keep their raw text so no muscle is silently lost from the chip row.
  final List<String> labels;

  static _ResolvedMuscles from(List<String> muscles) {
    final labels = <String>[];
    for (final raw in muscles) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final keyGroup = muscleGroupFromKey(trimmed);
      final hasKeyGroup = keyGroup != null && keyGroup != MuscleGroup.other;
      // Chip label: storage keys use the canonical group label; everything
      // else keeps its catalog text so no muscle is silently relabeled.
      labels.add(hasKeyGroup ? keyGroup.label : trimmed);
    }
    // Figure groups use the shared resolver (display labels + storage keys),
    // keeping the hero figure and the template thumbnails consistent.
    return _ResolvedMuscles(
      groups: figureMuscleGroups(muscles),
      labels: labels,
    );
  }
}

/// The Details-tab hero: a flat premium surface card (radius 20, no border) that
/// leads with the muscle figure (or the video/image when present) and a quiet
/// metadata strip of difficulty + equipment chips. Wrapped in the shared Hero
/// tag so the list -> detail media handoff stays seamless.
class _ExerciseHeroCard extends StatelessWidget {
  const _ExerciseHeroCard({required this.exercise, this.difficultyColor});

  final Exercise exercise;
  final Color? difficultyColor;

  static const double _heroRadius = 20;
  static const double _mediaHeight = 132;

  bool get _hasVideo {
    final url = exercise.videoUrl?.trim();
    return url != null && url.isNotEmpty;
  }

  bool get _hasImage {
    final url = exercise.imageUrl?.trim();
    return url != null && url.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final innerRadius = BorderRadius.circular(
      AppRadius.concentric(_heroRadius, AppSpacing.x2),
    );

    final hasMeta =
        exercise.difficulty != null || exercise.equipment.isNotEmpty;

    final metaColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (exercise.difficulty != null)
          AppChip(
            label: exercise.difficulty!,
            variant: AppChipVariant.status,
            color: difficultyColor,
          ),
        if (exercise.difficulty != null && exercise.equipment.isNotEmpty)
          const SizedBox(height: AppSpacing.x1),
        if (exercise.equipment.isNotEmpty)
          AppChip(
            label: 'Equipment',
            variant: AppChipVariant.data,
            value: exercise.equipment.join(', '),
          ),
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_heroRadius),
      ),
      padding: AppSpacing.cardPadding,
      child: hasMeta
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _mediaHeight,
                  height: _mediaHeight,
                  child: ClipRRect(
                    borderRadius: innerRadius,
                    child: _buildMedia(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(child: metaColumn),
              ],
            )
          : SizedBox(
              height: _mediaHeight,
              child: ClipRRect(
                borderRadius: innerRadius,
                child: _buildMedia(context),
              ),
            ),
    );

    return Hero(tag: 'exercise_image_${exercise.name}', child: card);
  }

  /// Hero media priority: video wins, then image (falling back to the figure on
  /// error), otherwise the muscle figure is the default — never a grey void.
  Widget _buildMedia(BuildContext context) {
    if (_hasVideo) {
      return VideoPlayerWidget(videoUrl: exercise.videoUrl!.trim());
    }

    final figure = MuscleFigure(
      primary: _ResolvedMuscles.from(exercise.muscles).groups,
      height: _mediaHeight,
    );

    if (_hasImage) {
      final imageUrl = exercise.imageUrl!.trim();
      if (imageUrl.startsWith('assets/')) {
        return Image.asset(
          imageUrl,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => figure,
        );
      }
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        fadeInDuration: AppMotion.medium,
        fadeOutDuration: AppMotion.fast,
        placeholder: (_, __) => const AppSkeleton(
          width: double.infinity,
          height: double.infinity,
          borderRadius: AppRadius.cardRadius,
        ),
        errorWidget: (_, __, ___) => figure,
      );
    }

    return figure;
  }
}

/// The "Muscles worked" section: primary muscle chips keyed to the figure tint.
/// When a video took the hero, an inline figure is shown beside the chips so
/// muscle context is never lost.
class _MusclesWorked extends StatelessWidget {
  const _MusclesWorked({required this.exercise, this.showFigure = false});

  final Exercise exercise;
  final bool showFigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolved = _ResolvedMuscles.from(exercise.muscles);

    final chips = Wrap(
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      children: [
        for (final label in resolved.labels)
          AppChip(
            label: label,
            variant: AppChipVariant.status,
            color: colorScheme.primary,
          ),
      ],
    );

    if (!showFigure) return chips;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: MuscleFigure(primary: resolved.groups, height: 72),
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(child: chips),
      ],
    );
  }
}

/// Flat surface Overview card (no border) holding the rendered markdown.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: AppSpacing.cardPadding,
      child: MarkdownBody(
        data: markdown,
        styleSheet: MarkdownStyleSheet(
          h1: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          h2: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          strong: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          p: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            height: 1.6,
          ),
          listBullet: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
