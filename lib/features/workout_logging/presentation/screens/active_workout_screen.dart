import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/navigation/workout_minimize_intent.dart';
import '../../../../core/navigation/workout_minimize_sheet_controller.dart';
import '../../../../core/widgets/active_workout_banner.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/next_incomplete_exercise.dart';
import '../../domain/models/exercise_timeline_event.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../../exercise_library/domain/repositories/exercise_repository.dart';
import '../../data/repositories/local_workout_repository.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/services/rest_timer_service.dart';
import '../../domain/services/inactivity_service.dart';
import '../../../health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../../health_sync/domain/usecases/load_latest_readiness.dart';
import '../../../onboarding/onboarding_flags.dart';
import '../../domain/utils/set_utils.dart';
import '../../domain/utils/superset_grouping.dart';
import '../../domain/utils/working_set_count.dart';
import '../widgets/active_workout_header.dart';
import '../widgets/exercise_card.dart';
import '../widgets/set_input_keyboard.dart';
import '../widgets/workout_notes_sheet.dart';
import '../widgets/global_timer_dialog.dart';
import '../widgets/workout_bottom_actions.dart';
import '../widgets/active_workout_app_bar_actions.dart';
import '../widgets/active/live_elapsed_label.dart';
import '../widgets/active/rest_control_pill.dart';
import '../widgets/rest_timer_chip.dart';
import '../widgets/rest_timer_dialog_content.dart';
import '../widgets/active/sticky_finish_bar.dart';
import '../widgets/active/pr_banner.dart';
import '../widgets/active/workout_minimize_drag_handle.dart';
import '../widgets/watch_recording_card.dart';
import '../widgets/active_workout_skeleton.dart';
import '../widgets/persist_failure_banner.dart';
import 'package:collection/collection.dart';
import '../widgets/finish_workout_dialog.dart';
import '../widgets/onboarding_permission_primer.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import '../../../../core/services/haptics.dart';
import '../../data/services/workout_sync_service.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/workout_widget_service.dart';
import '../../domain/services/workout_events_service.dart';
import '../../../../core/services/watch_bridge/watch_bridge_service.dart';
import '../../../../core/webmcp/active_workout_web_mcp_controller.dart';
import '../../../../core/webmcp/web_mcp_access_gate.dart';
import '../widgets/workout_adjustment_review_card.dart';

class NextExerciseSuggestion {
  final String? name;
  final bool isNextSet;

  const NextExerciseSuggestion({required this.name, required this.isNextSet});
}

@visibleForTesting
NextExerciseSuggestion nextExerciseSuggestion(
  List<WorkoutExercise> exercises,
  WorkoutExercise current,
) {
  final index = exercises.indexWhere((e) => e.id == current.id);
  if (index == -1) {
    return const NextExerciseSuggestion(name: null, isNextSet: false);
  }

  final hasRemainingSets = current.sets.any((s) => !s.isCompleted);
  if (hasRemainingSets) {
    return NextExerciseSuggestion(name: current.exercise.name, isNextSet: true);
  }

  // Current exercise is done: surface the next exercise that still has work
  // left, skipping any following exercises that are already fully completed so
  // the notification never names an already-finished exercise.
  final nextIndex = nextIncompleteExerciseIndex(exercises, index);
  if (nextIndex != null) {
    return NextExerciseSuggestion(
      name: exercises[nextIndex].exercise.name,
      isNextSet: false,
    );
  }
  return const NextExerciseSuggestion(name: null, isNextSet: false);
}

class ActiveWorkoutScreen extends StatefulWidget {
  final String? sessionId;
  final String initialName;
  final List<Map<String, dynamic>>?
  initialExercises; // list of { name: String, sets:int?, rest:int? }
  final String? returnLocation;
  @visibleForTesting
  final bool enableOnboardingTipsInTests;

