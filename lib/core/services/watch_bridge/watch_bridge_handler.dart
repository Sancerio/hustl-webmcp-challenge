import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../config/api_config.dart';
import '../../../features/exercise_library/domain/models/exercise.dart';
import '../../../features/exercise_library/domain/repositories/exercise_repository.dart';
import '../../../features/health_sync/domain/writeback/workout_record_mapper.dart';
import '../../../features/health_sync/data/writeback/workout_writeback_coordinator.dart';
import '../../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../../features/workout_logging/domain/models/workout_session.dart';
import '../../../features/workout_logging/domain/models/workout_set.dart';
import '../../../features/workout_logging/domain/models/exercise_timeline_event.dart';
import '../../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../../features/workout_logging/domain/services/workout_events_service.dart';
import '../../../features/workout_logging/domain/services/rest_timer_service.dart';
import '../../../features/workout_logging/domain/utils/set_utils.dart';
import '../../../features/workout_logging/data/repositories/local_workout_repository.dart';
import '../../../features/workout_logging/data/services/workout_sync_service.dart';
import '../../../features/workout_logging/data/services/watch_exercise_effort_service.dart';
import '../../../features/workout_templates/domain/models/workout_template.dart';
import '../../../features/workout_templates/domain/repositories/template_repository.dart';
import '../preferences_service.dart';
import '../workout_widget_service.dart';
import '../notification_service.dart';
import '../../navigation/workout_minimize_intent.dart';
import '../../../main.dart' show navigatorKey;
import 'watch_bridge_command.dart';
import 'watch_bridge_health.dart';
import 'watch_bridge_utils.dart';

class WatchBridgeHandler {
  WatchBridgeHandler({
    WorkoutRepository? workoutRepository,
    RestTimerService? restTimerService,
    NotificationService? notificationService,
    WorkoutRecordMapper? workoutRecordMapper,
    WorkoutEventsService? workoutEvents,
    PreferencesService? preferences,
    ExerciseRepository? exerciseRepository,
    void Function({required String sessionId, String? hkWorkoutUuid})?
    onPublishCancelled,
    void Function(Map<String, dynamic> payload)? onSendCatalogResponse,
  }) : _onPublishCancelled = onPublishCancelled,
       _onSendCatalogResponse = onSendCatalogResponse,
       _exerciseRepositoryOverride = exerciseRepository,
       _workoutRepository =
           workoutRepository ?? GetIt.instance<WorkoutRepository>(),
       _restTimerService =
           restTimerService ?? GetIt.instance<RestTimerService>(),
       _notificationService =
           notificationService ?? GetIt.instance<NotificationService>(),
       _workoutRecordMapper =
           workoutRecordMapper ?? const WorkoutRecordMapper(),
       _workoutEvents =
           workoutEvents ??
           (GetIt.instance.isRegistered<WorkoutEventsService>()
               ? GetIt.instance<WorkoutEventsService>()
               : null),
       _preferences =
           preferences ??
           (GetIt.instance.isRegistered<PreferencesService>()
               ? GetIt.instance<PreferencesService>()
               : null);

  final WorkoutRepository _workoutRepository;
  final RestTimerService _restTimerService;
  final NotificationService _notificationService;
  final WorkoutRecordMapper _workoutRecordMapper;
  final WorkoutEventsService? _workoutEvents;
  final PreferencesService? _preferences;
  // Pushes a phone-side `workout_cancelled` to paired watches (the service owns
  // the WatchConnectivity dual-path send). Null in tests / when unwired.
  final void Function({required String sessionId, String? hkWorkoutUuid})?
  _onPublishCancelled;
  // Sends an `exercise_catalog` response payload to paired watches (the service
  // owns the WatchConnectivity send). Null in tests / when unwired.
  final void Function(Map<String, dynamic> payload)? _onSendCatalogResponse;
  // Optional injected exercise library (tests); otherwise resolved from GetIt.
  final ExerciseRepository? _exerciseRepositoryOverride;
  String? _lastAutoNavigatedSessionId;

  String? _selectedSessionId;
  String? _selectedExerciseId;
  String? _watchRecordingSessionId;
  final Map<String, List<String>> _recentCommandIds = {};
  final Map<String, List<String>> _recentHealthIds = {};
  bool _recentCommandIdsLoaded = false;
  bool _recentHealthIdsLoaded = false;
  // COMMAND-ACK ledger: the most recently APPLIED watch set-mutation command ids
  // (log_set / add_set), echoed back in the published state payload as
  // `appliedCommandIds`. The watch uses this as the AUTHORITATIVE confirmation
  // signal for its optimistic overlay: it clears the overlay the moment an echo
  // carries the overlay's own command id — regardless of which exercise the echo
  // happens to select. This replaces the brittle "infer confirmation from the
  // echo's selected exercise" heuristic (which mis-fired on a rest-tick echo
  // anchored to a different exercise, clearing or flickering an unrelated set).
  // Bounded FIFO so the payload (and memory) stays small; ids are plain UUID
  // strings (no Int64 ts), so the watchOS arm64_32 Int64 constraint is moot here.
  final List<String> _appliedCommandIds = <String>[];
  static const int _appliedCommandIdsLimit = 12;
  // COMMAND-REJECT ledger (#481): the ids of watch set-mutation commands the
  // phone DROPPED without applying (target session unknown/terminal). Echoed back
  // in the state payload as `rejectedCommandIds` so the watch can surface a
  // FAILURE (revert the optimistic overlay + failure haptic) instead of the old
  // silent success — the foreign-session drop used to be recorded as APPLIED,
  // which cleared the overlay as if the set had landed while it was actually lost.
  // Same bounded FIFO shape as `_appliedCommandIds`; an id can only be in one
  // ledger at a time (recording into one removes it from the other).
  final List<String> _rejectedCommandIds = <String>[];
  // Newest observed in-progress watch snapshot time (`snapMs`) per session id.
  // This is the staleness WATERMARK for the live handoff: it advances on EVERY
  // accepted snapshot, INCLUDING the no-op heartbeat path that suppresses the UI
  // emission when content is unchanged. Without it, a no-op heartbeat at T2 would
  // not bump the persisted `lastUpdatedAt`, so a delayed OLDER-but-changed snapshot
  // at T1 (T0 < T1 < T2) would still beat the stale guard and overwrite newer watch
  // state. The guard compares against max(persisted lastUpdatedAt, watermark).
  final Map<String, int> _liveWatchSnapWatermark = {};
  // Terminal-state TOMBSTONES: ids (and HK UUIDs) of sessions the phone has
  // cancelled/discarded. The watch protocol only models "active X" or
  // "no session", so a cancel is otherwise indistinguishable from
  // "never started" — without this, a late/queued watch snapshot would
  // resurrect a workout the user explicitly threw away. Re-adoption of any
  // tombstoned id is refused.
  final Set<String> _cancelledSessionIds = <String>{};
  final Set<String> _cancelledHkWorkoutUuids = <String>{};
  static const int _tombstoneLimit = 200;
  final Map<String, Timer> _pendingWatchCaptureTimers = {};
  static const Duration _pendingWatchCaptureTimeout = Duration(minutes: 3);
  static const int _recentIdsLimit = 50;
  static const int _recentIdSessionLimit = 100;
  static const String _recentCommandIdsPrefsKey =
      'watch_bridge_recent_command_ids_v1';
  static const String _recentHealthIdsPrefsKey =
      'watch_bridge_recent_health_ids_v1';
  static const Duration _quickStartsTtl = Duration(seconds: 30);
  DateTime? _quickStartsFetchedAt;
  Map<String, dynamic>? _quickStartsCache;
  // Bounded slice of the exercise library shipped to the watch picker. Capped so
  // the WatchConnectivity payload stays well under the ~64 KB transfer limit.
  static const int _catalogSliceLimit = 160;
  // Hard cap on a search-driven catalog response (the long tail is filtered on
  // the phone; only the top matches are shipped to the wrist).
  static const int _catalogSearchLimit = 40;
  static const Duration _catalogCacheTtl = Duration(minutes: 5);
  DateTime? _catalogFetchedAt;
  List<Map<String, dynamic>>? _catalogSliceCache;
  Future<void> _commandChain = Future<void>.value();

  /// The exercise library, preferring an injected instance (tests) and otherwise
  /// the registered singleton. Null when neither is available so the watch picker
  /// gracefully degrades to recents/templates only.
  ExerciseRepository? get _exerciseRepository {
    if (_exerciseRepositoryOverride != null) return _exerciseRepositoryOverride;
    if (GetIt.instance.isRegistered<ExerciseRepository>()) {
      return GetIt.instance<ExerciseRepository>();
    }
    return null;
  }

  Future<void> handleCommand(
    WatchCommand command, {
    bool propagateErrors = false,
  }) {
    return _enqueue(
      () => _handleCommand(command),
      propagateErrors: propagateErrors,
    );
  }

  Future<void> handleHealthSummary(
    WatchHealthSummary summary, {
    bool propagateErrors = false,
  }) {
    return _enqueue(
      () => _handleHealthSummary(summary),
      propagateErrors: propagateErrors,
    );
  }

  Future<void> handleHealthRecordingState(
    WatchHealthRecordingState state, {
    bool propagateErrors = false,
  }) {
    return _enqueue(
      () => _handleHealthRecordingState(state),
      propagateErrors: propagateErrors,
    );
  }

  Future<void> handleWatchSession(
    WatchSession watchSession, {
    bool propagateErrors = false,
  }) {
    return _enqueue(
      () => _handleWatchSession(watchSession),
      propagateErrors: propagateErrors,
    );
  }

  /// Record a terminal tombstone for a cancelled/discarded session so a late or
  /// queued watch snapshot can never resurrect it. Idempotent; bounded.
  void markSessionCancelled(String sessionId, {String? hkWorkoutUuid}) {
    if (sessionId.isNotEmpty) {
      _cancelledSessionIds.add(sessionId);
      _trimTombstones(_cancelledSessionIds);
    }
    if (hkWorkoutUuid != null && hkWorkoutUuid.isNotEmpty) {
      _cancelledHkWorkoutUuids.add(hkWorkoutUuid);
      _trimTombstones(_cancelledHkWorkoutUuids);
    }
  }

  /// True when [watchSession]'s id or HK UUID has already been cancelled on the
  /// phone — the watch must not re-adopt (or re-create) it.
  bool _isWatchSessionTombstoned(WatchSession watchSession) {
    if (_cancelledSessionIds.contains(watchSession.id)) return true;
    final uuid = watchSession.hkWorkoutUuid;
    return uuid != null &&
        uuid.isNotEmpty &&
        _cancelledHkWorkoutUuids.contains(uuid);
  }

  void _trimTombstones(Set<String> store) {
    if (store.length <= _tombstoneLimit) return;
    // Drop the oldest insertions (Set preserves insertion order in Dart).
    final overflow = store.length - _tombstoneLimit;
    final toRemove = store.take(overflow).toList();
    store.removeAll(toRemove);
  }

  Future<void> _enqueue(
    Future<void> Function() action, {
    bool propagateErrors = false,
  }) {
    final run = _commandChain.catchError((_) {}).then((_) => action());
    _commandChain = run.catchError((Object error, StackTrace stackTrace) {
      dev.log(
        'Watch bridge handler error',
        name: 'WatchBridgeHandler',
        error: error,
        stackTrace: stackTrace,
      );
    });
    return propagateErrors ? run : _commandChain;
  }

  void _schedulePendingWatchCaptureFallback(String sessionId) {
    _pendingWatchCaptureTimers[sessionId]?.cancel();
    _pendingWatchCaptureTimers[sessionId] = Timer(
      _pendingWatchCaptureTimeout,
      () {
        _pendingWatchCaptureTimers.remove(sessionId);
        // ignore: discarded_futures
        _enqueue(() => _handlePendingWatchCaptureTimeout(sessionId));
      },
    );
  }

  void _cancelPendingWatchCaptureFallback(String sessionId) {
    _pendingWatchCaptureTimers.remove(sessionId)?.cancel();
  }

  Future<void> _handlePendingWatchCaptureTimeout(String sessionId) async {
    if (_watchRecordingSessionId == sessionId) {
      _schedulePendingWatchCaptureFallback(sessionId);
      return;
    }

    final session = await _workoutRepository.getWorkoutSession(sessionId);
    if (session == null) return;
    if (!session.watchCapturePending) return;
    final hasUuid =
        session.watchWorkoutUuid != null &&
        session.watchWorkoutUuid!.isNotEmpty;
    if (hasUuid || session.capturedOnWatch) {
      return;
    }

    final updated = session.copyWith(
      watchCapturePending: false,
      watchCapturePendingAt: null,
      lastUpdatedAt: DateTime.now(),
    );
    await _workoutRepository.updateWorkoutSession(updated, markDirty: false);
  }

