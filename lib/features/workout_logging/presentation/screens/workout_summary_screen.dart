import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';

import '../../data/datasources/hustl_backend_workout_history_api.dart';
import '../../data/mappers/workout_server_mapper.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_session_stats.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/utils/workout_date_label.dart';
import '../../../health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../../health_sync/domain/usecases/load_latest_readiness.dart';
import '../../../onboarding/domain/onboarding_proposal_gate.dart';
import '../../../onboarding/onboarding_flags.dart';
import '../../../workout_log/domain/services/body_score_service.dart';
import '../../../workout_templates/data/services/template_sync_service.dart';
import '../../../workout_templates/domain/models/workout_template.dart';
import '../../../workout_templates/domain/repositories/template_repository.dart';
import '../widgets/summary/save_template_sheet.dart';
import '../widgets/summary/summary_celebration_hero.dart';
import '../widgets/summary/summary_es_recap.dart';
import '../widgets/summary/summary_muscle_heatmap.dart';
import '../widgets/summary/summary_pr_cards.dart';
import '../widgets/summary/strain_recovery_note.dart';
import '../widgets/workout_exercise_summary_list.dart';

// Re-export the session/template domain helpers so existing call sites that
// import them from this screen keep compiling after the move to the domain
// layer.
export '../../domain/models/workout_session_stats.dart'
    show WorkoutSessionStats, WorkoutExerciseTemplateConversion;

class WorkoutSummaryScreen extends StatefulWidget {
  final String sessionId;
  final String? highlightExerciseKey;
  final HustlBackendWorkoutHistoryApi? historyApiOverride;

  /// Whether this summary is the just-finished post-workout flow (reached via
  /// `go('/summary/:id')` from the active workout) rather than a historical
  /// summary opened from History. Only the just-finished flow shows the
  /// post-workout recovery note, since today's readiness is meaningless next to
  /// a workout logged days ago. Defaults to `false` so history/deep-link
  /// entries (and legacy callers) never surface a stale "today's recovery" note.
  final bool justFinished;

  const WorkoutSummaryScreen({
    super.key,
    required this.sessionId,
    this.highlightExerciseKey,
    this.historyApiOverride,
    this.justFinished = false,
  });

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  final _workoutRepository = GetIt.instance<WorkoutRepository>();
  final _templateRepository = GetIt.instance<TemplateRepository>();
  final _bodyScoreService = BodyScoreService();
  bool _celebrated = false;

  WorkoutSession? _session;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isRemoteOnlySession = false;
  List<WorkoutTemplate> _existingTemplates = [];
  Map<DisplayRegion, double> _esCredits = const {};
  DailyRecoverySnapshot? _recovery;