  const ActiveWorkoutScreen({
    super.key,
    this.sessionId,
    this.initialName = 'Workout',
    this.initialExercises,
    this.returnLocation,
    this.enableOnboardingTipsInTests = false,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with WidgetsBindingObserver {
  final _workoutRepository = GetIt.instance<WorkoutRepository>();
  final _restTimerService = GetIt.instance<RestTimerService>();
  final _inactivityService = GetIt.instance<InactivityService>();
  final _preferencesService = GetIt.instance<PreferencesService>();
  final _notificationService = GetIt.instance<NotificationService>();
  final _uuid = const Uuid();
  // Serialize storage writes; UI is the source of truth.
  Future<void> _persistChain = Future<void>.value();
  // A storage write that fails is surfaced via [_persistFailed] (a retryable
  // banner) rather than swallowed — the optimistic UI would otherwise render a
  // lost edit as saved. [_persistFailureCount] only feeds the log line.
  bool _persistFailed = false;
  int _persistFailureCount = 0;
  bool _minimizeDragBlocked = false;
  ActiveWorkoutWebMcpController? _webMcpController;
  WebMcpAccessGate? _webMcpAccessGate;
  int? _webMcpOwnerToken;
  int? _webMcpLoadedSessionGeneration;

  void _scheduleWatchPublish() {
    if (!GetIt.instance.isRegistered<WatchBridgeService>()) return;
    GetIt.instance<WatchBridgeService>().schedulePublish();
  }

  Future<bool> _enqueuePersist(Future<WorkoutSession> Function() action) {
    final completion = Completer<bool>();
    _persistChain = _persistChain
        .then((_) => action())
        .then<void>((_) {
          // Publish only after a real phone edit has persisted. This replaces
          // the old five-second polling heartbeat, keeping the idle period
          // between sets completely quiet while still advancing the Watch
          // promptly after a completed or edited set.
          _scheduleWatchPublish();
          // A later successful write persists a newer full-session snapshot,
          // superseding any earlier failed write — so clear the banner.
          if (_persistFailed && mounted) {
            setState(() => _persistFailed = false);
          }
          if (!completion.isCompleted) completion.complete(true);
        })
        .catchError((Object error, StackTrace stack) {
          // Keep the chain alive (a rethrow would deadlock every later persist);
          // record the failure so the UI can offer a one-tap retry.
          _persistFailureCount++;
          dev.log(
            'Failed to persist workout edit (attempt $_persistFailureCount)',
            error: error,
            stackTrace: stack,
          );
          if (mounted) {
            setState(() => _persistFailed = true);
          }
          if (!completion.isCompleted) completion.complete(false);
        });
    return completion.future;
  }

  /// Re-persist the current UI truth after a failed write. The UI is the source
  /// of truth, so a full-session snapshot supersedes whatever write failed.
  void _retryPersist() {
    final session = _session;
    if (session == null) return;
    _enqueuePersist(() => _workoutRepository.updateWorkoutSession(session));
  }

  WorkoutSession? _session;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isRestTimerVisible = false;
  String? _activeRestTimerExerciseId;
  Timer? _sessionUpdateTimer;
  final ScrollController _scrollController = ScrollController();

  // Drives the shared set-input keyboard: which field is being edited, opened/
  // re-targeted as the lifter taps between reps/weight inputs. When non-null the
  // keyboard mounts at the bottom and the list above reflows.
  final SetInputKeyboardController _setInputKeyboard =
      SetInputKeyboardController();
  // Per-exercise card keys so superset auto-advance can scroll the next group
  // member into view via Scrollable.ensureVisible.
  final Map<String, GlobalKey> _exerciseCardKeys = {};
  final _uuidForGrouping = const Uuid();
  late final ValueNotifier<int> _tick;
  StreamSubscription<TimerStatus>? _restTimerStatusSub;
  StreamSubscription<WorkoutChange>? _workoutEventsSub;
  Timer? _externalRefreshDebounce;
  Future<void> _externalRefreshChain = Future<void>.value();
  TimerStatus? _lastRestTimerStatus;
  bool? _isOnboardingNewUser;
  final _prBanner = PrBannerController();

  // Readiness-aware rest suggestion (R3). Loaded lazily, once, and surfaced at
  // most once per session via [_restSuggestionShown] — an in-memory flag, never
  // persisted. With no/low-confidence recovery data the rest flow is identical
  // to today (the snapshot stays null → the dialog shows no suggestion).
  DailyRecoverySnapshot? _readiness;
  bool _readinessRequested = false;
  bool _restSuggestionShown = false;

  /// Guards the value-timed notification primer so it's attempted at most once
  /// per screen (on the first rest-timer start), not on screen mount.
  bool _notificationPrimerTried = false;

  bool get _watchRecordingSupported {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (!GetIt.instance.isRegistered<WatchBridgeService>()) return false;
    return GetIt.instance<WatchBridgeService>().isEnabled;
  }

  Future<bool> _watchRecordingDefaultEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _preferencesService.getWatchHeartRateRecordingEnabled();
    } catch (_) {
      return true;
    }
  }

  Future<void> _setWatchRecordingRequested(bool requested) async {
    final session = _session;
    if (session == null) return;
    if (session.watchRecordingRequested == requested) {
      _scheduleWatchPublish();
      return;
    }
    final updated = session.copyWith(watchRecordingRequested: requested);
    await _workoutRepository.updateWorkoutSession(updated, markDirty: false);
    if (!mounted) return;
    setState(() => _session = updated);
    _scheduleWatchPublish();
  }

  Future<void> _requestWatchRecordingStart() async {
    final session = _session;
    if (session == null) return;
    await _setWatchRecordingRequested(true);
    final currentSession = _session;
    if (!mounted ||
        currentSession == null ||
        currentSession.id != session.id ||
        currentSession.isCompleted ||
        !currentSession.watchRecordingRequested) {
      return;
    }
    if (!GetIt.instance.isRegistered<WatchBridgeService>()) return;
    await GetIt.instance<WatchBridgeService>().requestStartRecording(
      sessionId: session.id,
    );
  }

  Future<void> _cancelWatchRecordingRequest() =>
      _setWatchRecordingRequested(false);

  /// Publish a terminal `workout_cancelled(sessionId)` to paired watches and
  /// tombstone the session on the phone bridge, so the watch tears down any
  /// adopted/active local record and can't resurrect it (#4 dangling session).
  ///
  /// [reason] tells the watch whether this is an explicit discard (DELETE the
  /// on-watch record) or a normal completion teardown (FINISH it but keep its
  /// pending sync data so the direct-upload fallback can still reconcile it).
  void _publishWatchCancelled(
    WorkoutSession session, {
    WatchCancelReason reason = WatchCancelReason.discarded,
  }) {
    if (!GetIt.instance.isRegistered<WatchBridgeService>()) return;
    GetIt.instance<WatchBridgeService>().cancelWorkout(
      sessionId: session.id,
      hkWorkoutUuid: session.watchWorkoutUuid,
      reason: reason,
    );
  }

  Future<void> _requestWatchRecordingStop() async {
    final session = _session;
    if (session == null) return;
    if (!GetIt.instance.isRegistered<WatchBridgeService>()) return;
    // Prevent immediate auto-restarts if the watch app is reopened.
    await _setWatchRecordingRequested(false);
    await GetIt.instance<WatchBridgeService>().requestStopRecording(
      sessionId: session.id,
    );
  }

  WorkoutSession _appendTimelineEvent(
    WorkoutSession session,
    ExerciseTimelineEvent event, {
    int dedupeWindowMs = 800,
  }) {
    final events = session.timelineEvents;
    if (events.isNotEmpty) {
      final last = events.last;
      final delta = (event.tsMs - last.tsMs).abs();
      if (last.kind == event.kind &&
          last.workoutExerciseId == event.workoutExerciseId &&
          delta <= dedupeWindowMs) {
        return session;
      }
    }
    return session.copyWith(timelineEvents: [...events, event]);
  }

  @override
  void initState() {
    super.initState();
    if (GetIt.instance.isRegistered<ActiveWorkoutWebMcpController>()) {
      _webMcpController = GetIt.instance<ActiveWorkoutWebMcpController>();
      if (GetIt.instance.isRegistered<WebMcpAccessGate>()) {
        _webMcpAccessGate = GetIt.instance<WebMcpAccessGate>();
        _webMcpAccessGate!.ready.addListener(_handleWebMcpAccessChange);
      }
      _attachWebMcpOwnerIfReady();
    }
    WidgetsBinding.instance.addObserver(this);
    // Notification priming is value-timed: it now waits for the first rest
    // timer to start (see _onRestTimerStatusChanged) so a brand-new user logs
    // their first set before any OS prompt rationale appears. In tests/headless
    // we keep the legacy direct request on mount so existing coverage stays
    // deterministic.
    if (_isTestEnv()) {
      _notificationPrimerTried = true;
      // ignore: discarded_futures
      _notificationService.ensurePermissionsForWorkout();
    }
    _isRestTimerVisible =
        _restTimerService.status == TimerStatus.running ||
        _restTimerService.status == TimerStatus.paused;
    _lastRestTimerStatus = _restTimerService.status;
    _restTimerStatusSub = _restTimerService.statusStream.listen(
      _onRestTimerStatusChanged,
    );
    _workoutEventsSub = GetIt.instance.isRegistered<WorkoutEventsService>()
        ? GetIt.instance<WorkoutEventsService>().stream.listen(
            _onWorkoutChanged,
          )
        : null;
    _loadOrCreateSession();
    // ignore: discarded_futures
    _loadReadiness();
    _inactivityService.start();

    // Setup a lightweight ticker to update time labels without rebuilding the list
    _tick = ValueNotifier<int>(0);
    _sessionUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _session != null) {
        _tick.value++;
      }
    });
  }

  void _attachWebMcpOwnerIfReady() {
    final controller = _webMcpController;
    final gate = _webMcpAccessGate;
    if (controller == null ||
        _webMcpOwnerToken != null ||
        _session == null ||
        (gate != null && !gate.ready.value)) {
      return;
    }
    _webMcpOwnerToken = controller.attach(
      readSession: () => _session,
      apply: _applyWebMcpAdjustment,
    );
  }

  void _detachWebMcpOwner() {
    final ownerToken = _webMcpOwnerToken;
    _webMcpOwnerToken = null;
    if (ownerToken != null) _webMcpController?.detach(ownerToken);
  }

  void _handleWebMcpAccessChange() {
    final gate = _webMcpAccessGate;
    if (gate == null || !gate.ready.value) {
      _webMcpLoadedSessionGeneration = null;
      _detachWebMcpOwner();
      return;
    }
    final loadedGeneration = _webMcpLoadedSessionGeneration;
    if (loadedGeneration != gate.generation) {
      _detachWebMcpOwner();
      unawaited(_rebindWebMcpOwnerForCurrentAccount(gate.generation));
      return;
    }
    unawaited(_rebindWebMcpOwnerForCurrentAccount(loadedGeneration!));
  }

  int? _captureWebMcpLoadGeneration() {
    final gate = _webMcpAccessGate;
    return gate?.generation;
  }

  void _requestWebMcpRebindForLoadedSession(int? loadGeneration) {
    final gate = _webMcpAccessGate;
    if (gate == null) {
      _attachWebMcpOwnerIfReady();
      return;
    }
    if (loadGeneration == null || gate.generation != loadGeneration) {
      _webMcpLoadedSessionGeneration = null;
      _detachWebMcpOwner();
      if (gate.ready.value) {
        unawaited(_rebindWebMcpOwnerForCurrentAccount(gate.generation));
      }
      return;
    }
    _webMcpLoadedSessionGeneration = loadGeneration;
    if (gate.isReadyFor(loadGeneration)) {
      unawaited(_rebindWebMcpOwnerForCurrentAccount(loadGeneration));
    } else {
      _detachWebMcpOwner();
    }
  }

  Future<void> _rebindWebMcpOwnerForCurrentAccount(int generation) async {
    final gate = _webMcpAccessGate;
    final visibleSession = _session;
    if (gate == null || visibleSession == null) return;
    WorkoutSession? verified;
    try {
      verified = await _workoutRepository.getWorkoutSession(visibleSession.id);
    } catch (_) {
      return;
    }
    if (!mounted ||
        !gate.isReadyFor(generation) ||
        verified == null ||
        verified.isCompleted ||
        verified.endTime != null ||
        _session?.id != verified.id) {
      return;
    }
    if (_session != verified) {
      setState(() => _session = verified);
    }
    _webMcpLoadedSessionGeneration = generation;
    _attachWebMcpOwnerIfReady();
  }

  Future<void> _showNotesDialog() async {
    if (_session == null) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (ctx) {
        return WorkoutNotesSheet(
          initialText: _session!.notes ?? '',
          onSave: (text) => ctx.pop(text.trim()),
          onClose: () => ctx.pop(null),
        );
      },
    );

    if (!mounted) return;
    if (result != null) {
      _inactivityService.recordActivity();
      final updated = _session!.copyWith(notes: result.isEmpty ? null : result);
      await _workoutRepository.updateWorkoutSession(updated);
      setState(() {
        _session = updated;
      });
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Notes saved',
        variant: HustlSnackVariant.success,
      );
    }
  }

  @override
  void dispose() {
    _webMcpAccessGate?.ready.removeListener(_handleWebMcpAccessChange);
    _detachWebMcpOwner();
    WidgetsBinding.instance.removeObserver(this);
    _restTimerStatusSub?.cancel();
    _workoutEventsSub?.cancel();
    _externalRefreshDebounce?.cancel();
    _sessionUpdateTimer?.cancel();
    _inactivityService.stop();
    _prBanner.dismiss();
    _tick.dispose();
    _scrollController.dispose();
    _setInputKeyboard.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // On background, flush any pending edit before the OS can kill the app:
    // commit the open keyboard draft (close(commit: true) routes the drafted
    // value through the normal persist path), then defensively queue a
    // full-session snapshot of the latest state. Do NOT handle `inactive` — it
    // fires on control-center pulls and permission dialogs, where dismissing the
    // keyboard would be hostile.
    if (state == AppLifecycleState.paused) {
      _setInputKeyboard.close();
      _retryPersist();
    }
    // On resume, immediately resync the rest timer to catch up after backgrounding.
    if (state == AppLifecycleState.resumed) {
      try {
        _restTimerService.refreshNow();
      } catch (e, s) {
        dev.log('Error refreshing rest timer', error: e, stackTrace: s);
      }

      // Only rebuild if timer visibility needs updating
      final shouldShow =
          _restTimerService.status == TimerStatus.running ||
          _restTimerService.status == TimerStatus.paused;
      if (mounted && _isRestTimerVisible != shouldShow) {
        setState(() {
          _isRestTimerVisible = shouldShow;
        });
      }
    }
  }

  void _onRestTimerStatusChanged(TimerStatus status) {
    final previousStatus = _lastRestTimerStatus;
    _lastRestTimerStatus = status;
    final previousRestExerciseId = _activeRestTimerExerciseId;

    // Value-timed permission priming: the first rest timer has started, which
    // is exactly when "get a buzz when your rest timer finishes" becomes
    // relevant — and the user has already logged a set by now.
    if (!_notificationPrimerTried && status == TimerStatus.running) {
      _notificationPrimerTried = true;
      // ignore: discarded_futures
      _maybePrimeNotifications();
    }

    final shouldShow =
        status == TimerStatus.running || status == TimerStatus.paused;
    if (mounted && _isRestTimerVisible != shouldShow) {
      setState(() {
        _isRestTimerVisible = shouldShow;
        _activeRestTimerExerciseId = shouldShow
            ? _restTimerService.currentExerciseId
            : null;
      });
    } else if (shouldShow) {
      // Keep the exercise id in sync for notification resume state.
      _activeRestTimerExerciseId = _restTimerService.currentExerciseId;
    }

    final session = _session;
    if (session != null) {
      // Treat the first observed status as a transition from idle so we still
      // record restStart when resuming mid-rest.
      final prevForTimeline = previousStatus ?? TimerStatus.idle;
      final wasActive =
          prevForTimeline == TimerStatus.running ||
          prevForTimeline == TimerStatus.paused;
      final isActive =
          status == TimerStatus.running || status == TimerStatus.paused;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      WorkoutSession? updated;
      ExerciseTimelineEvent? timelineEvent;
      if (isActive && !wasActive) {
        final exId = _restTimerService.currentExerciseId;
        if (exId != null && exId.isNotEmpty) {
          timelineEvent = ExerciseTimelineEvent(
            tsMs: nowMs,
            kind: ExerciseTimelineEventKind.restStart,
            workoutExerciseId: exId,
          );
          updated = _appendTimelineEvent(session, timelineEvent);
        }
      }
      if (!isActive && wasActive) {
        final exId =
            previousRestExerciseId ?? _restTimerService.currentExerciseId;
        if (exId != null && exId.isNotEmpty) {
          timelineEvent = ExerciseTimelineEvent(
            tsMs: nowMs,
            kind: ExerciseTimelineEventKind.restStop,
            workoutExerciseId: exId,
          );
          updated = _appendTimelineEvent(updated ?? session, timelineEvent);
        }
      }

      if (updated != null && updated != session) {
        final updatedSession = updated;
        if (mounted) {
          setState(() => _session = updatedSession);
        }
        // Persist ONLY the timeline event, merged into the STORED session. A
        // whole-session write of `updatedSession` here loses data: this listener
        // fires precisely because a set completion started the rest timer, and
        // when that completion came from the watch the bridge has just written
        // the set to the repository while `_session` is still the pre-set
        // snapshot (the debounced WorkoutChange refresh hasn't run yet) — so a
        // full write would clobber the watch's set back to incomplete.
        final repo = _workoutRepository;
        final eventExerciseId = timelineEvent?.workoutExerciseId;
        final canAppendGranularly =
            repo is LocalWorkoutRepository &&
            eventExerciseId != null &&
            session.exercises.any((e) => e.id == eventExerciseId);
        if (canAppendGranularly) {
          final event = timelineEvent!;
          _enqueuePersist(() async {
            await repo.updateSetsInExercise(
              session.id,
              eventExerciseId,
              const {},
              appendTimelineEvents: [event],
              markDirty: false,
            );
            return updatedSession;
          });
        } else {
          _enqueuePersist(
            () => _workoutRepository.updateWorkoutSession(
              updatedSession,
              markDirty: false,
            ),
          );
        }
      }
    }

    if (status == TimerStatus.completed && previousStatus != status) {
      // Rest completion notifications already play the bell sound via
      // [NotificationService.showRestComplete]. Avoid layering an additional
      // system alert when the app is in the foreground.
    }
  }

  void _onWorkoutChanged(WorkoutChange change) {
    if (!mounted) return;
    final currentSessionId = _session?.id ?? widget.sessionId;
    final isRelevant =
        change.sessionId == null ||
        currentSessionId == null ||
        change.sessionId == currentSessionId;
    if (!isRelevant) return;
    _externalRefreshDebounce?.cancel();
    _externalRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      // Drain any queued phone-side persist BEFORE reading back, so the refresh
      // always observes the result of writes this screen already enqueued and can
      // never read a stale snapshot that a pending persist is about to supersede.
      _externalRefreshChain = _externalRefreshChain
          .catchError((_) {})
          .then((_) => _persistChain.catchError((_) {}))
          .then((_) => _refreshSessionFromRepository());
    });
  }

  void _leaveWorkoutRoute() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(widget.returnLocation ?? '/');
    }
  }

  Future<void> _refreshSessionFromRepository() async {
    final currentId = _session?.id ?? widget.sessionId;
    WorkoutSession? refreshed;
    if (currentId != null) {
      refreshed = await _workoutRepository.getWorkoutSession(currentId);
    } else {
      refreshed = await _workoutRepository.getLatestActiveSession();
    }

    if (!mounted) return;
    if (refreshed == null) {
      _leaveWorkoutRoute();
      return;
    }

    setState(() {
      _session = refreshed;
      _isLoading = false;
    });

    if (refreshed.isCompleted && refreshed.endTime != null) {
      await _notificationService.cancelWorkoutOngoing();
      if (!mounted) return;
      // Just-finished flow: flag the summary so it can show today's recovery
      // note. History/deep-link entries omit this and stay note-free.
      context.go(
        '/summary/${refreshed.id}',
        extra: const {'justFinished': true},
      );
    }
  }

  Future<void> _loadOrCreateSession() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      if (widget.sessionId != null) {
        // Load existing session
        final webMcpGeneration = _captureWebMcpLoadGeneration();
        final session = await _workoutRepository.getWorkoutSession(
          widget.sessionId!,
        );
        if (session != null) {
          setState(() {
            _session = session;
            _isLoading = false;
          });
          _requestWebMcpRebindForLoadedSession(webMcpGeneration);
          _notificationService.showWorkoutOngoing(
            startTime: session.startTime,
            currentExerciseName: session.exercises.isNotEmpty
                ? session.exercises.first.exercise.name
                : null,
          );
          return;
        }
      }

      // If no sessionId was provided (e.g. widget shortcut) try to resume the latest active session.
      final resumeWebMcpGeneration = _captureWebMcpLoadGeneration();
      final ongoing = await _workoutRepository.getLatestActiveSession();
      if (ongoing != null && !ongoing.isCompleted && ongoing.endTime == null) {
        setState(() {
          _session = ongoing;
          _isLoading = false;
        });
        _requestWebMcpRebindForLoadedSession(resumeWebMcpGeneration);
        _notificationService.showWorkoutOngoing(
          startTime: ongoing.startTime,
          currentExerciseName: ongoing.exercises.isNotEmpty
              ? ongoing.exercises.first.exercise.name
              : null,
        );
        return;
      }

      // Prefill from initialExercises if provided; build once, then create session.
      List<WorkoutExercise> prefilled = const [];
      if (widget.initialExercises != null &&
          widget.initialExercises!.isNotEmpty) {
        Map<String, Exercise>? exerciseLookup;
        if (GetIt.instance.isRegistered<ExerciseRepository>()) {
          try {
            final repo = GetIt.instance<ExerciseRepository>();
            final allExercises = await repo.getAllExercises();
            final map = <String, Exercise>{};
            for (final exercise in allExercises) {
              map.putIfAbsent(exercise.name.toLowerCase(), () => exercise);
              final slug = exercise.slug;
              if (slug != null && slug.isNotEmpty) {
                map.putIfAbsent(slug.toLowerCase(), () => exercise);
              }
            }
            exerciseLookup = map;
          } catch (_) {
            exerciseLookup = null;
          }
        }
        final List<WorkoutExercise> built = [];
        for (final m in widget.initialExercises!) {
          final name = (m['name'] as String?) ?? '';
          if (name.isEmpty) continue;
          final slug = (m['slug'] as String?)?.trim();
          Exercise? lookupExercise;
          final lookup = exerciseLookup;
          if (lookup != null) {
            lookupExercise = lookup[name.toLowerCase()];
            if (lookupExercise == null && slug != null && slug.isNotEmpty) {
              lookupExercise = lookup[slug.toLowerCase()];
            }
          }
          final ex =
              lookupExercise ??
              Exercise(
                name: name,
                muscles: const [],
                slug: (slug != null && slug.isNotEmpty) ? slug : null,
              );
          final setsCount = (m['sets'] as int?) ?? 1;
          final restSeconds = (m['rest'] as int?);

          // Repeat-workout/history starts pass exact logged sets. Template
          // starts pass prescription targets in the same legacy `previousSets`
          // field, so protect the "Previous" column from zero-load template
          // targets masking a real weighted history row.
          final List<dynamic>? providedPrev =
              m['previousSets'] as List<dynamic>?;
          final bool targetsArePlaceholder = m['targetsArePlaceholder'] == true;
          final bool previousSetsAreTemplateTargets =
              m['previousSetsAreTemplateTargets'] == true;
          final List<WorkoutSet>? parsedPrev = providedPrev
              ?.map((s) => WorkoutSet.fromMap(s as Map<String, dynamic>))
              .toList();
          final bool providedHasLoggedValue =
              parsedPrev != null &&
              parsedPrev.isNotEmpty &&
              parsedPrev.any((s) => s.hasLoggedValue);
          final bool zeroLoadTemplateTarget =
              _isZeroLoadTemplateTargetForWeightedExercise(
                exercise: ex,
                sets: parsedPrev,
                previousSetsAreTemplateTargets: previousSetsAreTemplateTargets,
              );
          final bool shouldFetchHistory =
              !providedHasLoggedValue ||
              targetsArePlaceholder ||
              zeroLoadTemplateTarget;
          final List<WorkoutSet>? historySets = shouldFetchHistory
              ? await _workoutRepository.getPreviousExerciseSets(
                  name,
                  exerciseSlug: slug,
                )
              : null;
          final List<WorkoutSet>? previousSets = _selectInitialPreviousSets(
            targetsArePlaceholder: targetsArePlaceholder,
            zeroLoadTemplateTarget: zeroLoadTemplateTarget,
            providedHasLoggedValue: providedHasLoggedValue,
            parsedPrev: parsedPrev,
            historySets: historySets,
          );

          // Build the current editable sets based on requested count (empty by default),
          // preserving any previous set types such as warm-up/failure.
          final List<WorkoutSet> sets = generateEmptySets(
            setsCount,
            _uuid,
            previousSets: previousSets,
          );

          built.add(
            WorkoutExercise(
              id: _uuid.v4(),
              exercise: ex,
              sets: sets,
              previousSessionSets: previousSets,
              restTimerSeconds: restSeconds,
            ),
          );
        }
        prefilled = built;
      }

      // Create new session once with any prefilled exercises to avoid repeated persistence.
      final watchRecordingRequested = await _watchRecordingDefaultEnabled();
      final createWebMcpGeneration = _captureWebMcpLoadGeneration();
      final createdSession = await _workoutRepository.createWorkoutSession(
        WorkoutSession(
          id: _uuid.v4(),
          name: widget.initialName,
          startTime: DateTime.now(),
          exercises: prefilled,
          watchRecordingRequested: watchRecordingRequested,
        ),
      );

      setState(() {
        _session = createdSession;
        _isLoading = false;
      });
      _requestWebMcpRebindForLoadedSession(createWebMcpGeneration);
      ActiveWorkoutBanner.synchronizeSession(createdSession);
      if (GetIt.instance.isRegistered<WorkoutEventsService>()) {
        GetIt.instance<WorkoutEventsService>().emit(
          WorkoutChange(
            kind: WorkoutChangeKind.created,
            sessionId: createdSession.id,
          ),
        );
      }
      _scheduleWatchPublish();

      // Non-blocking onboarding hints for first-time users.
      // ignore: discarded_futures
      _maybeShowOnboardingV2Tips();

      // Show ongoing workout notification (count-up) when not actively resting
      if (_restTimerService.status != TimerStatus.running) {
        _notificationService.showWorkoutOngoing(
          startTime: _session!.startTime,
          currentExerciseName: _session!.exercises.isNotEmpty
              ? _session!.exercises.first.exercise.name
              : null,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        HustlSnack.show(
          context,
          'We couldn\'t load your workout. Try again or check your connection.',
          variant: HustlSnackVariant.warning,
        );
      }
    }
  }

  List<WorkoutSet>? _selectInitialPreviousSets({
    required bool targetsArePlaceholder,
    required bool zeroLoadTemplateTarget,
    required bool providedHasLoggedValue,
    required List<WorkoutSet>? parsedPrev,
    required List<WorkoutSet>? historySets,
  }) {
    final historyHasLoggedValue =
        historySets?.any((set) => set.hasLoggedValue) ?? false;
    if (targetsArePlaceholder) {
      return historyHasLoggedValue ? historySets : null;
    }
    if (zeroLoadTemplateTarget) {
      return historyHasLoggedValue ? historySets : null;
    }
    if (providedHasLoggedValue) {
      return parsedPrev;
    }
    return historySets;
  }

  bool _isZeroLoadTemplateTargetForWeightedExercise({
    required Exercise exercise,
    required List<WorkoutSet>? sets,
    required bool previousSetsAreTemplateTargets,
  }) {
    if (!previousSetsAreTemplateTargets ||
        exercise.loggingMode != ExerciseLoggingMode.weightReps ||
        sets == null ||
        sets.isEmpty) {
      return false;
    }
    final topLevelSets = sets
        .where((set) => set.parentSetId == null)
        .toList(growable: false);
    if (topLevelSets.isEmpty) return false;
    return topLevelSets.any((set) => set.reps > 0) &&
        topLevelSets.every((set) => set.weight == 0);
  }

  bool _isTestEnv() {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTestWidgetsFlutterBinding');
  }

  Future<bool> _isNewUserForOnboarding() async {
    if (_isOnboardingNewUser != null) return _isOnboardingNewUser!;
    try {
      final sessions = await _workoutRepository.getWorkoutSessions(limit: 50);
      final hasCompleted = sessions.any((s) => s.isCompleted);
      _isOnboardingNewUser = !hasCompleted;
      return _isOnboardingNewUser!;
    } catch (_) {
      _isOnboardingNewUser = false;
      return false;
    }
  }

  bool _hasCompletedAnySet(WorkoutSession session) {
    return session.exercises.any((e) => e.sets.any((s) => s.isCompleted));
  }

  Future<void> _maybeShowOnboardingV2Tips() async {
    try {
      if (!mounted ||
          (_isTestEnv() && !widget.enableOnboardingTipsInTests) ||
          _session == null) {
        return;
      }
      if (!await _isNewUserForOnboarding()) return;

      // Delay to ensure first frame is drawn (so toasts attach reliably).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _session == null) return;

        if (_session!.exercises.isEmpty) {
          return;
        }

        if (_hasCompletedAnySet(_session!)) return;

        final seenLogFirstSet = await _preferencesService
            .getOnboardingV2SeenCoachmarkLogFirstSet();
        if (seenLogFirstSet || !mounted) return;
        await _preferencesService.setOnboardingV2SeenCoachmarkLogFirstSet(true);
        if (!mounted) return;
        HustlSnack.show(
          context,
          'Enter your weight and reps, then tap the check to log a set.',
          duration: const Duration(seconds: 6),
        );
      });
    } catch (_) {
      // ignore
    }
  }

  /// One-time discoverability hint for supersets: once the lifter has 2+
  /// ungrouped exercises, gently point them at the Superset chip. Best-effort,
  /// non-blocking, shown at most once ever.
  Future<void> _maybeShowSupersetHint() async {
    try {
      if (!mounted || _isTestEnv() || _session == null) return;
      final exercises = _session!.exercises;
      if (exercises.length < 2) return;
      final anyGrouped = exercises.any(
        (e) => (e.supersetGroupId ?? '').isNotEmpty,
      );
      if (anyGrouped) return;
      if (await _preferencesService.getSeenSupersetHint() || !mounted) return;
      await _preferencesService.setSeenSupersetHint(true);
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Tip: group two exercises into a superset with the Superset chip.',
        duration: const Duration(seconds: 6),
      );
    } catch (_) {
      // Discoverability hint is best-effort.
    }
  }

  /// Shows an in-context rationale before the OS notification prompt, then asks
  /// for permission only if the user opts in. The choice is remembered so we
  /// never re-prompt. Non-blocking and never gates starting the workout.
  Future<void> _maybePrimeNotifications() async {
    if (!mounted || _isTestEnv()) return;
    try {
      final seen = await _preferencesService
          .getOnboardingV2SeenNotificationPrimer();
      if (seen || !mounted) return;

      final choice = await OnboardingPermissionPrimer.show(
        context,
        assetIcon: 'assets/icons/ic_timer.svg',
        title: 'Stay on pace',
        message: 'Get a buzz when your rest timer finishes.',
        allowLabel: 'Allow',
      );
      // Only burn the one-shot "seen" flag once the user has actually answered.
      // A swipe/interruption (dismissed) leaves it unset so we can re-offer
      // later instead of silently consuming the single iOS prompt opportunity.
      if (choice == PermissionPrimerChoice.dismissed) return;
      await _preferencesService.setOnboardingV2SeenNotificationPrimer(true);
      if (choice == PermissionPrimerChoice.allow && mounted) {
        await _notificationService.ensurePermissionsForWorkout();
      }
    } catch (_) {
      // Notification priming is best-effort.
    }
  }

  /// Routes the user to the v3 "Building your plan" first-win summary after their
  /// first-ever completed workout, once. Returns `true` if we navigated there (so
  /// the caller skips its own onward navigation to the standard summary).
  /// Best-effort; never throws.
  Future<bool> _maybeShowFirstWin() async {
    // Kill switch: a flag-off build must never set the seen flag or route to the
    // v3 first-win summary, so it can't strand a user on a retired route.
    if (!kOnboardingV3Enabled) return false;
    if (!mounted || _isTestEnv()) return false;
    try {
      if (_preferencesService.onboardingFirstWinSeen || !mounted) return false;
      // Confirm this is genuinely their first completed session.
      final sessions = await _workoutRepository.getWorkoutSessions(limit: 50);
      final completedCount = sessions.where((s) => s.isCompleted).length;
      final sessionId = _session?.id;
      if (completedCount > 1 || sessionId == null || !mounted) {
        // Already had prior completions (or no session id); mark seen so we
        // don't keep checking.
        await _preferencesService.setOnboardingFirstWinSeen(true);
        return false;
      }
      await _preferencesService.setOnboardingFirstWinSeen(true);
      if (!mounted) return false;
      context.go('/onboarding/first-win/$sessionId');
      return true;
    } catch (_) {
      // First-win celebration is best-effort.
      return false;
    }
  }

  Future<void> _addExercise() async {
    if (_session == null) return;
    _inactivityService.recordActivity();

    // The selection screen pops a single [WorkoutExercise] for a normal add, or
    // a List<WorkoutExercise> (one shared supersetGroupId) for a multi-select
    // "Superset" group.
    final result = await context.push<Object?>('/exercise_select');
    if (result == null) return;

    final added = <WorkoutExercise>[
      if (result is WorkoutExercise) result,
      if (result is List<WorkoutExercise>) ...result,
    ];
    if (added.isEmpty) return;

    if (added.length == 1) {
      final updatedSession = await _workoutRepository.addExerciseToSession(
        _session!.id,
        added.first,
      );
      setState(() => _session = updatedSession);
    } else {
      // Append the group, then normalize so members are contiguous with a
      // consistent supersetOrder, and persist as one update.
      final merged = _normalizeGrouping([..._session!.exercises, ...added]);
      final updated = _session!.copyWith(exercises: merged);
      final persisted = await _workoutRepository.updateWorkoutSession(updated);
      setState(() => _session = persisted);
    }
    _scheduleWatchPublish();

    await Haptics.maybeSelectionClick();

    // Refresh ongoing notification with first exercise if previously empty
    if (_session!.exercises.isNotEmpty) {
      _notificationService.showWorkoutOngoing(
        startTime: _session!.startTime,
        currentExerciseName: _session!.exercises.first.exercise.name,
      );
    }

    // ignore: discarded_futures
    _maybeShowOnboardingV2Tips();
    // ignore: discarded_futures
    _maybeShowSupersetHint();
  }

  Future<void> _updateExercise(WorkoutExercise exercise) async {
    if (_session == null) return;
    _inactivityService.recordActivity();

    final index = _session!.exercises.indexWhere((e) => e.id == exercise.id);
    if (index == -1) return;

    final previousExercise = _session!.exercises[index];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Timeline events appended below are the ONLY session-level state this method
    // mutates besides the exercise itself. Capture the base count so the granular
    // persist can fold in exactly the newly-appended events (append-only).
    final baseTimelineCount = _session!.timelineEvents.length;

    var nextSession = _session!.updateExercise(index, exercise);
    nextSession = _appendTimelineEvent(
      nextSession,
      ExerciseTimelineEvent(
        tsMs: nowMs,
        kind: ExerciseTimelineEventKind.select,
        workoutExerciseId: exercise.id,
      ),
      dedupeWindowMs: 2000,
    );

    final minLen = math.min(previousExercise.sets.length, exercise.sets.length);
    var newlyCompletedPr = false;
    var hasNewlyCompletedSet = false;
    for (var i = 0; i < minLen; i++) {
      final before = previousExercise.sets[i];
      final after = exercise.sets[i];
      if (!before.isCompleted && after.isCompleted) {
        // TODO(telemetry): firstSetLogged — wiring here needs invasive edits to
        // this hot set-completion path (per-session "first set" gating), so it's
        // deferred out of the additive onboarding-telemetry pass.
        hasNewlyCompletedSet = true;
        if (after.isPr && after.reps > 0) {
          newlyCompletedPr = true;
        }
        final completedAtMs =
            after.completedAt?.millisecondsSinceEpoch ?? nowMs;
        nextSession = _appendTimelineEvent(
          nextSession,
          ExerciseTimelineEvent(
            tsMs: completedAtMs,
            kind: ExerciseTimelineEventKind.setComplete,
            workoutExerciseId: exercise.id,
          ),
        );
      }
    }

    // UI-first: update local session immediately
    setState(() {
      _session = nextSession;
    });

    // Superset auto-advance: when a set is completed in a grouped exercise,
    // walk focus to the next group member so the lifter logs A1 → B1 → A2 → B2
    // without scrolling. Gated behind the default-on preference.
    if (hasNewlyCompletedSet) {
      // ignore: discarded_futures
      _maybeAutoAdvanceSuperset(nextSession, exercise.id);
    }

    if (newlyCompletedPr && mounted && !_isTestEnv()) {
      // Non-blocking celebration: spring banner + heavy haptic.
      Haptics.celebrate();
      _prBanner.show(context, message: 'New PR · ${exercise.exercise.name}');
    }

    // Background persist; keep ordering via the chain. Prefer a GRANULAR
    // set-level write so a set the watch completed concurrently (between this
    // screen's last read and this write) is preserved instead of being clobbered
    // by a whole-session overwrite built from a stale in-memory `_session`.
    final newTimelineEvents =
        nextSession.timelineEvents.length > baseTimelineCount
        ? nextSession.timelineEvents.sublist(baseTimelineCount)
        : const <ExerciseTimelineEvent>[];
    _persistExerciseUpdate(
      nextSession,
      previousExercise,
      exercise,
      newTimelineEvents,
    );

    // Update ongoing workout notification with the current exercise name
    _notificationService.showWorkoutOngoing(
      startTime: _session!.startTime,
      currentExerciseName: exercise.exercise.name,
    );
  }

  Future<bool> _applyWebMcpAdjustment(
    StagedWorkoutAdjustment adjustment,
  ) async {
    final session = _session;
    if (session == null ||
        session.isCompleted ||
        session.endTime != null ||
        session.id != adjustment.sessionId ||
        ActiveWorkoutWebMcpController.revisionFor(session) !=
            adjustment.baseRevision) {
      return false;
    }

    var nextSession = session;
    final updatesByExercise = <String, Map<int, WorkoutSet>>{};
    for (final change in adjustment.changes) {
      final exerciseIndex = nextSession.exercises.indexWhere(
        (exercise) => exercise.id == change.exerciseId,
      );
      if (exerciseIndex < 0) return false;
      final exercise = nextSession.exercises[exerciseIndex];
      final setIndex = exercise.sets.indexWhere(
        (set) => set.id == change.setId,
      );
      if (setIndex < 0 ||
          exercise.sets[setIndex].isCompleted ||
          exercise.sets[setIndex] != change.before) {
        return false;
      }
      final updatedExercise = exercise.updateSet(setIndex, change.after);
      nextSession = nextSession.updateExercise(exerciseIndex, updatedExercise);
      updatesByExercise.putIfAbsent(
        change.exerciseId,
        () => <int, WorkoutSet>{},
      )[setIndex] = change.after;
    }

    if (!mounted) return false;
    setState(() => _session = nextSession);
    _inactivityService.recordActivity();

    var persisted = true;
    final repository = _workoutRepository;
    if (repository is LocalWorkoutRepository) {
      for (final entry in updatesByExercise.entries) {
        final success = await _enqueuePersist(() async {
          await repository.updateSetsInExercise(
            nextSession.id,
            entry.key,
            entry.value,
          );
          return nextSession;
        });
        persisted = persisted && success;
      }
    } else {
      for (final exerciseId in updatesByExercise.keys) {
        final exercise = nextSession.exercises.firstWhere(
          (candidate) => candidate.id == exerciseId,
        );
        final success = await _enqueuePersist(
          () => repository.updateExerciseInSession(
            nextSession.id,
            exerciseId,
            exercise,
          ),
        );
        persisted = persisted && success;
      }
    }

    if (mounted && persisted) {
      HustlSnack.show(
        context,
        'Suggested changes applied',
        variant: HustlSnackVariant.success,
      );
    }
    // The human action has been accepted into the screen's UI truth. A storage
    // failure is handled by the existing retry banner and must not leave the
    // now-stale suggestion card mounted on top of the accepted values.
    return true;
  }

  Widget _buildWebMcpReview(WorkoutSession session) {
    final controller = _webMcpController;
    if (controller == null) return const SizedBox.shrink();
    return ValueListenableBuilder<StagedWorkoutAdjustment?>(
      valueListenable: controller.pending,
      builder: (context, rawPending, _) {
        final adjustment = controller.pendingFor(session);
        if (rawPending != null && adjustment == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.invalidateIfStale(session);
          });
        }
        if (adjustment == null) return const SizedBox.shrink();
        return WorkoutAdjustmentReviewCard(
          adjustment: adjustment,
          onDiscard: () {
            controller.discard();
            HustlSnack.show(
              context,
              'Suggested changes discarded',
              variant: HustlSnackVariant.info,
            );
          },
          onApply: () async {
            final applied = await controller.applyPending();
            if (!applied && context.mounted) {
              HustlSnack.show(
                context,
                'These suggestions are out of date. Ask for a fresh review.',
                variant: HustlSnackVariant.error,
              );
            }
          },
        );
      },
    );
  }

  /// Persist a single-exercise edit, preferring a granular set-level write over a
  /// whole-session overwrite whenever the change is purely to set CONTENTS.
  ///
  /// The lost-update hazard: the watch bridge writes set completions granularly
  /// (`updateSetInExercise`) and emits a `WorkoutChange`, but this screen only
  /// reconciles `_session` from the repo after a debounce. Within that window a
  /// phone-side set completion built a whole-session `updateWorkoutSession` from
  /// the STALE `_session`, silently reverting the watch's just-completed set. A
  /// granular `updateSetsInExercise` read-modify-writes the STORED session, so it
  /// only touches the sets the phone actually changed and preserves the watch's.
  ///
  /// Falls back to a whole-session write when the edit is structural (set added or
  /// removed) or changes exercise-level fields the granular primitive can't
  /// express, or when the repository is not the local store (demo/mock) — those
  /// paths are colder and far less collision-prone.
  void _persistExerciseUpdate(
    WorkoutSession nextSession,
    WorkoutExercise previousExercise,
    WorkoutExercise exercise,
    List<ExerciseTimelineEvent> newTimelineEvents,
  ) {
    final repo = _workoutRepository;
    if (repo is LocalWorkoutRepository &&
        _isSetOnlyExerciseChange(previousExercise, exercise)) {
      final changedByIndex = <int, WorkoutSet>{};
      for (var i = 0; i < exercise.sets.length; i++) {
        if (previousExercise.sets[i] != exercise.sets[i]) {
          changedByIndex[i] = exercise.sets[i];
        }
      }
      if (changedByIndex.isEmpty && newTimelineEvents.isEmpty) return;
      _enqueuePersist(() async {
        await repo.updateSetsInExercise(
          nextSession.id,
          exercise.id,
          changedByIndex,
          appendTimelineEvents: newTimelineEvents,
        );
        return nextSession;
      });
      return;
    }
    _enqueuePersist(() => _workoutRepository.updateWorkoutSession(nextSession));
  }

  /// True when [before] and [after] differ ONLY in their set contents (same set
  /// count, every other exercise-level field identical). Compared via `toMap()`
  /// minus `sets` so it stays correct as fields are added. Only such a change can
  /// be expressed by the granular set-level persist without dropping other edits.
  bool _isSetOnlyExerciseChange(WorkoutExercise before, WorkoutExercise after) {
    if (before.sets.length != after.sets.length) return false;
    final beforeMeta = before.toMap()..remove('sets');
    final afterMeta = after.toMap()..remove('sets');
    return const DeepCollectionEquality().equals(beforeMeta, afterMeta);
  }

  /// Scrolls the next superset group member into view after a set is completed
  /// in a grouped exercise. No-op when ungrouped or when the user turned the
  /// preference off. Robust if the next member has fewer sets (it still scrolls
  /// the card into view; the lifter logs whatever round it has next).
  Future<void> _maybeAutoAdvanceSuperset(
    WorkoutSession session,
    String completedExerciseId,
  ) async {
    if (!SupersetGrouping.isGrouped(session.exercises, completedExerciseId)) {
      return;
    }
    bool enabled;
    try {
      enabled = await _preferencesService.getSupersetAutoAdvance();
    } catch (_) {
      enabled = true;
    }
    if (!enabled || !mounted) return;

    final nextId = SupersetGrouping.nextMemberId(
      session.exercises,
      completedExerciseId,
    );
    if (nextId == null || nextId == completedExerciseId) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Prefer scrolling the next member's card directly into view. When it is
      // not yet laid out (lazy ListView, far below the fold), fall back to
      // pinning the just-completed card near the top — which reveals the next
      // member below it. Both paths keep the lifter in the round flow.
      final nextContext = _exerciseCardKeys[nextId]?.currentContext;
      if (nextContext != null) {
        Scrollable.ensureVisible(
          nextContext,
          duration: AppMotion.medium,
          curve: AppMotion.enterCurve,
          alignment: 0.1,
        );
        return;
      }
      final completedContext =
          _exerciseCardKeys[completedExerciseId]?.currentContext;
      if (completedContext != null) {
        Scrollable.ensureVisible(
          completedContext,
          duration: AppMotion.medium,
          curve: AppMotion.enterCurve,
          alignment: 0.0,
        );
      }
    });
  }

  // ------- Superset grouping mutations -------

  /// Reorder [exercises] so members of each superset group are contiguous and
  /// carry a stable 0-based [WorkoutExercise.supersetOrder]. Groups appear in
  /// the order of their first member's current position; ungrouped exercises
  /// keep their relative order. Pure: returns a new list.
  List<WorkoutExercise> _normalizeGrouping(List<WorkoutExercise> exercises) {
    final result = <WorkoutExercise>[];
    final consumed = <String>{};
    for (final exercise in exercises) {
      if (consumed.contains(exercise.id)) continue;
      final groupId = exercise.supersetGroupId;
      if (groupId == null || groupId.isEmpty) {
        result.add(exercise);
        consumed.add(exercise.id);
        continue;
      }
      // Gather every member of this group in first-appearance order, then
      // assign contiguous supersetOrder values.
      final members = exercises
          .where((e) => e.supersetGroupId == groupId)
          .toList();
      if (members.length < 2) {
        // A lone member is not a real group — clear its grouping fields.
        result.add(
          exercise.copyWith(supersetGroupId: null, supersetOrder: null),
        );
        consumed.add(exercise.id);
        continue;
      }
      for (var i = 0; i < members.length; i++) {
        result.add(members[i].copyWith(supersetOrder: i));
        consumed.add(members[i].id);
      }
    }
    return result;
  }

  Future<void> _persistExercises(List<WorkoutExercise> exercises) async {
    if (_session == null) return;
    final normalized = _normalizeGrouping(exercises);
    final updated = _session!.copyWith(exercises: normalized);
    setState(() => _session = updated);
    _enqueuePersist(() => _workoutRepository.updateWorkoutSession(updated));
  }

  /// Link [anchorId] and [otherIds] into a NEW superset group.
  Future<void> _createSuperset(String anchorId, List<String> otherIds) async {
    if (_session == null) return;
    _inactivityService.recordActivity();
    final groupId = _uuidForGrouping.v4();
    final orderedIds = <String>[anchorId, ...otherIds];
    final updated = _session!.exercises.map((e) {
      if (orderedIds.contains(e.id)) {
        return e.copyWith(
          supersetGroupId: groupId,
          supersetOrder: orderedIds.indexOf(e.id),
        );
      }
      return e;
    }).toList();
    await _persistExercises(updated);
    await Haptics.maybeSelectionClick();
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Grouped into a superset',
      variant: HustlSnackVariant.success,
    );
  }

  /// Add [otherIds] to the existing group that contains [anchorId].
  Future<void> _addToSuperset(String anchorId, List<String> otherIds) async {
    if (_session == null) return;
    _inactivityService.recordActivity();
    final anchor = _session!.exercises.firstWhereOrNull(
      (e) => e.id == anchorId,
    );
    final groupId = anchor?.supersetGroupId;
    if (groupId == null || groupId.isEmpty) return;
    final updated = _session!.exercises.map((e) {
      if (otherIds.contains(e.id)) {
        return e.copyWith(supersetGroupId: groupId);
      }
      return e;
    }).toList();
    await _persistExercises(updated);
    await Haptics.maybeSelectionClick();
  }

  /// Remove [exerciseId] from its superset. If only one member would remain,
  /// the whole group dissolves (a superset needs 2+), handled by
  /// [_normalizeGrouping] clearing the lone member.
  Future<void> _removeFromSuperset(String exerciseId) async {
    if (_session == null) return;
    _inactivityService.recordActivity();
    final updated = _session!.exercises.map((e) {
      if (e.id == exerciseId) {
        return e.copyWith(supersetGroupId: null, supersetOrder: null);
      }
      return e;
    }).toList();
    await _persistExercises(updated);
    await Haptics.maybeSelectionClick();
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Removed from superset',
      variant: HustlSnackVariant.success,
    );
  }

  Future<void> _deleteExercise(String exerciseId) async {
    if (_session == null) return;
    _inactivityService.recordActivity();

    // Find the exercise to delete (for the snackbar copy).
    final exerciseToDelete = _session!.exercises.firstWhereOrNull(
      (e) => e.id == exerciseId,
    );
    if (exerciseToDelete == null) return; // Exercise not found

    // Store the exercise name for the snackbar
    final exerciseName = exerciseToDelete.exercise.name;

    // Snapshot the exact pre-delete list so Undo can restore the full prior
    // state. Reinserting only the removed exercise is not enough: deleting one
    // member of a 2-member superset dissolves the group (the survivor's
    // supersetGroupId is cleared by _normalizeGrouping), so re-adding the lone
    // exercise would leave the survivor ungrouped. Restoring the snapshot keeps
    // the superset intact.
    final previousExercises = List<WorkoutExercise>.unmodifiable(
      _session!.exercises,
    );

    // Create a new list without the selected exercise. Re-normalize grouping so
    // a superset that drops to a single surviving member dissolves cleanly.
    final updatedExercises = _normalizeGrouping(
      _session!.exercises.where((e) => e.id != exerciseId).toList(),
    );

    // Create updated session
    final updatedSession = _session!.copyWith(exercises: updatedExercises);

    // Save to repository
    final result = await _workoutRepository.updateWorkoutSession(
      updatedSession,
    );

    setState(() {
      _session = result;
    });
    _scheduleWatchPublish();

    await Haptics.maybeMediumImpact();

    // Show a confirmation snackbar with undo option
    if (mounted) {
      HustlSnack.show(
        context,
        '$exerciseName removed',
        variant: HustlSnackVariant.success,
        duration: const Duration(seconds: 3),
        actionLabel: 'Undo',
        onAction: () async {
          // Restore the exact pre-delete list (re-normalized so any superset the
          // delete dissolved is reconstituted intact), rather than reinserting
          // only the removed exercise.
          if (_session != null) {
            final restoredExercises = _normalizeGrouping(
              List<WorkoutExercise>.from(previousExercises),
            );
            final updatedSession = _session!.copyWith(
              exercises: restoredExercises,
            );

            // Save to repository
            final result = await _workoutRepository.updateWorkoutSession(
              updatedSession,
            );

            // Update UI
            setState(() {
              _session = result;
            });
            _scheduleWatchPublish();
          }
        },
      );
    }
  }

  Future<void> _finishWorkout() async {
    if (_session == null) return;
    final router = GoRouter.maybeOf(context);
    final sessionId = _session!.id;
    final shouldRequestWatchStop =
        _session!.watchRecordingActive &&
        GetIt.instance.isRegistered<WatchBridgeService>();

    _restTimerService.stopTimer();

    try {
      if (shouldRequestWatchStop) {
        await _requestWatchRecordingStop();
      }
      final completedSession = await _workoutRepository.completeWorkoutSession(
        sessionId,
      );
      final endMs =
          (completedSession.endTime ?? DateTime.now()).millisecondsSinceEpoch;
      final withEndEvent = _appendTimelineEvent(
        completedSession,
        ExerciseTimelineEvent(
          tsMs: endMs,
          kind: ExerciseTimelineEventKind.workoutEnd,
        ),
        dedupeWindowMs: 0,
      );
      final persisted = await _workoutRepository.updateWorkoutSession(
        withEndEvent,
        markDirty: true,
      );

      // Always tell a paired/passive watch that the phone-side workout ended.
      // Before polling was removed, the next heartbeat eventually cleared even
      // a phone-started session that the watch had not adopted for recording.
      // The terminal command is idempotent and preserves any pending Watch data.
      _publishWatchCancelled(persisted, reason: WatchCancelReason.completed);

      if (mounted) {
        setState(() {
          _session = persisted;
        });

        // Confirmation haptic for completing the workout (design-system
        // vocabulary §2.4). Fire-and-forget; never block the finish flow.
        Haptics.confirm();

        // Fire-and-forget sync of the newly completed workout
        // Keep UI snappy; errors are handled internally.
        if (GetIt.instance.isRegistered<WorkoutSyncService>()) {
          // ignore: unawaited_futures
          GetIt.instance<WorkoutSyncService>().syncNow();
        }

        // Post-persistence side-effects are best-effort. The workout is already
        // saved above, so a platform-channel failure here must not abort finishing
        // or block navigation to the summary. In particular, on minified Android
        // release builds flutter_local_notifications can throw
        // `PlatformException(error, TypeToken must be ...)` from its Gson cache; we
        // log and continue rather than surfacing "we couldn't finish your workout".
        try {
          if (GetIt.instance.isRegistered<WorkoutWidgetService>()) {
            // Keep widget data in sync once the workout is persisted.
            await GetIt.instance<WorkoutWidgetService>()
                .updateWorkoutsPerWeekWidget();
          }
        } catch (e, s) {
          dev.log(
            'Widget refresh failed after finishing workout; continuing.',
            name: 'ActiveWorkoutScreen',
            error: e,
            stackTrace: s,
          );
        }

        try {
          // Cancel workout-ongoing notification when completed
          await _notificationService.cancelWorkoutOngoing();
        } catch (e, s) {
          dev.log(
            'Cancelling the ongoing-workout notification failed; continuing.',
            name: 'ActiveWorkoutScreen',
            error: e,
            stackTrace: s,
          );
        }

        // Navigate to the summary screen via router to keep nav state coherent
        if (!mounted) return;

        // Celebrate the very first completed workout before routing on. If the
        // user chooses "See your progress", the sheet routes there itself and we
        // skip the summary so we don't yank them away from what they asked for.
        final wentToProgress = await _maybeShowFirstWin();
        if (!mounted || wentToProgress) return;
        // Just-finished flow: flag the summary so it can show today's recovery
        // note. History/deep-link entries omit this and stay note-free.
        router?.go('/summary/$sessionId', extra: const {'justFinished': true});
      }
    } catch (e, s) {
      // Handle any errors
      dev.log(
        'Failed to finish workout',
        name: 'ActiveWorkoutScreen',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        HustlSnack.show(
          context,
          'We couldn\'t finish your workout. Please try again.',
          variant: HustlSnackVariant.error,
        );
      }
    }
  }

  @visibleForTesting
  Future<void> finishWorkoutForTest() => _finishWorkout();

  Future<void> _replaceExercise(String exerciseId) async {
    if (_session == null) return;
    _inactivityService.recordActivity();

    // Find the exercise index to maintain position
    final exerciseIndex = _session!.exercises.indexWhere(
      (e) => e.id == exerciseId,
    );
    if (exerciseIndex == -1) return;

    // Store the original name for display in the snackbar
    final originalName = _session!.exercises[exerciseIndex].exercise.name;

    // Navigate to exercise selection screen
    final replacement = await context.push<WorkoutExercise>('/exercise_select');

    // If user selected a replacement exercise
    if (replacement != null && mounted) {
      // Re-read the latest exercise from current session (blur commits applied)
      final latestIndex = _session!.exercises.indexWhere(
        (e) => e.id == exerciseId,
      );
      if (latestIndex == -1) return;
      final latestExercise = _session!.exercises[latestIndex];

      // Ensure previous session context is available for the replacement.
      List<WorkoutSet>? previousSets = replacement.previousSessionSets;
      if (previousSets == null) {
        try {
          previousSets = await _workoutRepository.getPreviousExerciseSets(
            replacement.exercise.name,
            exerciseSlug: replacement.exercise.slug,
          );
        } catch (_) {
          previousSets = null;
        }
      }

      // Determine the template rows to mirror for warm-up/working set types.
      List<WorkoutSet> templateSets = replacement.sets;
      if (templateSets.isEmpty) {
        final fallbackCount = math.max(
          previousSets?.length ?? 0,
          latestExercise.sets.length,
        );
        final desiredCount = fallbackCount > 0 ? fallbackCount : 1;
        templateSets = generateEmptySets(
          desiredCount,
          _uuid,
          previousSets: previousSets,
        );
      }

      // Preserve any user-entered values while refreshing PR flags and set types.
      final List<WorkoutSet> mergedSets = [];
      for (var i = 0; i < latestExercise.sets.length; i++) {
        final current = latestExercise.sets[i];
        final template = i < templateSets.length ? templateSets[i] : null;
        bool isPr = false;
        if (replacement.exercise.loggingMode ==
                ExerciseLoggingMode.weightReps &&
            current.isCompleted &&
            current.weight > 0 &&
            current.reps > 0) {
          try {
            isPr = await _workoutRepository.checkIfSetIsPR(
              replacement.exercise.name,
              current,
              exerciseSlug: replacement.exercise.slug,
            );
          } catch (_) {
            isPr = false;
          }
        }
        mergedSets.add(
          current.copyWith(
            id: _uuid.v4(),
            setType: template?.setType ?? current.setType,
            isPr: isPr,
          ),
        );
      }

      // Add any additional template rows so previous-session placeholders render.
      if (templateSets.length > mergedSets.length) {
        for (var i = mergedSets.length; i < templateSets.length; i++) {
          final template = templateSets[i];
          mergedSets.add(
            WorkoutSet(
              id: _uuid.v4(),
              weight: template.weight,
              reps: template.reps,
              setType: template.setType,
            ),
          );
        }
      }

      final updatedExercise = replacement.copyWith(
        id: exerciseId, // Keep the same ID
        sets: mergedSets,
        previousSessionSets: previousSets,
        notes: latestExercise.notes,
        restTimerSeconds:
            replacement.restTimerSeconds ?? latestExercise.restTimerSeconds,
      );

      // UI-first: update local session immediately
      setState(() {
        _session = _session!.updateExercise(latestIndex, updatedExercise);
      });

      // Persist replacement in order (background)
      _enqueuePersist(
        () => _workoutRepository.updateExerciseInSession(
          _session!.id,
          exerciseId,
          updatedExercise,
        ),
      );

      // Show confirmation
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Replaced $originalName with ${updatedExercise.exercise.name}',
        variant: HustlSnackVariant.success,
        duration: const Duration(seconds: 2),
      );

      // Update ongoing workout notification with the new exercise name
      _notificationService.showWorkoutOngoing(
        startTime: _session!.startTime,
        currentExerciseName: updatedExercise.exercise.name,
      );
    }
  }

  Future<void> _confirmAndFinishWorkout() async {
    if (_session == null) return;
    final hasAnyCompleted = _session!.exercises.any(
      (e) => e.sets.any((s) => s.isCompleted),
    );

    if (!hasAnyCompleted) {
      final cancel = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Cancel empty workout?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'This workout has no completed sets. Do you want to cancel and discard it?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: Text(
                'Keep',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              child: Text(
                'Cancel Workout',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
      );
      if (cancel == true) {
        // Stop any running rest timer and delete the empty session
        _restTimerService.stopTimer();
        final cancelledSession = _session!;
        // Tell paired watches to tear down any adopted record BEFORE we delete
        // locally, so a queued watch snapshot can't resurrect it (#4).
        _publishWatchCancelled(cancelledSession);
        await _workoutRepository.deleteWorkoutSession(cancelledSession.id);
        // Clear persistent workout notification when canceling
        await _notificationService.cancelWorkoutOngoing();
        if (mounted) {
          _leaveWorkoutRoute();
        }
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return const FinishWorkoutDialog();
      },
    );
    if (confirmed == true) {
      await _finishWorkout();
    }
  }

  /// Lazily reads the latest readiness snapshot once per session for the
  /// readiness-aware rest suggestion. Reuses the shared recovery pipeline via a
  /// tiny use-case; never blocks the workout and silently no-ops on any error or
  /// missing DI, so the rest flow stays exactly as today when data is absent.
  Future<void> _loadReadiness() async {
    if (_readinessRequested) return;
    _readinessRequested = true;
    if (!GetIt.instance.isRegistered<LoadLatestReadinessUseCase>()) return;
    try {
      final readiness = await GetIt.instance<LoadLatestReadinessUseCase>()();
      if (!mounted || readiness == null) return;
      setState(() => _readiness = readiness);
    } catch (_) {
      // The suggestion is a pure annotation; absence leaves rest as today.
    }
  }

  /// The snapshot to offer the rest dialog: only while the once-per-session
  /// suggestion has not yet been shown. After it appears (accepted or
  /// dismissed) this returns null so the dialog never offers it again.
  DailyRecoverySnapshot? get _restSuggestionSnapshot =>
      _restSuggestionShown ? null : _readiness;

  /// Opens the global rest-timer dialog (idle -> start a global rest). Mirrors
  /// the legacy app-bar timer button wiring.
  void _openGlobalRestTimerDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + AppSpacing.x5,
          left: AppSpacing.x3,
          right: AppSpacing.x3,
          bottom: AppSpacing.x3,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        child: GlobalTimerDialog(
          restTimerService: _restTimerService,
          recoverySnapshot: _restSuggestionSnapshot,
          onSuggestionResolved: () => _restSuggestionShown = true,
          onStartTimer: (int seconds) {
            context.pop();
            setState(() {
              _isRestTimerVisible = true;
              // No specific exercise associated with a global timer.
              _activeRestTimerExerciseId = null;
            });
            _restTimerService.startTimer(
              durationInSeconds: seconds,
              exerciseName: null,
            );
          },
          onClose: () => context.pop(),
        ),
      ),
    );
  }

  /// Builds the rest control for the app-bar Soft Holders row: the running
  /// rest-timer chip when a rest is active, otherwise the idle "Rest" pill.
  Widget _buildRestControl() {
    if (!_isRestTimerVisible) {
      return RestControlPill(onTap: _openGlobalRestTimerDialog);
    }
    return RestTimerChip(
      restTimerService: _restTimerService,
      onExpand: () async {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            insetPadding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + AppSpacing.x5,
              left: AppSpacing.x3,
              right: AppSpacing.x3,
              bottom: AppSpacing.x3,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.cardRadius,
            ),
            child: RestTimerDialogContent(
              restTimerService: _restTimerService,
              onClose: () => context.pop(),
            ),
          ),
        );
        // If the timer completed or stopped while expanded, hide the chip.
        if (_restTimerService.status == TimerStatus.completed ||
            _restTimerService.status == TimerStatus.idle) {
          if (mounted) {
            setState(() {
              _isRestTimerVisible = false;
            });
          }
        }
      },
      onTimerComplete: () {
        Haptics.maybeMediumImpact();
        setState(() {
          _isRestTimerVisible = false;
        });
        // Switch to workout-ongoing notification with current exercise.
        final exName = _activeRestTimerExerciseId == null
            ? null
            : _session?.exercises
                  .firstWhereOrNull((e) => e.id == _activeRestTimerExerciseId)
                  ?.exercise
                  .name;
        _notificationService.showWorkoutOngoing(
          startTime: _session!.startTime,
          currentExerciseName: exName,
        );
      },
      totalSeconds:
          _session?.exercises
              .firstWhereOrNull((e) => e.id == _activeRestTimerExerciseId)
              ?.restTimerSeconds ??
          _restTimerService.originalDurationSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    // Optimistic resume: only block on the skeleton for a genuine COLD load
    // (no session yet). When a session is already in hand, keep rendering it
    // while a refresh runs behind it — old data stays visible instead of a
    // full-screen skeleton flashing on every resume.
    if (_session == null) {
      if (_loadFailed) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
          ),
          body: ScreenEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'We couldn\'t load your workout',
            message:
                'Something went wrong starting your session. Check your '
                'connection and try again.',
            actionLabel: 'Try again',
            onAction: _loadOrCreateSession,
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
        ),
        body: const ActiveWorkoutSkeleton(),
      );
    }

    // Safe-area bottom inset for stable list padding
    final bottomInset = mediaQuery.viewPadding.bottom;

    // On wide/desktop screens the viewport is far taller than a short workout
    // needs, so pinning the finish/cancel bar to the very bottom leaves a big
    // void between it and the content. There, render it inline as the LAST
    // scroll item (grouped right under "Add exercise") so the screen reads as
    // one cohesive top-aligned column. Phones keep the sticky bottom bar.
    final isWide = mediaQuery.size.width >= ResponsiveCenter.wideBreakpoint;
    final minimizeSheet = WorkoutMinimizeSheetScope.maybeOf(context);
    final canDragToMinimize =
        !isWide && (minimizeSheet?.canDrag(context) ?? false);

    void prepareMinimizeDestination() {
      final session = _session;
      if (session != null) {
        ActiveWorkoutBanner.synchronizeSession(session);
      }
      ActiveWorkoutBanner.prepareForMinimizeDestination();
    }

    void minimizeWorkout() {
      // Preserve native keyboard-dismiss-on-back semantics: the first tap on
      // the collapse control commits and closes an open set keyboard; a second
      // tap minimizes. Starting a route animation before PopScope allows the
      // pop would otherwise leave the sheet visually offscreen.
      if (_setInputKeyboard.isOpen) {
        _setInputKeyboard.close();
        return;
      }
      prepareMinimizeDestination();
      if (minimizeSheet != null) {
        unawaited(minimizeSheet.minimize(context));
        return;
      }
      // Direct widget-test/deep-link fallback outside workoutMinimizePage.
      WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
      _leaveWorkoutRoute();
    }

    // Bucket the session's exercises into superset groups once per build so each
    // card can render its rail/header/round-labels without recomputing.
    final supersetGroups = SupersetGrouping.groupsFor(_session!.exercises);
    final groupByExerciseId = <String, SupersetGroup>{};
    for (final group in supersetGroups) {
      for (final member in group.members) {
        groupByExerciseId[member.id] = group;
      }
    }

    // (removed unused buttonColor)

    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        // Touch layouts reserve a distinct top strip for the drag handle so
        // it reads as sheet chrome instead of crowding the timer/actions row.
        toolbarHeight: canDragToMinimize ? 80 : 56,
        leading: null,
        flexibleSpace: canDragToMinimize
            ? WorkoutMinimizeDragHandle(
                onDragStart: (_) {
                  _minimizeDragBlocked = _setInputKeyboard.isOpen;
                  if (_minimizeDragBlocked) {
                    _setInputKeyboard.close();
                    return;
                  }
                  prepareMinimizeDestination();
                },
                onDragUpdate: (details) {
                  if (_minimizeDragBlocked) return;
                  minimizeSheet!.dragBy(
                    context,
                    details.delta.dy / mediaQuery.size.height,
                  );
                },
                onDragEnd: (details) {
                  if (_minimizeDragBlocked) {
                    _minimizeDragBlocked = false;
                    return;
                  }
                  unawaited(
                    minimizeSheet!.release(
                      context,
                      details.primaryVelocity ?? 0,
                    ),
                  );
                },
                onDragCancel: () {
                  if (_minimizeDragBlocked) {
                    _minimizeDragBlocked = false;
                    return;
                  }
                  unawaited(minimizeSheet!.cancel(context));
                },
              )
            : null,
        // Always-visible live "recording" status, left-aligned.
        title: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.x2),
          child: LiveElapsedLabel(startTime: _session!.startTime),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          // The hairline becomes a thin progress line while a background
          // refresh runs, so an optimistic resume signals "updating" without
          // ever blocking the already-visible session behind a skeleton.
          child: _isLoading
              ? LinearProgressIndicator(
                  minHeight: 1,
                  backgroundColor: theme.colorScheme.outlineVariant,
                  color: theme.colorScheme.primary,
                )
              : Container(height: 1, color: theme.colorScheme.outlineVariant),
        ),
        actions: [
          ActiveWorkoutAppBarActions(
            restControl: _buildRestControl(),
            hasNotes:
                _session?.notes != null && _session!.notes!.trim().isNotEmpty,
            onMinimize: minimizeWorkout,
            onOpenNotes: _showNotesDialog,
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: _setInputKeyboard,
        builder: (context, kbChild) => PopScope(
          // While the custom keyboard is open, the first system back dismisses
          // it (committing the in-progress draft via close()); a second back
          // leaves the workout. Mirrors native keyboard-dismiss-on-back.
          canPop: !_setInputKeyboard.isOpen && widget.returnLocation == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_setInputKeyboard.isOpen) {
              _setInputKeyboard.close();
              return;
            }
            _leaveWorkoutRoute();
          },
          child: kbChild!,
        ),
        child: SetInputKeyboardScope(
          controller: _setInputKeyboard,
          child: Column(
            children: [
              // Sits directly under the app bar, above the exercise list, so a
              // failed write is visible without obstructing logging.
              if (_persistFailed) PersistFailureBanner(onRetry: _retryPersist),
              _buildWebMcpReview(_session!),
              Expanded(
                child: GestureDetector(
                  key: const Key('activeWorkoutTapRegion'),
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _setInputKeyboard.close();
                  },
                  child: ScrollConfiguration(
                    behavior: const _IOSScrollBehavior(),
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      switchInCurve: AppMotion.enterCurve,
                      switchOutCurve: AppMotion.exitCurve,
                      transitionBuilder: appFadeSlideTransition,
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          'content-${_session!.exercises.isEmpty}-$_watchRecordingSupported',
                        ),
                        child: ListView.builder(
                          key: const Key('activeWorkoutScrollView'),
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          // Use behavior-provided physics; apply stable bottom padding once
                          padding: EdgeInsets.only(
                            bottom: bottomInset + AppSpacing.x2,
                          ),
                          itemCount: (() {
                            final showWatchCard = _watchRecordingSupported;
                            final contentCount = _session!.exercises.isEmpty
                                ? 1
                                : _session!.exercises.length;
                            final watchCardOffset = showWatchCard ? 1 : 0;
                            final footerIndex =
                                1 + watchCardOffset + contentCount;
                            // Wide/desktop carries one extra item: the finish/cancel
                            // bar rendered inline under "Add exercise" (phones pin it
                            // at the bottom instead — see `if (!isWide)` below).
                            return footerIndex + 1 + (isWide ? 1 : 0);
                          })(),
                          itemBuilder: (context, index) {
                            // 0: header
                            if (index == 0) {
                              return ValueListenableBuilder<int>(
                                valueListenable: _tick,
                                builder: (_, __, ___) {
                                  return ActiveWorkoutHeader(
                                    key: ValueKey(
                                      'workout-header-${_session!.id}',
                                    ),
                                    session: _session!,
                                    onNameChanged: (newName) {
                                      if (_session == null) return;
                                      final updated = _session!.copyWith(
                                        name: newName,
                                      );
                                      setState(() {
                                        _session = updated;
                                      });
                                      ActiveWorkoutBanner.synchronizeSession(
                                        updated,
                                      );
                                      _enqueuePersist(
                                        () => _workoutRepository
                                            .updateWorkoutSession(updated),
                                      );
                                    },
                                    pauseTicker: false,
                                  );
                                },
                              );
                            }

                            final showWatchCard = _watchRecordingSupported;
                            final watchCardOffset = showWatchCard ? 1 : 0;
                            final contentCount = _session!.exercises.isEmpty
                                ? 1
                                : _session!.exercises.length;
                            final contentStartIndex = 1 + watchCardOffset;
                            final footerIndex =
                                contentStartIndex + contentCount;

                            if (showWatchCard && index == 1) {
                              return WatchRecordingCard(
                                isRecording: _session!.watchRecordingActive,
                                isRequested:
                                    _session!.watchRecordingRequested &&
                                    !_session!.watchRecordingActive,
                                onRequestStart: () =>
                                    _requestWatchRecordingStart(),
                                onRequestCancel: () =>
                                    _cancelWatchRecordingRequest(),
                                onRequestStop: () =>
                                    _requestWatchRecordingStop(),
                              );
                            }

                            // Last: footer actions
                            if (index == footerIndex) {
                              // Footer without extra SafeArea; list padding includes inset
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.x1,
                                ),
                                child: WorkoutBottomActions(
                                  padding: EdgeInsets.zero,
                                  hasExercises: _session!.exercises.isNotEmpty,
                                  onAddExercise: _addExercise,
                                ),
                              );
                            }

                            // Wide/desktop only: the finish/cancel bar rides inline
                            // right under "Add exercise", so on a tall viewport it
                            // sits with the content instead of stranded at the bottom.
                            if (isWide && index == footerIndex + 1) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.x2,
                                ),
                                child: _buildFinishBar(),
                              );
                            }

                            // Content section
                            if (_session!.exercises.isEmpty) {
                              // Premium hero empty state. Sits as a single ListView
                              // item, so give it a comfortable min-height and
                              // vertical breathing room rather than hugging the top
                              // of a tall void.
                              return ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 360,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.x4,
                                  ),
                                  child: ScreenEmptyState(
                                    icon: Icons.fitness_center_rounded,
                                    assetIcon: 'assets/icons/empty_workout.svg',
                                    title: 'No exercises yet',
                                    message:
                                        'Add your first exercise to start logging '
                                        'sets.',
                                    actionLabel: 'Add exercise',
                                    onAction: _addExercise,
                                  ),
                                ),
                              );
                            }

                            final contentIndex = index - contentStartIndex;
                            final exercise = _session!.exercises[contentIndex];
                            final group = groupByExerciseId[exercise.id];
                            // Candidates the lifter can link this exercise with:
                            // other ungrouped exercises (avoids merging two groups,
                            // which would be a confusing gesture).
                            final linkCandidates = _session!.exercises
                                .where(
                                  (e) =>
                                      e.id != exercise.id &&
                                      groupByExerciseId[e.id] == null,
                                )
                                .toList();
                            final cardKey = _exerciseCardKeys.putIfAbsent(
                              exercise.id,
                              () => GlobalKey(),
                            );
                            return RepaintBoundary(
                              key: ValueKey('exercise-${exercise.id}'),
                              child: KeyedSubtree(
                                key: cardKey,
                                child: ExerciseCard(
                                  exercise: exercise,
                                  supersetGroup: group,
                                  linkCandidates: linkCandidates,
                                  onCreateSuperset: (otherIds) =>
                                      _createSuperset(exercise.id, otherIds),
                                  onAddToSuperset: (otherIds) =>
                                      _addToSuperset(exercise.id, otherIds),
                                  onRemoveFromSuperset: () =>
                                      _removeFromSuperset(exercise.id),
                                  onExerciseUpdated: _updateExercise,
                                  onStartRestTimer: (int? durationSeconds) {
                                    setState(() {
                                      _isRestTimerVisible = true;
                                      _activeRestTimerExerciseId = exercise.id;
                                    });
                                    _inactivityService.recordActivity();
                                    // Resolve the current exercise from the
                                    // freshly-updated session (the set just
                                    // completed) rather than the build-captured
                                    // object, so the next-exercise decision sees
                                    // the latest set-completion state.
                                    final exercises = _session!.exercises;
                                    final current =
                                        exercises.firstWhereOrNull(
                                          (e) => e.id == exercise.id,
                                        ) ??
                                        exercise;
                                    final nextSuggestion =
                                        nextExerciseSuggestion(
                                          exercises,
                                          current,
                                        );
                                    _restTimerService.startTimer(
                                      durationInSeconds: durationSeconds,
                                      exerciseId: exercise.id,
                                      // Show current exercise in UI
                                      exerciseName: exercise.exercise.name,
                                      // Use next exercise only for notification body
                                      notificationNextExerciseName:
                                          nextSuggestion.name,
                                      notificationIsNextSet:
                                          nextSuggestion.isNextSet,
                                      // Fresh decision: an explicit null next
                                      // exercise must clear any stale stored name.
                                      updateNotificationNextExercise: true,
                                    );
                                  },
                                  onExerciseDeleted: _deleteExercise,
                                  onExerciseReplaced: _replaceExercise,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // When a set input is active the custom keyboard mounts here as a
              // Column child, shrinking the list above so the active row scrolls
              // clear of the keys (native-keyboard reflow). Otherwise the phone's
              // sticky finish/cancel bar shows (wide screens render it inline).
              ListenableBuilder(
                listenable: _setInputKeyboard,
                builder: (context, _) {
                  final session = _setInputKeyboard.active;
                  if (session != null) {
                    // The panel reserves its full height immediately so the list
                    // reflow + scroll-into-view math stay correct from frame one;
                    // SetInputKeyboard slides its OWN content up (paint only) for
                    // the native-style reveal, without animating the layout size.
                    return TapRegion(
                      groupId: setInputTapGroupId,
                      // A tap on anything OUTSIDE the keyboard + the set fields
                      // (the ✓ check, an action chip, Add set, the finish bar,
                      // another row…) dismisses the keyboard, committing the
                      // in-progress draft first — like a native keyboard.
                      // Tapping another field stays in the group and re-targets.
                      onTapOutside: (_) => _setInputKeyboard.close(),
                      child: SetInputKeyboard(
                        // Stable key: reuse the keyboard across field switches so
                        // tapping weight↔reps re-targets it in place (handled in
                        // didUpdateWidget) instead of tearing it down — that
                        // teardown + the height pop were the switch "jank".
                        key: const ValueKey('setInputKeyboard'),
                        session: session,
                      ),
                    );
                  }
                  if (!isWide) return _buildFinishBar();
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The finish/cancel action bar (its label flips to "Cancel workout" until a
  /// set is logged). Reused both pinned at the bottom on phones and inline as
  /// the last scroll item on wide screens.
  Widget _buildFinishBar() {
    final session = _session!;
    final exercises = session.exercises;
    var completedSets = 0;
    var totalSets = 0;
    for (final exercise in exercises) {
      // Tally working sets only: a dropset counts as one set (its drops roll
      // into the parent), so the "X of Y sets" progress never over-counts.
      totalSets += exercise.workingSetCount;
      completedSets += exercise.completedWorkingSetCount;
    }
    return StickyFinishBar(
      completedSets: completedSets,
      totalSets: totalSets,
      totalVolume: session.totalVolume,
      exerciseCount: exercises.length,
      // A cardio/duration-only session has no kg volume — hide the "· 0 kg"
      // segment instead of implying nothing was lifted.
      showVolume: exercises.any(
        (ex) => ex.exercise.loggingMode == ExerciseLoggingMode.weightReps,
      ),
      onFinish: _confirmAndFinishWorkout,
      onCancel: _confirmAndFinishWorkout,
    );
  }
}

class _IOSScrollBehavior extends ScrollBehavior {
  const _IOSScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Remove glow/overscroll indicator for a calmer iOS feel
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }
}