  Future<Map<String, dynamic>?> buildStatePayload() async {
    WorkoutSession? session = await _latestActiveSession();
    final now = DateTime.now();
    final restStatus = _restTimerService.status;
    final restExerciseId =
        restStatus == TimerStatus.running || restStatus == TimerStatus.paused
        ? _restTimerService.currentExerciseId
        : null;

    if (session == null) {
      _selectedSessionId = null;
      _selectedExerciseId = null;
      final rest = _restPayload(now);
      final quickStarts = await _buildQuickStartsPayload(now);
      return {
        'v': 1,
        'ts': now.millisecondsSinceEpoch,
        'sessionId': null,
        'workoutName': null,
        'elapsedSec': null,
        'sessionStartMs': null,
        'activityType': null,
        'exerciseId': null,
        'exerciseName': null,
        'exerciseLoggingMode': null,
        'nextSetIndex': null,
        'nextSetSummary': null,
        'rest': rest,
        if (quickStarts != null) 'quickStarts': quickStarts,
        'capabilities': {
          'canEnd': false,
          'canNavigate': false,
          'canMarkSet': false,
        },
        'health': {'watchRecording': false, 'shouldRecord': false},
        // COMMAND-ACK: echo recently-applied command ids on the no-session path
        // too. A log_set landing as the workout ends produces a null-session echo;
        // without the ack here the watch's optimistic overlay would only clear via
        // the watch-side safety timer rather than promptly.
        if (_appliedCommandIds.isNotEmpty)
          'appliedCommandIds': List<String>.from(_appliedCommandIds),
        // COMMAND-REJECT (#481): echo dropped set-mutation ids so the watch can
        // revert the matching optimistic overlay and signal failure.
        if (_rejectedCommandIds.isNotEmpty)
          'rejectedCommandIds': List<String>.from(_rejectedCommandIds),
      };
    }

    if (_selectedSessionId != session.id) {
      _selectedSessionId = session.id;
      _selectedExerciseId = null;
    }

    final selection = resolveSelection(
      session,
      restExerciseId: restExerciseId,
      selectedExerciseId: _selectedExerciseId,
    );
    _selectedExerciseId = selection?.selectedExerciseId;
    final rest = _restPayload(now, selection: selection);
    final record = _workoutRecordMapper.fromSession(session);
    final capabilities = {
      'canEnd': true,
      'canNavigate': session.exercises.length > 1,
      'canMarkSet': selection?.nextIncompleteSetIndex != null,
    };
    final nextPrefill = selection == null ? null : nextSetPrefill(selection);
    final upNext = selection == null
        ? const WatchBridgeNextSuggestion(name: null, isNextSet: false)
        : nextRemainingWorkSuggestion(session.exercises, selection.exercise);

    return {
      'v': 1,
      'ts': now.millisecondsSinceEpoch,
      'sessionId': session.id,
      'workoutName': session.name,
      'elapsedSec': now.difference(session.startTime).inSeconds,
      'sessionStartMs': session.startTime.millisecondsSinceEpoch,
      'activityType': record.activityType.name,
      'exerciseId': selection?.exercise.id,
      'exerciseName': selection?.exercise.exercise.name,
      'exerciseLoggingMode': selection?.exercise.exercise.loggingMode.name,
      'exerciseImageUrl': resolveWatchImageUrl(
        selection?.exercise.exercise.imageUrl,
        baseUrl: ApiConfig.baseUrl,
      ),
      'nextSetIndex': selection?.nextIncompleteSetIndex == null
          ? null
          : (selection!.nextIncompleteSetIndex! + 1),
      'nextSetTotal': selection?.exercise.sets.length,
      'nextSetSummary': selection == null ? null : nextSetSummary(selection),
      'nextSetWeight': nextPrefill?.weight,
      'nextSetReps': nextPrefill?.reps,
      'nextSetRpe': selection?.nextIncompleteSetIndex == null
          ? null
          : selection!.exercise.sets[selection.nextIncompleteSetIndex!].rpe,
      'upNextExerciseName': upNext.name,
      'upNextIsCurrentExercise': upNext.isNextSet,
      'rest': rest,
      'capabilities': capabilities,
      'health': {
        'watchRecording': _watchRecordingSessionId == session.id,
        'shouldRecord': session.watchRecordingRequested,
      },
      // COMMAND-ACK: echo the recently-applied watch set-mutation command ids so
      // the watch can clear the matching optimistic overlay authoritatively (by
      // command id, not by inferring confirmation from the selected exercise).
      if (_appliedCommandIds.isNotEmpty)
        'appliedCommandIds': List<String>.from(_appliedCommandIds),
      // COMMAND-REJECT (#481): echo dropped set-mutation ids so the watch can
      // revert the matching optimistic overlay and signal failure.
      if (_rejectedCommandIds.isNotEmpty)
        'rejectedCommandIds': List<String>.from(_rejectedCommandIds),
    };
  }

  Future<Map<String, dynamic>?> _buildQuickStartsPayload(DateTime now) async {
    // The catalog slice has its own (longer) TTL; fetch it up front so it can be
    // attached even when the recents/templates cache is warm.
    final catalogSlice = await _buildCatalogSlicePayload(now);

    final lastFetched = _quickStartsFetchedAt;
    if (lastFetched != null && now.difference(lastFetched) < _quickStartsTtl) {
      final cached = _quickStartsCache;
      if (cached == null) {
        if (catalogSlice == null) return null;
        return {'exerciseCatalog': catalogSlice};
      }
      if (catalogSlice == null) return cached;
      return {...cached, 'exerciseCatalog': catalogSlice};
    }

    try {
      final sessions = await _workoutRepository.getWorkoutSessions(limit: 15);
      final completed = sessions.where((s) => s.isCompleted).toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      final recentWorkouts = [
        for (final s in completed.take(3))
          {
            'id': s.id,
            'name': (s.name.trim().isEmpty ? 'Workout' : s.name.trim()),
            'startMs': s.startTime.millisecondsSinceEpoch,
            'endMs': (s.endTime ?? s.startTime).millisecondsSinceEpoch,
            'exerciseCount': s.exercises.length,
            'exerciseNames': [
              for (final ex in s.exercises.take(3)) ex.exercise.name,
            ],
          },
      ];

      List<Map<String, dynamic>> templates = const [];
      if (GetIt.instance.isRegistered<TemplateRepository>()) {
        final repo = GetIt.instance<TemplateRepository>();
        final all = await repo.getWorkoutTemplates();
        final sorted = List<WorkoutTemplate>.from(all)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        templates = [
          for (final t in sorted.take(3))
            {
              'id': t.id,
              'name': (t.name.trim().isEmpty ? 'Template' : t.name.trim()),
              'updatedMs': t.updatedAt.millisecondsSinceEpoch,
              'exerciseCount': t.exercises.length,
              'exerciseNames': [
                for (final raw in t.exercises.take(3))
                  if (raw is Map)
                    (((raw['exerciseId'] as String?) ??
                            (raw['exerciseName'] as String?) ??
                            '')
                        .trim()),
              ].where((name) => name.isNotEmpty).toList(),
            },
        ];
      }

      if (recentWorkouts.isEmpty && templates.isEmpty) {
        _quickStartsFetchedAt = now;
        _quickStartsCache = null;
        if (catalogSlice == null) return null;
        return {'exerciseCatalog': catalogSlice};
      }

      final payload = {
        'recentWorkouts': recentWorkouts,
        'templates': templates,
      };
      _quickStartsFetchedAt = now;
      _quickStartsCache = payload;
      if (catalogSlice == null) return payload;
      return {...payload, 'exerciseCatalog': catalogSlice};
    } catch (_) {
      _quickStartsFetchedAt = now;
      _quickStartsCache = null;
      if (catalogSlice == null) return null;
      return {'exerciseCatalog': catalogSlice};
    }
  }