  @override
  void initState() {
    super.initState();
    _loadWorkoutSession();
    _loadExistingTemplates();
    _loadRecovery();
    // After the summary is on the stack, maybe surface the onboarding AI "magic
    // moment" over it (post-workout only). Best-effort; pushed (never replaces)
    // so dismissing returns to this summary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowStarterProposal();
    });
  }

  /// Surfaces the onboarding starter-proposal "magic moment" over the summary
  /// when the user is eligible (gated by [OnboardingProposalGate]). Gated to the
  /// just-finished post-workout flow, skipped in tests and when DI is absent,
  /// and fully best-effort: any failure leaves the summary exactly as today.
  Future<void> _maybeShowStarterProposal() async {
    // Kill switch: a flag-off build never surfaces the v3 starter-proposal moment.
    if (!kOnboardingV3Enabled) return;
    if (!widget.justFinished || _isTestEnv()) return;
    if (!GetIt.instance.isRegistered<OnboardingProposalGate>()) return;
    try {
      final eligible = await GetIt.instance<OnboardingProposalGate>()
          .isEligible();
      if (!eligible || !mounted) return;
      context.push('/onboarding/proposal');
    } catch (_) {
      // The magic moment is a delight, never a blocker.
    }
  }

  /// Lazily reads the latest readiness snapshot for the quiet post-workout
  /// strain-vs-recovery note. Reuses the shared recovery pipeline; never blocks
  /// the summary and silently no-ops on any error or missing DI, so the summary
  /// renders exactly as today when recovery data is absent.
  ///
  /// Gated to the just-finished flow: a historical summary opened from History
  /// must never annotate an old workout with today's readiness, so we skip the
  /// read entirely unless this is the post-workout flow.
  Future<void> _loadRecovery() async {
    if (!widget.justFinished) return;
    if (!GetIt.instance.isRegistered<LoadLatestReadinessUseCase>()) return;
    try {
      final recovery = await GetIt.instance<LoadLatestReadinessUseCase>()();
      if (!mounted || recovery == null) return;
      setState(() => _recovery = recovery);
    } catch (_) {
      // The note is a pure annotation; absence leaves the summary as today.
    }
  }

  bool _isTestEnv() {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTestWidgetsFlutterBinding');
  }

  Future<void> _loadWorkoutSession() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final local = await _workoutRepository.getWorkoutSession(
        widget.sessionId,
      );
      final loaded = local ?? await _tryFetchRemoteWorkout(widget.sessionId);
      if (!mounted) return;
      if (loaded == null) {
        HustlSnack.show(
          context,
          'Workout session not found',
          variant: HustlSnackVariant.warning,
        );
        context.pop();
        return;
      }
      setState(() {
        _session = loaded;
        _isRemoteOnlySession = local == null;
        _isLoading = false;
        _esCredits = _computeEsCredits(loaded);
      });
      _celebrate();
    } catch (e, s) {
      if (!mounted) return;
      dev.log(
        'Failed to load workout session',
        name: 'WorkoutSummaryScreen',
        error: e,
        stackTrace: s,
      );
      setState(() {
        _isLoading = false;
        _isRemoteOnlySession = false;
        _esCredits = const {};
        _loadFailed = true;
      });
      HustlSnack.show(
        context,
        'We couldn\'t load this workout. Check your connection and try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  void _celebrate() {
    if (_celebrated || _isTestEnv()) return;
    _celebrated = true;
    // Paired with the spring + ring entrance in the celebration hero.
    Haptics.celebrate();
  }

  Future<WorkoutSession?> _tryFetchRemoteWorkout(String sessionId) async {
    final tokens = GetIt.instance.isRegistered<TokenStorage>()
        ? GetIt.instance<TokenStorage>()
        : TokenStorage();
    final access = await tokens.getAccessToken();
    if (access == null || access.isEmpty) return null;

    final api =
        widget.historyApiOverride ??
        HustlBackendWorkoutHistoryApi(tokens: tokens);
    try {
      final map = await api.fetchWorkoutDetail(sessionId);
      return WorkoutServerMapper.sessionFromServerMap(map);
    } on HustlBackendWorkoutHistoryApiException catch (e) {
      if (e.statusCode == 404 || e.code == 'not_found') return null;
      rethrow;
    }
  }

  Map<DisplayRegion, double> _computeEsCredits(WorkoutSession session) {
    final end = session.endTime ?? session.startTime;
    final range = DateTimeRange(start: session.startTime, end: end);
    final metrics = _bodyScoreService.aggregateForRange([session], range);
    final totals = <DisplayRegion, double>{
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final entry in metrics.entries) {
      totals[entry.key.displayRegion] =
          (totals[entry.key.displayRegion] ?? 0.0) + entry.value.sets;
    }
    final entries =
        totals.entries
            .where((e) => e.key != DisplayRegion.other && e.value > 0.1)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return Map<DisplayRegion, double>.fromEntries(entries);
  }

  Future<void> _loadExistingTemplates() async {
    try {
      final templates = await _templateRepository.getWorkoutTemplates();
      if (!mounted) return;
      setState(() => _existingTemplates = templates);
    } catch (_) {
      // Non-fatal: the save sheet simply offers "create new" only.
    }
  }

  Future<void> _onSaveTemplate() async {
    final session = _session;
    if (session == null) return;
    final choice = await showSaveTemplateSheet(
      context,
      defaultName: session.name,
      existingTemplates: _existingTemplates,
    );
    if (choice == null || !mounted) return;

    try {
      final exercises = session.exercises
          .map((e) => e.toTemplateExercise())
          .toList();
      if (choice.template == null) {
        await _templateRepository.createWorkoutTemplate(
          WorkoutTemplate(
            id: '',
            name: choice.name,
            description:
                'Created from workout on ${WorkoutDateLabel.absolute(session.startTime)}',
            exercises: exercises,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        await _templateRepository.updateWorkoutTemplate(
          choice.template!.copyWith(
            description:
                'Updated from workout on ${WorkoutDateLabel.absolute(session.startTime)}',
            exercises: exercises,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (GetIt.I.isRegistered<TemplateSyncService>()) {
        // ignore: unawaited_futures
        GetIt.I<TemplateSyncService>().syncNow();
      }
      if (!mounted) return;
      final label = choice.template?.name ?? choice.name;
      HustlSnack.show(
        context,
        'Saved "$label" as a template',
        variant: HustlSnackVariant.success,
      );
      context.go('/');
    } catch (e, s) {
      dev.log(
        'Failed to save template from summary',
        name: 'WorkoutSummaryScreen',
        error: e,
        stackTrace: s,
      );
      if (!mounted) return;
      HustlSnack.show(
        context,
        'We couldn\'t save this as a template. Please try again.',
        variant: HustlSnackVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isLoading && _session == null && _loadFailed) {
      return MainScaffold(
        appBar: AppBar(
          title: const Text('Workout summary'),
          leading: const HustlMenuButton(),
        ),
        child: ScreenEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'We couldn\'t load this workout',
          message:
              'Something went wrong loading the summary. Check your connection '
              'and try again.',
          actionLabel: 'Try again',
          onAction: _loadWorkoutSession,
        ),
      );
    }
    if (_isLoading || _session == null) {
      return MainScaffold(
        appBar: AppBar(
          title: const Text('Workout summary'),
          leading: const HustlMenuButton(),
        ),
        child: const HustlInlineSkeleton(),
      );
    }

    final session = _session!;
    final prs = prEntriesFromSession(session);
    final heroMetric = _heroMetricFor(session);

    return MainScaffold(
      appBar: AppBar(
        title: const Text('Workout summary'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        // Adaptive leading: a back button when pushed (e.g. from History), the
        // account avatar when reached terminally via go() from finish
        // (canPop false). Replaces Material's automaticallyImplyLeading.
        leading: const HustlMenuButton(),
        actions: [
          if (!_isRemoteOnlySession)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit workout',
              onPressed: () async {
                await context.push('/workout_edit/${session.id}');
                if (mounted) await _loadWorkoutSession();
              },
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View history',
            onPressed: () => context.go('/history'),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: AppSpacing.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryCelebrationHero(
              title: 'Workout complete',
              subtitle: _subtitleFor(session, prs.length),
              exercises: session.exercises
                  .where((ex) => ex.sets.any((s) => s.reps > 0))
                  .length,
              prs: session.countPrSets(),
              metricValue: heroMetric.value,
              metricUnitLabel: heroMetric.unitLabel,
              metricSemanticsLabel: heroMetric.semanticsLabel,
              metricFractionDigits: heroMetric.fractionDigits,
              heroSessionId: session.id,
            ),
            if (prs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x3),
              SummaryPrCards(entries: prs),
            ],
            if (_esCredits.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x3),
              SummaryMuscleHeatmap(credits: _esCredits),
            ],
            const SizedBox(height: AppSpacing.x3),
            _DetailsSection(session: session),
            ...?_recoveryNote(),
            const SizedBox(height: AppSpacing.x3),
            SummaryEsRecap(
              session: session,
              bodyScoreService: _bodyScoreService,
              credits: _esCredits,
            ),
            const SizedBox(height: AppSpacing.x3),
            WorkoutExerciseSummaryList(
              exercises: session.exercises,
              showTitle: true,
              highlightExerciseKey: widget.highlightExerciseKey,
            ),
            if ((session.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x3),
              _NotesSection(notes: session.notes!.trim()),
            ],
            const SizedBox(height: AppSpacing.x3),
            OutlinedButton.icon(
              onPressed: _onSaveTemplate,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save as template'),
            ),
            const SizedBox(height: AppSpacing.x1),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  /// The quiet post-workout strain-vs-recovery note, gated on a present,
  /// reasonably-confident snapshot. Returns `null` (rendered as nothing) when
  /// recovery data is absent, so the summary stays identical to today.
  List<Widget>? _recoveryNote() {
    final note = StrainRecoveryNote.maybe(_recovery);
    if (note == null) return null;
    return [const SizedBox(height: AppSpacing.x2), note];
  }

  /// Picks the hero ring's big metric. Weight sessions centre on kg volume;
  /// a cardio/duration-only session centres on distance (or time when no
  /// distance was logged) so the hero never celebrates "0 kg volume".
  ({double value, String unitLabel, String semanticsLabel, int fractionDigits})
  _heroMetricFor(WorkoutSession session) {
    final hasWeightWork = session.exercises.any(
      (ex) => ex.exercise.loggingMode == ExerciseLoggingMode.weightReps,
    );
    if (hasWeightWork) {
      return (
        value: session.calculateTotalVolume().toDouble(),
        unitLabel: 'kg volume',
        semanticsLabel: 'Total volume',
        fractionDigits: 0,
      );
    }

    double distanceKm = 0;
    int durationSeconds = 0;
    for (final ex in session.exercises) {
      for (final set in ex.sets) {
        if (ex.exercise.loggingMode == ExerciseLoggingMode.distanceDuration) {
          if (set.weight > 0) distanceKm += set.weight;
        }
        if (set.reps > 0) durationSeconds += set.reps;
      }
    }
    if (distanceKm > 0) {
      return (
        value: distanceKm,
        unitLabel: 'km distance',
        semanticsLabel: 'Total distance',
        fractionDigits: distanceKm.truncateToDouble() == distanceKm ? 0 : 1,
      );
    }
    final minutes = durationSeconds > 0
        ? durationSeconds / 60
        : session.duration.inSeconds / 60;
    return (
      value: minutes,
      unitLabel: 'min duration',
      semanticsLabel: 'Total duration',
      fractionDigits: 0,
    );
  }

  String _subtitleFor(WorkoutSession session, int prCount) {
    if (prCount > 0) {
      return prCount == 1
          ? 'You set a new personal record'
          : 'You set $prCount new personal records';
    }
    final minutes = session.duration.inMinutes;
    if (minutes >= 1) {
      return 'Logged in ${WorkoutDateLabel.relative(session.startTime).toLowerCase()} · $minutes min';
    }
    return 'Great work finishing strong';
  }
}

/// Flat session details: aligned 15px label/value rows between hairlines.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final duration = session.endTime != null
        ? session.endTime!.difference(session.startTime)
        : DateTime.now().difference(session.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationText = hours > 0
        ? '$hours hr${minutes > 0 ? ' $minutes min' : ''}'
        : (minutes > 0 ? '$minutes min' : 'Just started');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Details', padding: EdgeInsets.only(bottom: 4)),
        SectionList(
          card: true,
          children: [
            _DetailRow(label: 'Workout', value: session.name),
            _DetailRow(
              label: 'Date',
              value: WorkoutDateLabel.relative(session.startTime),
            ),
            _DetailRow(label: 'Duration', value: durationText),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat notes block under a 13px UPPERCASE header.
class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'Notes',
          padding: EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        Text(notes, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