  Future<void> _handleCommand(WatchCommand command) async {
    WorkoutSession? session = await _latestActiveSession();
    final activeSessionId = session?.id;
    final sessionKey = command.sessionId ?? activeSessionId ?? 'global';
    if (await _hasDuplicateCommandId(sessionKey, command.id)) {
      dev.log(
        'Dropping duplicate command id=${command.id} type=${command.type} '
        '(active=$activeSessionId)',
        name: 'WatchBridgeHandler',
      );
      // COMMAND-ACK on the dedup early-return: a deduped log_set/add_set was
      // already applied on its first delivery, so its optimistic overlay still
      // needs the ack to clear. Without recording the id here the duplicate
      // delivery would return BEFORE the switch's `_recordAppliedCommandId`, so a
      // re-delivered command (e.g. sendMessage failed → transferUserInfo retry)
      // would never re-echo its id and the overlay would linger until the
      // watch-side safety timer.
      _maybeRecordSetMutationAck(command);
      return;
    }
    if (_sessionContainsWatchCommandId(session, command.id)) {
      dev.log(
        'Dropping already-applied watch set command id=${command.id} '
        'type=${command.type} (active=$activeSessionId); '
        'knownExercises=[${_describeSessionExerciseIds(session)}]',
        name: 'WatchBridgeHandler',
      );
      _maybeRecordSetMutationAck(command);
      await _recordProcessedCommandId(sessionKey, command.id);
      return;
    }

    // `session` is passed as a PARAMETER (not closed over) so the recovery path
    // below can retarget it to a recoverable non-active session without
    // write-capturing the enclosing local — which would disable null-promotion in
    // the switch cases.
    Future<void> processCommand(WorkoutSession? session) async {
      // True once a set-mutation has been RETARGETED onto a recoverable
      // NON-ACTIVE session (#481 recovery). The set still lands on that session,
      // but PHONE-GLOBAL side effects anchored to the FOREGROUND active workout —
      // notably the singleton `_restTimerService` and its rest notification —
      // must be SUPPRESSED. Anchoring the phone's global rest countdown to a
      // background session's exercise would hijack the active workout's rest UI.
      var retargetedToForeignSession = false;
      if (command.sessionId != null &&
          activeSessionId != null &&
          command.sessionId != activeSessionId) {
        // #481: the command targets a session that is NOT the phone's current
        // active one (the active session moved on between publishing state and
        // receiving this command). Only set-mutations carry a durable set the
        // user completed and raise an optimistic overlay on the watch; other
        // command types are safe to drop silently.
        final isSetMutation =
            command.type == WatchCommandType.markSetComplete ||
            command.type == WatchCommandType.logSet ||
            command.type == WatchCommandType.addSet;
        if (isSetMutation) {
          // RECOVERY (part B): if the command's session still resolves to a real,
          // non-terminal session, APPLY the mutation to THAT session instead of
          // dropping it — the completed set lands where it belongs rather than
          // being lost. Only reject when the target is unknown or terminal.
          final recovered = await _resolveRecoverableSession(
            command.sessionId!,
          );
          if (recovered != null) {
            dev.log(
              'Retargeting ${command.type} to recoverable non-active session '
              'id=${command.sessionId} (active=$activeSessionId)',
              name: 'WatchBridgeHandler',
            );
            session = recovered;
            retargetedToForeignSession = true;
            // Fall through to the switch, which now operates against `recovered`.
          } else {
            dev.log(
              'Rejecting ${command.type} for unknown/terminal session '
              'id=${command.sessionId} (active=$activeSessionId)',
              name: 'WatchBridgeHandler',
            );
            // COMMAND-REJECT (part A): the set was NOT applied. Report the id as
            // REJECTED (not applied) so the watch reverts its optimistic overlay
            // and signals failure — the previous code acked it here, which
            // cleared the overlay as a false success while the set was lost.
            _maybeRecordSetMutationReject(command);
            return;
          }
        } else {
          dev.log(
            'Ignoring command for non-active session id=${command.sessionId} '
            '(active=$activeSessionId) type=${command.type}',
            name: 'WatchBridgeHandler',
          );
          return;
        }
      }

      switch (command.type) {
        case WatchCommandType.startWorkout:
          dev.log(
            'Start workout command received (active=${session != null})',
            name: 'WatchBridgeHandler',
          );
          if (session != null) return;
          final watchRecordingRequested = await _watchRecordingDefaultEnabled();
          final created = await _workoutRepository.createWorkoutSession(
            WorkoutSession(
              id: const Uuid().v4(),
              name: 'Workout',
              startTime: DateTime.now(),
              exercises: const [],
              watchRecordingRequested: watchRecordingRequested,
            ),
          );
          dev.log(
            'Created workout session id=${created.id}',
            name: 'WatchBridgeHandler',
          );
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.created,
              sessionId: created.id,
            ),
          );
          _maybeNavigateToActiveWorkout(created);
          _notificationService.showWorkoutOngoing(
            startTime: created.startTime,
            currentExerciseName: null,
          );
          break;

        case WatchCommandType.startWorkoutFromTemplate:
          dev.log(
            'Start from template command received (active=${session != null})',
            name: 'WatchBridgeHandler',
          );
          if (session != null) return;
          final templateId = command.templateId;
          if (templateId == null || templateId.isEmpty) return;
          if (!GetIt.instance.isRegistered<TemplateRepository>()) return;
          final templateRepo = GetIt.instance<TemplateRepository>();
          final template = await templateRepo.getWorkoutTemplate(templateId);
          if (template == null) return;
          final watchRecordingRequested = await _watchRecordingDefaultEnabled();
          final created = await _createWorkoutFromTemplate(
            template,
            watchRecordingRequested: watchRecordingRequested,
          );
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.created,
              sessionId: created.id,
            ),
          );
          _maybeNavigateToActiveWorkout(created);
          _notificationService.showWorkoutOngoing(
            startTime: created.startTime,
            currentExerciseName: created.exercises.isNotEmpty
                ? created.exercises.first.exercise.name
                : null,
          );
          break;

        case WatchCommandType.startWorkoutFromRecent:
          dev.log(
            'Start from recent command received (active=${session != null})',
            name: 'WatchBridgeHandler',
          );
          if (session != null) return;
          final workoutId = command.workoutId;
          if (workoutId == null || workoutId.isEmpty) return;
          final watchRecordingRequested = await _watchRecordingDefaultEnabled();
          final created = await _createWorkoutFromRecent(
            workoutId,
            watchRecordingRequested: watchRecordingRequested,
          );
          if (created == null) return;
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.created,
              sessionId: created.id,
            ),
          );
          _maybeNavigateToActiveWorkout(created);
          _notificationService.showWorkoutOngoing(
            startTime: created.startTime,
            currentExerciseName: created.exercises.isNotEmpty
                ? created.exercises.first.exercise.name
                : null,
          );
          break;

        case WatchCommandType.addExercise:
          if (session == null) return;
          dev.log(
            'Add exercise command received sessionId=${session.id} '
            'name=${command.exerciseName ?? "(blank)"}',
            name: 'WatchBridgeHandler',
          );
          await _addExerciseToSession(session, command);
          break;

        case WatchCommandType.exerciseCatalogRequest:
          await _handleExerciseCatalogRequest(command);
          break;

        case WatchCommandType.endWorkout:
          if (session == null) return;
          dev.log(
            'End workout command received sessionId=${session.id}',
            name: 'WatchBridgeHandler',
          );
          _restTimerService.stopTimer();
          final completed = await _workoutRepository.completeWorkoutSession(
            session.id,
          );
          final endMs =
              (completed.endTime ?? DateTime.now()).millisecondsSinceEpoch;
          final withEndEvent = _appendTimelineEvent(
            completed,
            ExerciseTimelineEvent(
              tsMs: endMs,
              kind: ExerciseTimelineEventKind.workoutEnd,
            ),
            dedupeWindowMs: 0,
          );
          await _workoutRepository.updateWorkoutSession(
            withEndEvent,
            markDirty: true,
          );
          unawaited(_notificationService.cancelWorkoutOngoing());
          if (GetIt.instance.isRegistered<WorkoutSyncService>()) {
            unawaited(GetIt.instance<WorkoutSyncService>().syncNow());
          }
          if (GetIt.instance.isRegistered<WorkoutWidgetService>()) {
            unawaited(
              GetIt.instance<WorkoutWidgetService>()
                  .updateWorkoutsPerWeekWidget(),
            );
          }
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.completed,
              sessionId: session.id,
            ),
          );
          if (_watchRecordingSessionId == session.id) {
            _watchRecordingSessionId = null;
          }
          // Session teardown: drop the per-session command-ack ledger so finished
          // ids don't leak into the next session (a fresh session starts clean).
          _appliedCommandIds.clear();
          break;

        case WatchCommandType.discardWorkout:
          if (session == null) return;
          dev.log(
            'Discard workout command received sessionId=${session.id}',
            name: 'WatchBridgeHandler',
          );
          // Cancel is a first-class TERMINAL state: throw the session away (no
          // complete, no markDirty, no sync upload) and tombstone it so a queued
          // watch snapshot can't resurrect it. Mirrors endWorkout but deletes.
          _restTimerService.stopTimer();
          final discardedUuid = session.watchWorkoutUuid;
          markSessionCancelled(session.id, hkWorkoutUuid: discardedUuid);
          // Cancel any queued HealthKit writeback for this session (don't leave a
          // pending Apple Health write for a workout the user discarded).
          _cancelQueuedWritebackForSession(session.id);
          await _workoutRepository.deleteWorkoutSession(session.id);
          unawaited(_notificationService.cancelWorkoutOngoing());
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.cancelled,
              sessionId: session.id,
            ),
          );
          if (_watchRecordingSessionId == session.id) {
            _watchRecordingSessionId = null;
          }
          // Session teardown: drop the per-session command-ack ledger so discarded
          // ids don't leak into the next session.
          _appliedCommandIds.clear();
          // Tell paired watches to tear down their local/active record for this id.
          _onPublishCancelled?.call(
            sessionId: session.id,
            hkWorkoutUuid: discardedUuid,
          );
          break;

        case WatchCommandType.restStart:
          if (session == null) return;
          final restStatus = _restTimerService.status;
          final restExerciseId =
              restStatus == TimerStatus.running ||
                  restStatus == TimerStatus.paused
              ? _restTimerService.currentExerciseId
              : null;
          final selection = resolveSelection(
            session,
            restExerciseId: restExerciseId,
            selectedExerciseId: _selectedExerciseId,
          );
          if (selection == null) return;
          _selectedExerciseId = selection.selectedExerciseId;
          final duration =
              command.durationSec ?? selection.exercise.restTimerSeconds;
          final next = nextExerciseSuggestion(
            session.exercises,
            selection.exercise,
          );
          _restTimerService.startTimer(
            durationInSeconds: duration,
            exerciseId: selection.exercise.id,
            exerciseName: selection.exercise.exercise.name,
            notificationNextExerciseName: next.name,
            notificationIsNextSet: next.isNextSet,
            // Fresh decision: an explicit null next exercise must clear any
            // stale stored name rather than reuse it.
            updateNotificationNextExercise: true,
          );
          await _recordTimelineEvent(
            session: session,
            kind: ExerciseTimelineEventKind.restStart,
            workoutExerciseId: selection.exercise.id,
          );
          break;

        case WatchCommandType.restStop:
          if (session != null) {
            final exId = _restTimerService.currentExerciseId;
            if (exId != null && exId.isNotEmpty) {
              await _recordTimelineEvent(
                session: session,
                kind: ExerciseTimelineEventKind.restStop,
                workoutExerciseId: exId,
              );
            }
          }
          _restTimerService.stopTimer();
          break;

        case WatchCommandType.markSetComplete:
          if (session == null) return;
          // `mark_set_complete` carries an EXPLICIT target exercise (the one the
          // watch overlay was logging against). Honor it AUTHORITATIVELY —
          // exactly like `log_set`/`add_set`: completing a set on exercise A
          // while a REST timer is running for exercise B must land on A, not on
          // the rest-anchored B. The old code wrote the override into
          // `_selectedExerciseId` but then re-derived the target via
          // `resolveSelection`, where `restExerciseId` OUTRANKS the selection —
          // so the completion could be mis-routed to the resting exercise.
          //
          // Per the V2 stale-id contract, a present-but-UNKNOWN explicit id must
          // NO-OP (never fall through to resolveSelection, which would complete
          // a set on the first incomplete exercise). Echo the command id so the
          // watch overlay clears promptly even on that no-op path — the set is
          // never stamped there, so the applied-id ledger is its only ack.
          _recordAppliedCommandId(command.id);
          final markExerciseIdOverride = command.exerciseId?.trim();
          final markHasExplicitTarget =
              markExerciseIdOverride != null &&
              markExerciseIdOverride.isNotEmpty;
          WorkoutExercise? markTargetExercise;
          if (markHasExplicitTarget) {
            markTargetExercise = _findWatchCommandTargetExercise(
              session,
              markExerciseIdOverride,
              allowWatchCreatedCatalogMatch: true,
            );
            if (markTargetExercise == null) {
              dev.log(
                'Ignoring mark_set_complete for unknown exerciseId='
                '$markExerciseIdOverride (stale snapshot); republishing '
                'current state',
                name: 'WatchBridgeHandler',
              );
              return;
            }
          }

          final WorkoutExercise markExercise;
          if (markTargetExercise != null) {
            markExercise = markTargetExercise;
            _selectedExerciseId = markTargetExercise.id;
          } else {
            // No explicit id: fall back to the normal rest/selection resolution.
            final restStatus = _restTimerService.status;
            final restExerciseId =
                restStatus == TimerStatus.running ||
                    restStatus == TimerStatus.paused
                ? _restTimerService.currentExerciseId
                : null;
            final selection = resolveSelection(
              session,
              restExerciseId: restExerciseId,
              selectedExerciseId: _selectedExerciseId,
            );
            if (selection == null) return;
            _selectedExerciseId = selection.selectedExerciseId;
            markExercise = selection.exercise;
          }

          final index = markExercise.sets.indexWhere((s) => !s.isCompleted);
          if (index == -1) return;
          final currentSet = markExercise.sets[index];
          final updatedSet = currentSet.copyWith(
            isCompleted: true,
            completedAt: DateTime.now(),
            watchCommandId: _watchCommandIdOrNull(command.id),
          );
          final updatedExercise = markExercise.updateSet(index, updatedSet);
          await _workoutRepository.updateSetInExercise(
            session.id,
            markExercise.id,
            index,
            updatedSet,
          );
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.updated,
              sessionId: session.id,
            ),
          );
          // Only anchor the phone's GLOBAL rest timer when the set landed on the
          // FOREGROUND active session. A retargeted background set (#481 recovery)
          // must not hijack the active workout's rest countdown/notification.
          if (!retargetedToForeignSession) {
            final next = nextExerciseSuggestion(
              session.exercises,
              updatedExercise,
            );
            _restTimerService.startTimer(
              durationInSeconds: markExercise.restTimerSeconds,
              exerciseId: markExercise.id,
              exerciseName: markExercise.exercise.name,
              notificationNextExerciseName: next.name,
              notificationIsNextSet: next.isNextSet,
              // Fresh decision: an explicit null next exercise must clear any
              // stale stored name rather than reuse it.
              updateNotificationNextExercise: true,
            );
          }
          break;

        case WatchCommandType.logSet:
          if (session == null) return;
          // `log_set` carries an EXPLICIT target exercise (the exercise the watch
          // overlay was logging against). Honor it AUTHORITATIVELY — exactly like
          // `add_set` (round-4): a set logged on exercise A while a REST timer is
          // running for exercise B must land on A, not on the rest-anchored B. The
          // old code set `_selectedExerciseId` from the override but then re-derived
          // the target via `resolveSelection`, where `restExerciseId` OUTRANKS the
          // selection — so the set could be mis-routed to the resting exercise.
          //
          // Per the V2 stale-id contract ("if the set no longer exists, phone
          // should no-op and republish"), a present-but-UNKNOWN explicit id must
          // NO-OP (never fall through to resolveSelection, which would log against
          // the first incomplete exercise). The trailing `_schedulePublish`
          // republishes current state. Always echo the command id so the watch's
          // overlay clears promptly even on the no-op path.
          _recordAppliedCommandId(command.id);
          final logExerciseIdOverride = command.exerciseId?.trim();
          final logHasExplicitTarget =
              logExerciseIdOverride != null && logExerciseIdOverride.isNotEmpty;
          WorkoutExercise? logTargetExercise;
          if (logHasExplicitTarget) {
            logTargetExercise = _findWatchCommandTargetExercise(
              session,
              logExerciseIdOverride,
              allowWatchCreatedCatalogMatch: true,
            );
            if (logTargetExercise == null) {
              dev.log(
                'Ignoring log_set for unknown exerciseId='
                '$logExerciseIdOverride (stale snapshot); republishing current '
                'state. activeSession=${session.id} '
                'knownExercises=[${_describeSessionExerciseIds(session)}]',
                name: 'WatchBridgeHandler',
              );
              return;
            }
          }

          final WorkoutExercise logExercise;
          if (logTargetExercise != null) {
            logExercise = logTargetExercise;
            _selectedExerciseId = logTargetExercise.id;
          } else {
            // No explicit id: fall back to the normal rest/selection resolution.
            final restStatus = _restTimerService.status;
            final restExerciseId =
                restStatus == TimerStatus.running ||
                    restStatus == TimerStatus.paused
                ? _restTimerService.currentExerciseId
                : null;
            final selection = resolveSelection(
              session,
              restExerciseId: restExerciseId,
              selectedExerciseId: _selectedExerciseId,
            );
            if (selection == null) return;
            _selectedExerciseId = selection.selectedExerciseId;
            logExercise = selection.exercise;
          }

          final countRaw = command.setCount ?? 1;
          final setCount = countRaw < 1 ? 1 : (countRaw > 10 ? 10 : countRaw);

          var updatedExercise = logExercise;
          var completedAny = false;
          final setUpdates = <int, WorkoutSet>{};
          for (var i = 0; i < setCount; i++) {
            final index = updatedExercise.sets.indexWhere(
              (s) => !s.isCompleted,
            );
            if (index == -1) break;
            final currentSet = updatedExercise.sets[index];
            final requestedRpe = command.rpe;
            final validRpe =
                requestedRpe != null && requestedRpe >= 1 && requestedRpe <= 10
                ? requestedRpe
                : null;
            final updatedSet = currentSet.copyWith(
              weight: command.weight ?? currentSet.weight,
              reps: command.reps ?? currentSet.reps,
              rpe: command.clearRpe ? null : validRpe ?? currentSet.rpe,
              isCompleted: true,
              completedAt: DateTime.now(),
              watchCommandId: _watchCommandIdOrNull(command.id),
            );
            updatedExercise = updatedExercise.updateSet(index, updatedSet);
            setUpdates[index] = updatedSet;
            completedAny = true;
          }

          if (!completedAny) return;
          await _applyWatchSetUpdates(session.id, logExercise.id, setUpdates);
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.updated,
              sessionId: session.id,
            ),
          );
          // Only anchor the phone's GLOBAL rest timer when the set landed on the
          // FOREGROUND active session. A retargeted background set (#481 recovery)
          // must not hijack the active workout's rest countdown/notification.
          if (!retargetedToForeignSession) {
            final next = nextExerciseSuggestion(
              session.exercises,
              updatedExercise,
            );
            _restTimerService.startTimer(
              durationInSeconds: logExercise.restTimerSeconds,
              exerciseId: logExercise.id,
              exerciseName: logExercise.exercise.name,
              notificationNextExerciseName: next.name,
              notificationIsNextSet: next.isNextSet,
              // Fresh decision: an explicit null next exercise must clear any
              // stale stored name rather than reuse it.
              updateNotificationNextExercise: true,
            );
          }
          break;

        case WatchCommandType.addSet:
          if (session == null) return;
          // COMMAND-ACK: echo this id back in the next state so the watch clears its
          // Add Set optimistic overlay authoritatively (even on the stale-id no-op
          // path below, which republishes current state).
          _recordAppliedCommandId(command.id);
          // `add_set` carries an EXPLICIT target exercise. Validate it against the active
          // session BEFORE any generic selection fallback: a queued Add Set from an older
          // watch snapshot can reference an exercise that no longer exists here. Per the V2
          // stale-id contract ("if the set no longer exists, phone should no-op and
          // republish"), a present-but-unknown id must NO-OP — falling through to
          // resolveSelection() would silently append the set to the FIRST exercise (wrong
          // exercise). The trailing `_schedulePublish` republishes current state for us.
          final exerciseIdOverride = command.exerciseId?.trim();
          final hasExplicitTarget =
              exerciseIdOverride != null && exerciseIdOverride.isNotEmpty;
          WorkoutExercise? targetExercise;
          if (hasExplicitTarget) {
            targetExercise = _findWatchCommandTargetExercise(
              session,
              exerciseIdOverride,
              allowWatchCreatedCatalogMatch: true,
            );
            if (targetExercise == null) {
              dev.log(
                'Ignoring add_set for unknown exerciseId=$exerciseIdOverride '
                '(stale snapshot); republishing current state. '
                'activeSession=${session.id} '
                'knownExercises=[${_describeSessionExerciseIds(session)}]',
                name: 'WatchBridgeHandler',
              );
              return;
            }
          }
          // With a valid explicit target, append to THAT exercise directly (the explicit id
          // is authoritative — don't let an active rest timer's exercise win). Only when no
          // explicit id was supplied do we use the normal rest/selection fallback.
          final WorkoutExercise exercise;
          if (targetExercise != null) {
            exercise = targetExercise;
            _selectedExerciseId = targetExercise.id;
          } else {
            final restStatus = _restTimerService.status;
            final restExerciseId =
                restStatus == TimerStatus.running ||
                    restStatus == TimerStatus.paused
                ? _restTimerService.currentExerciseId
                : null;
            final selection = resolveSelection(
              session,
              restExerciseId: restExerciseId,
              selectedExerciseId: _selectedExerciseId,
            );
            if (selection == null) return;
            _selectedExerciseId = selection.selectedExerciseId;
            exercise = selection.exercise;
          }
          // Seed the appended set from the exercise's last set (else its previous-session
          // set) so it prefills sensibly, matching the in-app "add set" behavior. It is
          // left INCOMPLETE so the watch can log it next.
          final WorkoutSet? seed = exercise.sets.isNotEmpty
              ? exercise.sets.last
              : (exercise.previousSessionSets != null &&
                    exercise.previousSessionSets!.isNotEmpty)
              ? exercise.previousSessionSets!.last
              : null;
          final newSet = WorkoutSet(
            id: const Uuid().v4(),
            weight: command.weight ?? seed?.weight ?? 0,
            reps: command.reps ?? seed?.reps ?? 0,
            // Always append a plain working set (never a drop / warmup clone).
            setType: SetType.regular,
            watchCommandId: _watchCommandIdOrNull(command.id),
          );
          await _workoutRepository.addSetToExercise(
            session.id,
            exercise.id,
            newSet,
          );
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.updated,
              sessionId: session.id,
            ),
          );
          break;

        case WatchCommandType.navNextExercise:
        case WatchCommandType.navPrevExercise:
          if (session == null) return;
          final currentId =
              _selectedExerciseId ?? firstIncompleteExerciseId(session);
          if (currentId == null) return;
          final delta = command.type == WatchCommandType.navNextExercise
              ? 1
              : -1;
          final nextId = navigateExerciseId(
            exercises: session.exercises,
            currentExerciseId: currentId,
            delta: delta,
          );
          if (nextId == currentId) return;
          _selectedExerciseId = nextId;
          await _recordTimelineEvent(
            session: session,
            kind: ExerciseTimelineEventKind.watchNav,
            workoutExerciseId: nextId,
          );
          break;
      }
    }

    await processCommand(session);
    await _recordProcessedCommandId(sessionKey, command.id);
  }

  Future<WorkoutSession> _createWorkoutFromTemplate(
    WorkoutTemplate template, {
    required bool watchRecordingRequested,
  }) async {
    const uuid = Uuid();
    final built = <WorkoutExercise>[];

    for (final raw in template.exercises) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);

      final name =
          (map['exerciseName'] as String?) ??
          (map['exerciseId'] as String?) ??
          '';
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) continue;

      final slug =
          (map['exerciseSlug'] as String?) ??
          (map['slug'] as String?) ??
          (map['canonicalKey'] as String?);
      final setsCount = (map['sets'] as num?)?.toInt() ?? 1;
      final restSeconds = (map['restTimerSeconds'] as num?)?.toInt();

      List<WorkoutSet>? previousSets;
      try {
        previousSets = await _workoutRepository.getPreviousExerciseSets(
          trimmedName,
          exerciseSlug: slug,
        );
      } catch (_) {
        previousSets = null;
      }

      final sets = generateEmptySets(
        setsCount,
        uuid,
        previousSets: previousSets,
      );
      built.add(
        WorkoutExercise(
          id: uuid.v4(),
          exercise: Exercise(name: trimmedName, muscles: const [], slug: slug),
          sets: sets,
          previousSessionSets: previousSets,
          restTimerSeconds: restSeconds,
        ),
      );
    }

    dev.log(
      'Template ${template.id}: parsed ${built.length} of '
      '${template.exercises.length} exercises',
      name: 'WatchBridgeHandler',
    );

    final session = WorkoutSession(
      id: uuid.v4(),
      name: template.name.trim().isEmpty ? 'Workout' : template.name.trim(),
      startTime: DateTime.now(),
      exercises: built,
      watchRecordingRequested: watchRecordingRequested,
    );
    return _workoutRepository.createWorkoutSession(session);
  }

  Future<void> _applyWatchSetUpdates(
    String sessionId,
    String exerciseId,
    Map<int, WorkoutSet> updatesByIndex,
  ) async {
    if (updatesByIndex.isEmpty) return;

    final repo = _workoutRepository;
    if (repo is LocalWorkoutRepository) {
      await repo.updateSetsInExercise(sessionId, exerciseId, updatesByIndex);
      return;
    }

    final updates = updatesByIndex.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final update in updates) {
      await repo.updateSetInExercise(
        sessionId,
        exerciseId,
        update.key,
        update.value,
      );
    }
  }

  WorkoutExercise? _findWatchCommandTargetExercise(
    WorkoutSession session,
    String? rawExerciseId, {
    required bool allowWatchCreatedCatalogMatch,
  }) {
    final id = rawExerciseId?.trim();
    if (id == null || id.isEmpty) return null;

    for (final ex in session.exercises) {
      if (ex.id == id) return ex;
    }

    if (!allowWatchCreatedCatalogMatch) return null;

    final candidates = <WorkoutExercise>[];
    for (final ex in session.exercises) {
      final catalogId = ex.exercise.id?.trim();
      if (ex.createdFromWatch &&
          catalogId != null &&
          catalogId.isNotEmpty &&
          catalogId == id) {
        candidates.add(ex);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Append an exercise to the active session from the watch.
  ///
  /// When [command] carries a NAMED exercise (the on-watch picker / voice flow
  /// chose a real library exercise), that exercise is added with its real name +
  /// slug — so the watch shows e.g. "Pull Up", never "Exercise N". When no name
  /// is supplied (the legacy empty-state "Add exercise" tap), a blank placeholder
  /// is appended and the user can rename it on the phone.
  Future<void> _addExerciseToSession(
    WorkoutSession session,
    WatchCommand command,
  ) async {
    const uuid = Uuid();

    final resolved = await _resolveExerciseForAdd(command);
    final Exercise exercise;
    final List<WorkoutSet> previousSets;
    if (resolved != null) {
      exercise = resolved;
      // Prefill from history so the named exercise starts with the user's last
      // working set (matches the template/recent flows).
      List<WorkoutSet>? prev;
      try {
        prev = await _workoutRepository.getPreviousExerciseSets(
          exercise.name,
          exerciseSlug: exercise.slug,
        );
      } catch (_) {
        prev = null;
      }
      previousSets = prev ?? const [];
    } else {
      exercise = Exercise(
        name: 'Exercise ${session.exercises.length + 1}',
        muscles: const [],
      );
      previousSets = const [];
    }

    final updated = session.copyWith(
      exercises: [
        ...session.exercises,
        WorkoutExercise(
          id: uuid.v4(),
          exercise: exercise,
          sets: generateEmptySets(
            1,
            uuid,
            previousSets: previousSets.isEmpty ? null : previousSets,
          ),
          previousSessionSets: previousSets.isEmpty ? null : previousSets,
          // The wrist initiated this row. A following live watch-session
          // snapshot echoes the catalog exercise id rather than this freshly
          // minted phone row id, so mark it watch-created to let
          // `_mergeWatchExercises` reconcile instead of appending a duplicate.
          createdFromWatch: true,
        ),
      ],
      lastUpdatedAt: DateTime.now(),
    );
    final stored = await _workoutRepository.updateWorkoutSession(
      updated,
      markDirty: true,
    );
    // Focus the watch/phone on the freshly added exercise so the next published
    // state targets it (so logging lands on the right exercise immediately).
    if (stored.exercises.isNotEmpty) {
      _selectedExerciseId = stored.exercises.last.id;
    }
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.updated, sessionId: session.id),
    );
  }

  /// Resolve the real library [Exercise] a NAMED add command refers to. Prefers
  /// an explicit library id, then a slug/name match against the library, and
  /// finally falls back to a name-only exercise so a custom/unknown name from the
  /// watch still adds cleanly. Returns null when the command carries no name/id
  /// (the blank empty-state add).
  Future<Exercise?> _resolveExerciseForAdd(WatchCommand command) async {
    final name = command.exerciseName?.trim();
    final slug = command.exerciseSlug?.trim();
    final id = command.exerciseId?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasId = id != null && id.isNotEmpty;
    if (!hasName && !hasId) return null;

    final repo = _exerciseRepository;
    if (repo != null) {
      try {
        final all = await repo.getAllExercises();
        // 1) exact library id match (most precise).
        if (hasId) {
          for (final ex in all) {
            if (ex.id != null && ex.id == id) return ex;
          }
        }
        // 2) canonical key match (slug-aware, case-insensitive).
        final targetKey = Exercise.canonicalKeyFrom(
          name: hasName ? name : null,
          slug: (slug != null && slug.isNotEmpty) ? slug : null,
        );
        if (targetKey != null) {
          for (final ex in all) {
            if (ex.canonicalKey == targetKey) return ex;
          }
        }
        // 3) case-insensitive exact-name match.
        if (hasName) {
          final lower = name.toLowerCase();
          for (final ex in all) {
            if (ex.name.trim().toLowerCase() == lower) return ex;
          }
        }
      } catch (_) {
        // Library unavailable; fall through to a name-only exercise below.
      }
    }

    // Fall back to a name-only exercise (custom name, or library unavailable) so
    // the watch's chosen name is honored rather than dropped.
    if (hasName) {
      return Exercise(
        name: name,
        slug: (slug != null && slug.isNotEmpty) ? slug : null,
        muscles: const [],
      );
    }
    return null;
  }

  /// Handle a watch `exercise_catalog_request`: build a bounded slice of the
  /// library (optionally filtered by the request's search query) and ship it back
  /// to the wrist as an `exercise_catalog` response. No-op when no send callback
  /// is wired (tests) or no library is available.
  Future<void> _handleExerciseCatalogRequest(WatchCommand command) async {
    final send = _onSendCatalogResponse;
    if (send == null) return;
    final query = command.searchQuery?.trim();
    final hasQuery = query != null && query.isNotEmpty;
    final exercises = await _buildExerciseCatalog(
      query: hasQuery ? query : null,
    );
    send({
      'v': 1,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'id': const Uuid().v4(),
      'type': 'exercise_catalog',
      if (hasQuery) 'searchQuery': query,
      'exercises': exercises,
    });
  }

  /// Build the wire-shape exercise slice the watch picker renders:
  /// `[{id, name, slug, exerciseLoggingMode, muscles}]`. Bounded by
  /// [_catalogSliceLimit] (no query) or [_catalogSearchLimit] (search). Names are
  /// de-duplicated case-insensitively.
  Future<List<Map<String, dynamic>>> _buildExerciseCatalog({
    String? query,
  }) async {
    final repo = _exerciseRepository;
    if (repo == null) return const [];
    try {
      final source = (query != null && query.isNotEmpty)
          ? await repo.searchExercises(query)
          : await repo.getAllExercises();
      final limit = (query != null && query.isNotEmpty)
          ? _catalogSearchLimit
          : _catalogSliceLimit;
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final ex in source) {
        final name = ex.name.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        if (!seen.add(key)) continue;
        out.add({
          if (ex.id != null && ex.id!.isNotEmpty) 'id': ex.id,
          'name': name,
          'exerciseLoggingMode': ex.loggingMode.name,
          if (ex.slug != null && ex.slug!.isNotEmpty) 'slug': ex.slug,
          if (ex.muscles.isNotEmpty) 'muscles': ex.muscles.take(3).toList(),
        });
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Cached catalog slice for embedding in the state payload (fast-path picker
  /// data the watch has immediately, before any search request). Bounded + TTL'd.
  Future<List<Map<String, dynamic>>?> _buildCatalogSlicePayload(
    DateTime now,
  ) async {
    final fetched = _catalogFetchedAt;
    if (fetched != null && now.difference(fetched) < _catalogCacheTtl) {
      return _catalogSliceCache;
    }
    final slice = await _buildExerciseCatalog();
    _catalogFetchedAt = now;
    _catalogSliceCache = slice.isEmpty ? null : slice;
    return _catalogSliceCache;
  }

  Future<WorkoutSession?> _createWorkoutFromRecent(
    String workoutId, {
    required bool watchRecordingRequested,
  }) async {
    final previous = await _workoutRepository.getWorkoutSession(workoutId);
    if (previous == null || !previous.isCompleted) return null;

    const uuid = Uuid();
    final built = <WorkoutExercise>[];
    for (final ex in previous.exercises) {
      final previousSets = ex.sets;
      final sets = generateEmptySets(
        previousSets.length,
        uuid,
        previousSets: previousSets,
      );
      built.add(
        WorkoutExercise(
          id: uuid.v4(),
          exercise: ex.exercise,
          sets: sets,
          previousSessionSets: previousSets,
          restTimerSeconds: ex.restTimerSeconds,
          notes: ex.notes,
        ),
      );
    }

    final name = previous.name.trim().isEmpty
        ? 'Workout'
        : '${previous.name.trim()} (Repeat)';
    final session = WorkoutSession(
      id: uuid.v4(),
      name: name,
      startTime: DateTime.now(),
      exercises: built,
      watchRecordingRequested: watchRecordingRequested,
    );
    return _workoutRepository.createWorkoutSession(session);
  }

  Future<bool> _watchRecordingDefaultEnabled() async {
    final prefs = _preferences;
    if (prefs == null) return true;
    try {
      return await prefs.getWatchHeartRateRecordingEnabled();
    } catch (_) {
      return true;
    }
  }

  void _maybeNavigateToActiveWorkout(WorkoutSession session) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    if (_lastAutoNavigatedSessionId == session.id) return;

    try {
      final router = GoRouter.of(context);
      final path = router.routeInformationProvider.value.uri.path;
      if (path == '/workout_session' || path == '/workout') {
        _lastAutoNavigatedSessionId = session.id;
        return;
      }

      // Only mark as navigated if route ownership transfers. This can throw synchronously
      // when the router isn't ready (e.g. app is backgrounded).
      router.go(
        '/workout_session',
        extra: workoutRouteExtra(context, {
          'sessionId': session.id,
          'initialName': session.name,
        }),
      );
      _lastAutoNavigatedSessionId = session.id;
    } catch (_) {
      // Best-effort: if the router isn't ready (e.g. app is backgrounded),
      // keep the workout visible via the banner/notification.
    }
  }

  Future<void> _handleHealthSummary(WatchHealthSummary summary) async {
    final sessionId = summary.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    if (await _hasDuplicateHealthId(sessionId, summary.id)) {
      return;
    }

    final session = await _workoutRepository.getWorkoutSession(sessionId);
    if (session == null) return;

    _cancelPendingWatchCaptureFallback(sessionId);

    final incomingUuid = summary.hkWorkoutUuid;
    final effectiveUuid = incomingUuid != null && incomingUuid.isNotEmpty
        ? incomingUuid
        : session.watchWorkoutUuid;
    final watchUuid = effectiveUuid ?? '';
    final hasWatchUuid = watchUuid.isNotEmpty;
    final hasWatchMetricsSignal =
        summary.durationSeconds != null ||
        summary.averageHeartRateBpm != null ||
        summary.maxHeartRateBpm != null ||
        summary.activeEnergyKilocalories != null ||
        summary.recordingStartMs != null ||
        summary.recordingEndMs != null;
    final inferredWatchCapture = hasWatchUuid || hasWatchMetricsSignal;
    final updated = session.copyWith(
      watchRecordingRequested: false,
      watchRecordingActive: false,
      capturedOnWatch: inferredWatchCapture ? true : session.capturedOnWatch,
      watchCapturePending: false,
      watchCapturePendingAt: null,
      activeEnergyKilocalories:
          summary.activeEnergyKilocalories ?? session.activeEnergyKilocalories,
      averageHeartRateBpm:
          summary.averageHeartRateBpm ?? session.averageHeartRateBpm,
      maxHeartRateBpm: summary.maxHeartRateBpm ?? session.maxHeartRateBpm,
      watchDurationSeconds:
          summary.durationSeconds ?? session.watchDurationSeconds,
      watchWorkoutUuid: effectiveUuid ?? session.watchWorkoutUuid,
      watchRecordingStartMs:
          summary.recordingStartMs ?? session.watchRecordingStartMs,
      watchRecordingEndMs:
          summary.recordingEndMs ?? session.watchRecordingEndMs,
      lastUpdatedAt: DateTime.now(),
    );
    final markDirty = _shouldMarkDirtyForWatchSync(session, updated);
    final stored = await _workoutRepository.updateWorkoutSession(
      updated,
      markDirty: markDirty,
    );
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.updated, sessionId: sessionId),
    );
    if (hasWatchUuid) {
      _reconcileWatchCapturedWriteback(sessionId, watchUuid);
    } else if (inferredWatchCapture) {
      _cancelQueuedWritebackForSession(sessionId);
    }
    if (_watchRecordingSessionId == sessionId) {
      _watchRecordingSessionId = null;
    }
    await _recordProcessedHealthId(sessionId, summary.id);

    unawaited(() async {
      try {
        final didUpdate = await WatchExerciseEffortService().computeAndPersist(
          session: stored,
          workoutRepository: _workoutRepository,
        );
        if (didUpdate) {
          _workoutEvents?.emit(
            WorkoutChange(
              kind: WorkoutChangeKind.updated,
              sessionId: sessionId,
            ),
          );
        }
      } catch (e, s) {
        dev.log(
          'Failed to compute watch exercise effort',
          name: 'WatchBridgeHandler',
          error: e,
          stackTrace: s,
        );
      }
    }());
  }

  Future<void> _handleHealthRecordingState(
    WatchHealthRecordingState state,
  ) async {
    final hasRecordingError = !state.isRecording && state.hasError;
    final explicitSessionId = state.sessionId?.trim();
    WorkoutSession? latestActiveSession;
    var sessionId = explicitSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      latestActiveSession = await _latestActiveSession();
      sessionId = latestActiveSession?.id;
    }
    if (sessionId == null || sessionId.isEmpty) return;

    var session = await _workoutRepository.getWorkoutSession(sessionId);
    if (session == null && hasRecordingError) {
      if (_cancelledSessionIds.contains(sessionId)) return;
      final fallbackSession =
          latestActiveSession ?? await _latestActiveSession();
      if (fallbackSession == null) return;
      sessionId = fallbackSession.id;
      session = fallbackSession;
    }
    if (session == null) return;

    // A delayed or pre-activation "started" acknowledgement must not revive a
    // session the phone already completed or explicitly discarded. Terminal
    // summaries/stops can still reconcile below; only the stale running edge is
    // rejected.
    if (state.isRecording &&
        (session.isCompleted ||
            session.endTime != null ||
            _cancelledSessionIds.contains(sessionId))) {
      await _recordProcessedHealthId(sessionId, state.id);
      return;
    }

    if (await _hasDuplicateHealthId(sessionId, state.id)) {
      return;
    }

    final now = DateTime.now();

    if (state.isRecording) {
      _watchRecordingSessionId = sessionId;
    } else {
      if (_watchRecordingSessionId == sessionId) {
        _watchRecordingSessionId = null;
      }
    }

    final workoutUuid = state.hkWorkoutUuid;
    final hasUuid = workoutUuid != null && workoutUuid.isNotEmpty;
    final shouldClearRecordingRequest =
        state.isRecording || hasRecordingError || hasUuid;
    final updated = session.copyWith(
      watchRecordingRequested: shouldClearRecordingRequest
          ? false
          : session.watchRecordingRequested,
      watchRecordingActive: state.isRecording,
      capturedOnWatch: hasUuid ? true : session.capturedOnWatch,
      watchCapturePending: hasRecordingError ? false : !hasUuid,
      watchCapturePendingAt: (hasRecordingError || hasUuid) ? null : now,
      watchWorkoutUuid: hasUuid ? workoutUuid : session.watchWorkoutUuid,
      watchRecordingStartMs:
          state.recordingStartMs ?? session.watchRecordingStartMs,
      lastUpdatedAt: now,
    );
    final markDirty = _shouldMarkDirtyForWatchSync(session, updated);
    await _workoutRepository.updateWorkoutSession(
      updated,
      markDirty: markDirty,
    );
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.updated, sessionId: sessionId),
    );
    await _recordProcessedHealthId(sessionId, state.id);
    if (!hasUuid) {
      if (hasRecordingError) {
        _cancelPendingWatchCaptureFallback(sessionId);
        _cancelQueuedWritebackForSession(sessionId);
        return;
      }
      _schedulePendingWatchCaptureFallback(sessionId);
      _cancelQueuedWritebackForSession(sessionId);
      return;
    }
    _cancelPendingWatchCaptureFallback(sessionId);
    _reconcileWatchCapturedWriteback(sessionId, workoutUuid);
  }

  /// Reconciles a full, self-contained session the watch captured while the
  /// phone was absent (Phase 3 / standalone watch mode).
  ///
  /// IDEMPOTENT: if a session already exists locally with the same id OR the
  /// same watch HealthKit UUID, the existing session is merged (fill missing
  /// watch metadata) rather than duplicated. Otherwise a completed
  /// [WorkoutSession] is created from the payload and marked dirty so
  /// [WorkoutSyncService] uploads it.
  Future<void> _handleWatchSession(WatchSession watchSession) async {
    if (_isWatchSessionTombstoned(watchSession)) {
      // The phone already cancelled/discarded this session. Refuse to re-adopt
      // or re-create it — a late/queued watch snapshot must not resurrect it.
      dev.log(
        'Ignoring tombstoned watch session id=${watchSession.id}',
        name: 'WatchBridgeHandler',
      );
      return;
    }
    final existing = await _findSessionForWatchSession(watchSession);
    if (existing != null) {
      if (watchSession.inProgress) {
        // Live handoff: the watch is still recording — update the adopted session.
        await _applyInProgressWatchSnapshot(existing, watchSession);
      } else {
        await _mergeWatchSession(existing, watchSession);
      }
      return;
    }
    await _createSessionFromWatch(watchSession);
  }

  Future<WorkoutSession?> _findSessionForWatchSession(
    WatchSession watchSession,
  ) async {
    final byId = await _workoutRepository.getWorkoutSession(watchSession.id);
    if (byId != null) return byId;

    final incomingUuid = watchSession.hkWorkoutUuid;
    if (incomingUuid == null || incomingUuid.isEmpty) return null;
    try {
      final sessions = await _workoutRepository.getWorkoutSessions();
      for (final session in sessions) {
        final uuid = session.watchWorkoutUuid;
        if (uuid != null && uuid.isNotEmpty && uuid == incomingUuid) {
          return session;
        }
      }
    } catch (_) {
      // Best-effort lookup; fall through to create.
    }
    return null;
  }

  Future<void> _mergeWatchSession(
    WorkoutSession existing,
    WatchSession watchSession,
  ) async {
    final incomingUuid = watchSession.hkWorkoutUuid;
    final effectiveUuid = incomingUuid != null && incomingUuid.isNotEmpty
        ? incomingUuid
        : existing.watchWorkoutUuid;
    final watchUuid = effectiveUuid ?? '';
    final hasWatchUuid = watchUuid.isNotEmpty;

    var updated = existing.copyWith(
      capturedOnWatch: true,
      watchCapturePending: false,
      watchCapturePendingAt: null,
      activeEnergyKilocalories:
          existing.activeEnergyKilocalories ?? watchSession.activeEnergyKcal,
      averageHeartRateBpm: existing.averageHeartRateBpm ?? watchSession.avgHr,
      maxHeartRateBpm: existing.maxHeartRateBpm ?? watchSession.maxHr,
      watchDurationSeconds:
          existing.watchDurationSeconds ?? watchSession.durationSec,
      watchWorkoutUuid: effectiveUuid ?? existing.watchWorkoutUuid,
      watchRecordingStartMs:
          existing.watchRecordingStartMs ?? watchSession.startedAtMs,
      watchRecordingEndMs:
          existing.watchRecordingEndMs ?? watchSession.endedAtMs,
      lastUpdatedAt: DateTime.now(),
    );

    // Handoff: a finished watch session completes a session we adopted live (the
    // user started on the watch, the phone adopted the in-progress snapshots, then
    // the watch finished). The finished payload arrives via guaranteed delivery, so
    // its set log is authoritative — replace the adopted one in case a live snapshot
    // was dropped (but don't wipe it if the finished payload carries no exercises).
    final endMs = watchSession.endedAtMs;
    final completesAdoptedSession =
        !existing.isCompleted && existing.endTime == null && endMs != null;
    if (completesAdoptedSession) {
      // Handoff into an EXISTING (adopted) session — MERGE, don't rebuild fresh.
      // `_exercisesFromWatch` passes no prior set tree, so phone-only data
      // (notably phone-entered RPE, which the watch never sends, and phone-only
      // exercises) would be wiped. `_mergeWatchExercises` reconciles with the
      // watch's authoritative sets while preserving `prior?.rpe` positionally.
      final fullExercises = _mergeWatchExercises(
        updated.exercises,
        watchSession,
      );
      updated = updated.copyWith(
        isCompleted: true,
        endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
        exercises: fullExercises.isNotEmpty ? fullExercises : updated.exercises,
      );
    }

    if (updated == existing) {
      // Nothing changed; idempotent no-op (e.g. replayed identical payload).
      _cancelPendingWatchCaptureFallback(existing.id);
      if (hasWatchUuid) {
        _reconcileWatchCapturedWriteback(existing.id, watchUuid);
      }
      return;
    }

    _cancelPendingWatchCaptureFallback(existing.id);
    // A watch session we adopted live was created clean (dirty:false, in-progress).
    // When the finished payload completes it HERE, `_shouldMarkDirtyForWatchSync`
    // sees `existing` as not-yet-completed and returns false, so the finished
    // workout would stay clean and never reach the backend. Force dirty (and a
    // sync) on the completion transition; otherwise fall back to the watch-field
    // delta check for an already-completed session getting late enrichment.
    final markDirty =
        completesAdoptedSession ||
        _shouldMarkDirtyForWatchSync(existing, updated);
    await _workoutRepository.updateWorkoutSession(
      updated,
      markDirty: markDirty,
    );
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.updated, sessionId: existing.id),
    );
    if (completesAdoptedSession &&
        GetIt.instance.isRegistered<WorkoutSyncService>()) {
      unawaited(GetIt.instance<WorkoutSyncService>().syncNow());
    }
    if (hasWatchUuid) {
      _reconcileWatchCapturedWriteback(existing.id, watchUuid);
    }
  }

  /// Build a fresh exercise tree purely from a watch payload (used only when no
  /// phone session exists yet — e.g. a standalone wrist workout the phone never
  /// adopted). For live handoffs into an EXISTING session, use
  /// [_mergeWatchExercises] instead so phone-only exercises are never dropped.
  List<WorkoutExercise> _exercisesFromWatch(WatchSession watchSession) {
    const uuid = Uuid();
    return <WorkoutExercise>[
      for (final ex in watchSession.exercises)
        WorkoutExercise(
          id: uuid.v4(),
          exercise: Exercise(
            id: ex.exerciseId,
            name: ex.name,
            muscles: const [],
            kind: _exerciseKindForWatchLoggingMode(ex.exerciseLoggingMode),
            loggingMode: _exerciseLoggingModeFromWatch(ex.exerciseLoggingMode),
          ),
          sets: _setsFromWatchExercise(
            ex,
            const [],
            uuid,
            keepEditableTail: watchSession.inProgress,
          ),
          // Wrist-minted row: the watch keeps re-sending ex.exerciseId (a catalog id,
          // never this fresh phone ROW UUID), so mark it so the live-merge can re-match
          // it by exercise.id on later snapshots instead of duplicating it.
          createdFromWatch: true,
        ),
    ];
  }

  /// Build the reconciled set list for a single matched exercise. Reuses the
  /// phone's existing set ids positionally (so set identity is stable across
  /// snapshots) and mints fresh ids for any additional watch sets. The watch's
  /// sets are authoritative for weight/reps/completion, except that a completed
  /// phone-side tail on a wrist-created row wins over a stale incomplete draft.
  List<WorkoutSet> _setsFromWatchExercise(
    WatchSessionExercise ex,
    List<WorkoutSet> existingSets,
    Uuid uuid, {
    bool keepEditableTail = false,
    bool preserveCompletedTailSets = false,
  }) {
    final sets = <WorkoutSet>[
      for (var i = 0; i < ex.sets.length; i++)
        () {
          final set = ex.sets[i];
          final prior = i < existingSets.length ? existingSets[i] : null;
          if (preserveCompletedTailSets &&
              prior != null &&
              prior.isCompleted &&
              !set.isCompleted) {
            return prior;
          }
          return WorkoutSet(
            id: prior?.id ?? uuid.v4(),
            weight: set.weight,
            reps: set.reps,
            // New watches mark the RPE field as known, so a null is an explicit
            // clear. Older payloads omit both fields; preserve any phone value.
            rpe: set.rpeKnown ? set.rpe : prior?.rpe,
            setType: prior?.setType ?? SetType.regular,
            isCompleted: set.isCompleted,
            completedAt: !set.isCompleted
                ? null
                : set.completedAtMs == null
                ? prior?.completedAt
                : DateTime.fromMillisecondsSinceEpoch(set.completedAtMs!),
            isPr: prior?.isPr ?? false,
          );
        }(),
    ];
    if (preserveCompletedTailSets) {
      for (var i = ex.sets.length; i < existingSets.length; i++) {
        final prior = existingSets[i];
        if (!prior.isCompleted) break;
        sets.add(prior);
      }
    }
    if (keepEditableTail && !sets.any((set) => !set.isCompleted)) {
      final tailIndex = sets.length;
      final prior = tailIndex < existingSets.length
          ? existingSets[tailIndex]
          : null;
      final reusablePrior = prior != null && !prior.isCompleted ? prior : null;
      final seed = reusablePrior ?? (sets.isNotEmpty ? sets.last : prior);
      sets.add(
        WorkoutSet(
          id: reusablePrior?.id ?? uuid.v4(),
          weight: seed?.weight ?? 0,
          reps: seed?.reps ?? 0,
          rpe: reusablePrior?.rpe,
          setType: reusablePrior?.setType ?? SetType.regular,
          notes: reusablePrior?.notes,
          isCompleted: false,
          completedAt: null,
          isPr: reusablePrior?.isPr ?? false,
          watchCommandId: reusablePrior?.watchCommandId,
          parentSetId: reusablePrior?.parentSetId,
          dropIndex: reusablePrior?.dropIndex,
        ),
      );
    }
    return sets;
  }

  /// MERGE a live watch snapshot's exercises into the phone's current exercises
  /// instead of regenerating the whole tree.
  ///
  /// Matching is done on the per-instance `WorkoutExercise` ROW UUID — the id the
  /// phone publishes as `exerciseId` in [buildStatePayload] (`selection.exercise.id`)
  /// and the watch echoes back as [WatchSessionExercise.exerciseId]. The earlier
  /// code keyed the phone side on `phoneEx.exercise.id` (the *library* `Exercise.id`)
  /// while the watch side carried the row UUID, so the two id-spaces never matched
  /// and a single phone-driven exercise was APPENDED as a second card (the #359
  /// regression: one "Reverse Fly (Machine)" showing up twice). A case-insensitive
  /// NAME fallback covers the residual id-namespace edge where a watch echo DROPPED
  /// its id (id null/empty) so we reconcile instead of duplicating. The fallback is
  /// deliberately limited to BLANK ids: a watch instance carrying a non-empty id the
  /// phone doesn't have is a genuinely separate instance, and matching it by name
  /// would overwrite the phone row's sets (the inverse of #359).
  ///
  /// The four matching cases this handles:
  ///   1. Phone-driven: the watch echoes the phone ROW UUID -> primary row-UUID match
  ///      -> ONE card.
  ///   2. Watch-owned/catalog (the #376 [P1] fix): the phone row was MINTED from the
  ///      watch (`createdFromWatch`), so the watch keeps sending the catalog id stored
  ///      on `phoneEx.exercise.id` (never the fresh ROW UUID). A secondary, watch-
  ///      created-only match on `exercise.id` reconciles the row on later snapshots so
  ///      it is NOT re-appended on every live update.
  ///   3. Genuine separate instance: a distinct non-empty watch id the phone doesn't
  ///      have (and that no watch-created row owns) -> append (never name-collapsed).
  ///   4. Blank/missing watch id -> name fallback.
  ///
  /// The secondary (case 2) match is gated on `createdFromWatch` precisely so a
  /// catalog-id collision on a PHONE-authored row can never collapse two distinct phone
  /// instances (the #359 overwrite).
  ///
  /// Invariants for a LIVE handoff:
  ///   * phone-only exercises absent from the watch payload are kept (a phone-added
  ///     exercise survives a stale/smaller watch snapshot),
  ///   * a matched exercise has its sets reconciled (genuine watch set edits apply),
  ///   * the exercise list never shrinks,
  ///   * superset grouping (supersetGroupId / supersetOrder) and notes/restTimer
  ///     are preserved on matched exercises,
  ///   * watch-only exercises (logged on the wrist with their OWN id) are appended,
  ///   * a phone-driven exercise + its watch echo (same row UUID) collapse to ONE
  ///     card; a watch echo that dropped its id reconciles by name,
  ///   * the watch genuinely logging the same exercise as a second instance under a
  ///     DISTINCT non-empty id the phone doesn't have still yields TWO cards (it is
  ///     NOT collapsed onto the same-named phone row).
  List<WorkoutExercise> _mergeWatchExercises(
    List<WorkoutExercise> existing,
    WatchSession watchSession,
  ) {
    const uuid = Uuid();

    // Wire-order list of incoming watch instances, each with a "consumed" flag so a
    // single watch instance is matched to at most one phone instance and appended at
    // most once. A workout can contain the SAME exercise more than once (two blocks
    // of "Bench Press"), so we track instances individually rather than by key.
    final watch = <_WatchInstance>[
      for (final ex in watchSession.exercises) _WatchInstance(ex),
    ];

    String? rowId(String? raw) {
      final id = raw?.trim();
      return (id == null || id.isEmpty) ? null : id;
    }

    final merged = <WorkoutExercise>[];

    // 1) Walk the phone's exercises in order. Reconcile each matched one by CONSUMING
    //    one watch instance; keep phone-only ones untouched (NEVER shrink / drop).
    //    PRIMARY match: the watch instance's echoed row UUID == this phone row UUID.
    //    FALLBACK match: an as-yet-unconsumed watch instance with a BLANK/MISSING id
    //    whose name matches (case-insensitive) — covers an echo that DROPPED its id.
    //    A watch instance with a NON-EMPTY id that doesn't match any phone row UUID is
    //    a GENUINELY separate instance (e.g. a second "Bench" the wrist started under
    //    its own id); matching it by name would OVERWRITE the phone row's sets, so it
    //    is left for step 2 to append. Restricting the fallback to blank ids prevents
    //    that inverse-of-#359 overwrite (a phone "Bench" silently eaten by a distinct
    //    watch "Bench").
    for (final phoneEx in existing) {
      _WatchInstance? hit;
      // Primary: row-UUID match (the per-instance id the watch echoes).
      for (final w in watch) {
        if (w.consumed) continue;
        if (rowId(w.exercise.exerciseId) == phoneEx.id) {
          hit = w;
          break;
        }
      }
      // Secondary (watch-created rows only): a wrist-minted phone row carries a fresh
      // ROW UUID the watch never echoes; the watch instead keeps sending the catalog id
      // it owns, which we stored on `phoneEx.exercise.id`. Re-match that id so the row
      // is reconciled across snapshots instead of re-appended on every live update
      // (the #376 [P1] watch-owned duplication). Gated on `createdFromWatch` so a
      // coincidental catalog-id collision can NEVER collapse two distinct PHONE rows
      // (that would reintroduce the #359 overwrite). Consumed-flag + wire order still
      // hold, so a genuine second wrist instance of the same catalog id falls through
      // to step 2 and appends (case 3).
      if (hit == null && phoneEx.createdFromWatch) {
        final phoneCatalogId = rowId(phoneEx.exercise.id);
        if (phoneCatalogId != null) {
          for (final w in watch) {
            if (w.consumed) continue;
            if (rowId(w.exercise.exerciseId) == phoneCatalogId) {
              hit = w;
              break;
            }
          }
        }
      }
      // Fallback: name match against a still-unconsumed instance that carries NO id.
      if (hit == null) {
        final phoneName = phoneEx.exercise.name.trim().toLowerCase();
        for (final w in watch) {
          if (w.consumed) continue;
          if (rowId(w.exercise.exerciseId) != null) {
            continue; // has a distinct id
          }
          if (w.exercise.name.trim().toLowerCase() == phoneName) {
            hit = w;
            break;
          }
        }
      }
      if (hit == null) {
        merged.add(phoneEx); // phone-only / no match: preserve exactly.
        continue;
      }
      hit.consumed = true;
      // Reconcile sets; keep the phone's identity + grouping + metadata.
      merged.add(
        phoneEx.copyWith(
          sets: _setsFromWatchExercise(
            hit.exercise,
            phoneEx.sets,
            uuid,
            keepEditableTail:
                watchSession.inProgress && phoneEx.createdFromWatch,
            preserveCompletedTailSets:
                watchSession.inProgress && phoneEx.createdFromWatch,
          ),
        ),
      );
    }

    // 2) Append any watch instances step 1 didn't consume — exercises logged on the
    //    wrist that the phone genuinely doesn't have yet (including a genuine repeat
    //    of an exercise the phone only had once), in wire order.
    for (final w in watch) {
      if (w.consumed) continue;
      final ex = w.exercise;
      merged.add(
        WorkoutExercise(
          id: uuid.v4(),
          exercise: Exercise(
            id: ex.exerciseId,
            name: ex.name,
            muscles: const [],
            kind: _exerciseKindForWatchLoggingMode(ex.exerciseLoggingMode),
            loggingMode: _exerciseLoggingModeFromWatch(ex.exerciseLoggingMode),
          ),
          sets: _setsFromWatchExercise(
            ex,
            const [],
            uuid,
            keepEditableTail: watchSession.inProgress,
          ),
          // Wrist-started row: fresh phone ROW UUID, but the watch will keep echoing
          // ex.exerciseId (the catalog id) — NOT this UUID. Mark it watch-created so the
          // NEXT snapshot re-matches it by exercise.id (case 2) instead of appending it
          // again on every live update (the #376 [P1] duplication this fixes).
          createdFromWatch: true,
        ),
      );
    }

    return merged;
  }

  ExerciseLoggingMode _exerciseLoggingModeFromWatch(String? raw) {
    switch (raw?.trim()) {
      case 'distanceDuration':
      case 'distance_duration':
        return ExerciseLoggingMode.distanceDuration;
      case 'durationOnly':
      case 'duration_only':
        return ExerciseLoggingMode.durationOnly;
      default:
        return ExerciseLoggingMode.weightReps;
    }
  }

  ExerciseKind _exerciseKindForWatchLoggingMode(String? raw) {
    final mode = _exerciseLoggingModeFromWatch(raw);
    return mode == ExerciseLoggingMode.distanceDuration
        ? ExerciseKind.cardio
        : ExerciseKind.strength;
  }

  Future<void> _createSessionFromWatch(WatchSession watchSession) async {
    final inProgress = watchSession.inProgress;
    final endMs = watchSession.endedAtMs;
    final startTime = DateTime.fromMillisecondsSinceEpoch(
      watchSession.startedAtMs,
    );
    final endTime = (inProgress || endMs == null)
        ? null
        : DateTime.fromMillisecondsSinceEpoch(endMs);
    final hkUuid = watchSession.hkWorkoutUuid;

    final session = WorkoutSession(
      id: watchSession.id,
      name: 'Workout',
      startTime: startTime,
      endTime: endTime,
      exercises: _exercisesFromWatch(watchSession),
      // In-progress sessions are adopted as the phone's live workout (the user can
      // continue them); only finished ones are completed + synced.
      isCompleted: !inProgress,
      dirty: !inProgress,
      capturedOnWatch: true,
      activeEnergyKilocalories: watchSession.activeEnergyKcal,
      averageHeartRateBpm: watchSession.avgHr,
      maxHeartRateBpm: watchSession.maxHr,
      watchDurationSeconds: watchSession.durationSec,
      watchWorkoutUuid: hkUuid,
      watchRecordingStartMs: watchSession.startedAtMs,
      watchRecordingEndMs: endMs,
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        watchSession.snapshotMs ?? endMs ?? watchSession.startedAtMs,
      ),
      timelineEvents: [
        ExerciseTimelineEvent(
          tsMs: watchSession.startedAtMs,
          kind: ExerciseTimelineEventKind.workoutStart,
        ),
        if (!inProgress && endMs != null)
          ExerciseTimelineEvent(
            tsMs: endMs,
            kind: ExerciseTimelineEventKind.workoutEnd,
          ),
      ],
    );

    final created = await _workoutRepository.createWorkoutSession(session);
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.created, sessionId: created.id),
    );
    if (inProgress) {
      _maybeNavigateToActiveWorkout(created);
      _notificationService.showWorkoutOngoing(
        startTime: created.startTime,
        currentExerciseName: created.exercises.isNotEmpty
            ? created.exercises.first.exercise.name
            : null,
      );
    }
    if (!inProgress && GetIt.instance.isRegistered<WorkoutSyncService>()) {
      unawaited(GetIt.instance<WorkoutSyncService>().syncNow());
    }
    if (!inProgress && hkUuid != null && hkUuid.isNotEmpty) {
      _reconcileWatchCapturedWriteback(created.id, hkUuid);
    }
  }

  /// Live handoff: apply a streamed in-progress snapshot to an already-adopted
  /// session, last-writer-wins by snapshot time so the phone's own edits (when the
  /// user has continued there) are never clobbered by a stale watch snapshot.
  Future<void> _applyInProgressWatchSnapshot(
    WorkoutSession existing,
    WatchSession watchSession,
  ) async {
    if (existing.isCompleted || existing.endTime != null) return;
    if (_isWatchSessionTombstoned(watchSession)) {
      return; // cancelled; never re-adopt.
    }
    final snapMs = watchSession.snapshotMs ?? watchSession.startedAtMs;
    final persistedMs = existing.lastUpdatedAt?.millisecondsSinceEpoch ?? 0;
    // Compare against the WATERMARK as well as the persisted time. The watermark
    // captures the newest snapshot we observed even when its UI emission was
    // suppressed (the no-op heartbeat path below), so an out-of-order
    // older-but-changed snapshot can't slip past `lastUpdatedAt` and clobber state.
    final watermarkMs = _liveWatchSnapWatermark[existing.id] ?? 0;
    final existingMs = persistedMs > watermarkMs ? persistedMs : watermarkMs;
    if (snapMs <= existingMs) {
      return; // phone (or a newer watch snapshot) wins; ignore.
    }

    // MERGE (don't replace): protect phone-only exercises and superset grouping
    // while letting genuine watch set edits through. Regenerating the whole tree
    // here (the old behavior) dropped phone-added exercises and minted fresh
    // uuids — the live-handoff crash root cause.
    final mergedExercises = _mergeWatchExercises(
      existing.exercises,
      watchSession,
    );

    // Only persist + emit on a REAL content delta. The watch heartbeats a fresh
    // snapshot every few seconds even when nothing changed; without this guard a
    // merge that merely re-stamped `lastUpdatedAt` would still `updated != existing`
    // and fire a WorkoutChange, re-rendering the live screen and re-publishing watch
    // state on a loop (the sync churn / lag). A bumped `lastUpdatedAt` with identical
    // exercises + watch metadata is a no-op for the user, so we skip it.
    final exercisesUnchanged = listEquals(mergedExercises, existing.exercises);
    final metaUnchanged =
        existing.capturedOnWatch == true &&
        existing.watchRecordingStartMs != null;
    if (exercisesUnchanged && metaUnchanged) {
      // No-op heartbeat: suppress the UI emission (lag/churn fix) but STILL advance
      // the watermark so this snapshot's `snapMs` raises the staleness floor. A later
      // delayed older-but-changed snapshot is then correctly rejected as stale.
      _liveWatchSnapWatermark[existing.id] = snapMs;
      return;
    }

    final updated = existing.copyWith(
      exercises: mergedExercises,
      capturedOnWatch: true,
      watchRecordingStartMs:
          existing.watchRecordingStartMs ?? watchSession.startedAtMs,
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(snapMs),
    );
    if (updated == existing) return;
    _liveWatchSnapWatermark[existing.id] = snapMs;
    await _workoutRepository.updateWorkoutSession(updated, markDirty: false);
    _workoutEvents?.emit(
      WorkoutChange(kind: WorkoutChangeKind.updated, sessionId: existing.id),
    );
  }

  Future<WorkoutSession?> _latestActiveSession() async {
    final session = await _workoutRepository.getLatestActiveSession();
    if (session == null) return null;
    if (session.isCompleted || session.endTime != null) return null;
    return session;
  }

  Map<String, dynamic> _restPayload(
    DateTime now, {
    WatchBridgeResolvedSelection? selection,
  }) {
    final status = _restTimerService.status;
    final isActive =
        status == TimerStatus.running || status == TimerStatus.paused;
    final isCompleted = status == TimerStatus.completed;
    final targetSec = isActive || isCompleted
        ? _restTimerService.originalDurationSeconds
        : selection?.exercise.restTimerSeconds ??
              RestTimerService.defaultRestTime;
    final remainingSec = isActive || isCompleted
        ? _restTimerService.remainingSeconds
        : targetSec;
    final exerciseId = isActive || isCompleted
        ? _restTimerService.currentExerciseId
        : selection?.exercise.id;
    return {
      'status': status.name,
      'active': isActive,
      'remainingSec': remainingSec,
      'originalSec': targetSec,
      'targetSec': targetSec,
      'exerciseId': exerciseId,
      'ts': now.millisecondsSinceEpoch,
    };
  }

  Future<bool> _hasDuplicateCommandId(String sessionKey, String id) async {
    await _ensureRecentCommandIdsLoaded();
    return _recentCommandIds[sessionKey]?.contains(id) ?? false;
  }

  Future<void> _recordProcessedCommandId(String sessionKey, String id) async {
    if (id.isEmpty) return;
    await _ensureRecentCommandIdsLoaded();
    _recordRecentId(_recentCommandIds, sessionKey, id);
    await _saveRecentIds(_recentCommandIdsPrefsKey, _recentCommandIds);
  }

  Future<bool> _hasDuplicateHealthId(String sessionKey, String id) async {
    await _ensureRecentHealthIdsLoaded();
    return _recentHealthIds[sessionKey]?.contains(id) ?? false;
  }

  Future<void> _recordProcessedHealthId(String sessionKey, String id) async {
    if (id.isEmpty) return;
    await _ensureRecentHealthIdsLoaded();
    _recordRecentId(_recentHealthIds, sessionKey, id);
    await _saveRecentIds(_recentHealthIdsPrefsKey, _recentHealthIds);
  }

  Future<void> _ensureRecentCommandIdsLoaded() async {
    if (_recentCommandIdsLoaded) return;
    await _loadRecentIds(_recentCommandIdsPrefsKey, _recentCommandIds);
    _recentCommandIdsLoaded = true;
  }

  Future<void> _ensureRecentHealthIdsLoaded() async {
    if (_recentHealthIdsLoaded) return;
    await _loadRecentIds(_recentHealthIdsPrefsKey, _recentHealthIds);
    _recentHealthIdsLoaded = true;
  }

  Future<void> _loadRecentIds(
    String prefsKey,
    Map<String, List<String>> store,
  ) async {
    final prefs = _preferences;
    if (prefs == null) return;
    try {
      final raw = await prefs.getRawString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty || value is! List) continue;
        final ids = value
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.isEmpty) continue;
        final existing = store.putIfAbsent(key, () => <String>[]);
        for (final id in ids) {
          existing.remove(id);
          existing.add(id);
        }
        store[key] = _tailRecentIds(existing, _recentIdsLimit);
      }
      if (store.length > _recentIdSessionLimit) {
        final overflow = store.length - _recentIdSessionLimit;
        for (final key in store.keys.take(overflow).toList()) {
          store.remove(key);
        }
      }
    } catch (_) {
      // Persistence is best-effort; keep the in-memory dedupe ledger usable.
    }
  }

  Future<void> _saveRecentIds(
    String prefsKey,
    Map<String, List<String>> store,
  ) async {
    final prefs = _preferences;
    if (prefs == null) return;
    try {
      if (store.length > _recentIdSessionLimit) {
        final overflow = store.length - _recentIdSessionLimit;
        for (final key in store.keys.take(overflow).toList()) {
          store.remove(key);
        }
      }
      final payload = <String, List<String>>{};
      for (final entry in store.entries) {
        if (entry.value.isEmpty) continue;
        payload[entry.key] = _tailRecentIds(entry.value, _recentIdsLimit);
      }
      await prefs.setRawString(prefsKey, json.encode(payload));
    } catch (_) {
      // Best-effort: in-memory dedupe still protects the current process.
    }
  }

  void _recordRecentId(
    Map<String, List<String>> store,
    String sessionKey,
    String id,
  ) {
    if (id.isEmpty) return;
    final ids = store.putIfAbsent(sessionKey, () => <String>[]);
    ids.remove(id);
    ids.add(id);
    if (ids.length > _recentIdsLimit) {
      ids.removeRange(0, ids.length - _recentIdsLimit);
    }
  }

  List<String> _tailRecentIds(List<String> ids, int limit) {
    if (ids.length <= limit) return List<String>.from(ids);
    return ids.sublist(ids.length - limit);
  }

  bool _sessionContainsWatchCommandId(
    WorkoutSession? session,
    String commandId,
  ) {
    if (session == null || commandId.isEmpty) return false;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (set.watchCommandId == commandId) return true;
      }
    }
    return false;
  }

  String? _watchCommandIdOrNull(String commandId) {
    return commandId.isEmpty ? null : commandId;
  }

  /// Compact, log-safe summary of the active session's exercise rows: for each
  /// row, its phone row id plus (when present) its catalog id and whether it was
  /// created from the watch. Emitted on the stale-id no-op / foreign-session
  /// paths so an on-device repro shows WHY a watch command's exercise id didn't
  /// match (e.g. the phone re-created the row with a new id, or the row is
  /// phone-authored so the catalog-id rescue — watch-created rows only — was
  /// skipped). See issue #481.
  String _describeSessionExerciseIds(WorkoutSession? session) {
    final exercises = session?.exercises;
    if (exercises == null || exercises.isEmpty) return 'none';
    return exercises
        .map((e) {
          final catalogId = e.exercise.id?.trim();
          final cat = (catalogId != null && catalogId.isNotEmpty)
              ? ' cat=$catalogId'
              : '';
          final watch = e.createdFromWatch ? ' fromWatch' : '';
          return '${e.id}$cat$watch';
        })
        .join(', ');
  }

  /// Record [id] as an APPLIED set-mutation command so the next published state
  /// echoes it in `appliedCommandIds`. Called for every log_set / add_set the
  /// handler processes to completion (including a stale-id no-op that republishes
  /// state) — the watch only ever creates an overlay for a command it sent, so an
  /// echoed id is an unambiguous "I processed your command" ack that clears the
  /// matching overlay regardless of which exercise the echo selects. Bounded FIFO;
  /// duplicates are coalesced (a re-sent id keeps a single, most-recent slot).
  void _recordAppliedCommandId(String id) {
    if (id.isEmpty) return;
    // An id is either applied or rejected, never both: if this command was
    // previously (speculatively) rejected, drop that stale reject so the watch
    // doesn't see a contradictory echo.
    _rejectedCommandIds.remove(id);
    _appliedCommandIds.remove(id);
    _appliedCommandIds.add(id);
    if (_appliedCommandIds.length > _appliedCommandIdsLimit) {
      _appliedCommandIds.removeRange(
        0,
        _appliedCommandIds.length - _appliedCommandIdsLimit,
      );
    }
  }

  /// Record [id] as a REJECTED set-mutation command (#481) — the phone dropped it
  /// without applying because its target session is unknown or terminal. Mirrors
  /// [_recordAppliedCommandId]; the id is echoed in `rejectedCommandIds` so the
  /// watch reverts its optimistic overlay and signals failure instead of the old
  /// silent success. Bounded FIFO; mutually exclusive with the applied ledger.
  void _recordRejectedCommandId(String id) {
    if (id.isEmpty) return;
    _appliedCommandIds.remove(id);
    _rejectedCommandIds.remove(id);
    _rejectedCommandIds.add(id);
    if (_rejectedCommandIds.length > _appliedCommandIdsLimit) {
      _rejectedCommandIds.removeRange(
        0,
        _rejectedCommandIds.length - _appliedCommandIdsLimit,
      );
    }
  }

  /// Record the ack for a set-mutation command on an
  /// EARLY-RETURN path (dedup / foreign-session) that returns before the switch
  /// would normally call [_recordAppliedCommandId]. Only set-mutation commands
  /// raise optimistic overlays on the watch, so only they need to be acked here;
  /// other command types are ignored so the bounded ledger is not diluted.
  void _maybeRecordSetMutationAck(WatchCommand command) {
    if (command.type == WatchCommandType.markSetComplete ||
        command.type == WatchCommandType.logSet ||
        command.type == WatchCommandType.addSet) {
      _recordAppliedCommandId(command.id);
    }
  }

  /// Companion to [_maybeRecordSetMutationAck] for the foreign-session DROP path
  /// (#481): a set-mutation whose target session is unknown/terminal was NOT
  /// applied, so it must be reported as REJECTED (not applied). Only set-mutation
  /// commands raise an optimistic overlay on the watch, so only they are recorded.
  void _maybeRecordSetMutationReject(WatchCommand command) {
    if (command.type == WatchCommandType.markSetComplete ||
        command.type == WatchCommandType.logSet ||
        command.type == WatchCommandType.addSet) {
      _recordRejectedCommandId(command.id);
    }
  }

  /// Resolve [sessionId] to a session a foreign-session set-mutation can be safely
  /// RETARGETED onto (#481 recovery): it must exist, be non-terminal (not
  /// completed/ended), and not have been tombstoned (cancelled/discarded). Returns
  /// null when the target is unknown or terminal — in which case the mutation is
  /// rejected rather than applied, so a set is never written to a session that is
  /// genuinely gone.
  Future<WorkoutSession?> _resolveRecoverableSession(String sessionId) async {
    if (sessionId.isEmpty) return null;
    if (_cancelledSessionIds.contains(sessionId)) return null;
    final target = await _workoutRepository.getWorkoutSession(sessionId);
    if (target == null) return null;
    if (target.isCompleted || target.endTime != null) return null;
    return target;
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

  bool _shouldMarkDirtyForWatchSync(
    WorkoutSession before,
    WorkoutSession after,
  ) {
    // Watch-derived metadata can arrive after a workout has already been
    // completed and synced. Only then do we need to re-mark dirty to upload
    // these fields.
    final isCompleted = before.endTime != null || before.isCompleted;
    if (!isCompleted) return false;

    return before.capturedOnWatch != after.capturedOnWatch ||
        before.activeEnergyKilocalories != after.activeEnergyKilocalories ||
        before.averageHeartRateBpm != after.averageHeartRateBpm ||
        before.maxHeartRateBpm != after.maxHeartRateBpm ||
        before.watchDurationSeconds != after.watchDurationSeconds ||
        before.watchWorkoutUuid != after.watchWorkoutUuid ||
        before.watchRecordingStartMs != after.watchRecordingStartMs ||
        before.watchRecordingEndMs != after.watchRecordingEndMs;
  }

  Future<void> _recordTimelineEvent({
    required WorkoutSession session,
    required ExerciseTimelineEventKind kind,
    String? workoutExerciseId,
    int? tsMs,
  }) async {
    final event = ExerciseTimelineEvent(
      tsMs: tsMs ?? DateTime.now().millisecondsSinceEpoch,
      kind: kind,
      workoutExerciseId: workoutExerciseId,
    );
    final updated = _appendTimelineEvent(session, event);
    if (updated == session) return;
    await _workoutRepository.updateWorkoutSession(updated, markDirty: false);
  }

  void _cancelQueuedWritebackForSession(String sessionId) {
    if (!GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) return;
    unawaited(
      GetIt.instance<WorkoutWritebackCoordinator>().cancelQueuedWriteback(
        sessionId,
      ),
    );
  }

  void _reconcileWatchCapturedWriteback(String sessionId, String workoutUuid) {
    if (!GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) return;
    unawaited(
      GetIt.instance<WorkoutWritebackCoordinator>().handleWatchCapturedWorkout(
        sessionId: sessionId,
        watchWorkoutUuid: workoutUuid,
      ),
    );
  }

  void dispose() {
    for (final timer in _pendingWatchCaptureTimers.values) {
      timer.cancel();
    }
    _pendingWatchCaptureTimers.clear();
  }
}

/// A single incoming watch exercise plus a mutable "consumed" flag, used by
/// [WatchBridgeHandler._mergeWatchExercises] so each watch instance is matched to
/// at most one phone exercise (and otherwise appended exactly once).
class _WatchInstance {
  _WatchInstance(this.exercise);

  final WatchSessionExercise exercise;
  bool consumed = false;
}
