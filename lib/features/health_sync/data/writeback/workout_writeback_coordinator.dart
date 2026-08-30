import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/services/preferences_service.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../domain/writeback/workout_record_mapper.dart';
import '../../domain/writeback/workout_write_service.dart';
import '../../domain/writeback/workout_record.dart';
import 'workout_write_queue.dart';

const Duration _defaultWatchCompanionWritebackGracePeriod = Duration(
  seconds: 20,
);
const bool _watchCompanionEnvEnabled = bool.fromEnvironment(
  'WATCH_COMPANION_ENABLED',
  defaultValue: false,
);

class WorkoutWritebackState {
  const WorkoutWritebackState({
    required this.capability,
    required this.enabled,
    required this.permissionsGranted,
    required this.queueLength,
  });

  final WorkoutWriteCapability? capability;
  final bool enabled;
  final bool permissionsGranted;
  final int queueLength;

  WorkoutWritebackState copyWith({
    WorkoutWriteCapability? capability,
    bool? enabled,
    bool? permissionsGranted,
    int? queueLength,
  }) {
    return WorkoutWritebackState(
      capability: capability ?? this.capability,
      enabled: enabled ?? this.enabled,
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
      queueLength: queueLength ?? this.queueLength,
    );
  }
}

class WorkoutWritebackCoordinator {
  WorkoutWritebackCoordinator({
    required WorkoutWriteQueue queue,
    required WorkoutWriteService service,
    required PreferencesService preferences,
    required WorkoutRepository workoutRepository,
    WorkoutRecordMapper? mapper,
    Duration? watchCompanionWritebackGracePeriod,
  }) : _queue = queue,
       _service = service,
       _preferences = preferences,
       _workoutRepository = workoutRepository,
       _mapper = mapper ?? const WorkoutRecordMapper(),
       _watchCompanionWritebackGracePeriod =
           watchCompanionWritebackGracePeriod ??
           _defaultWatchCompanionWritebackGracePeriod;

  final WorkoutWriteQueue _queue;
  final WorkoutWriteService _service;
  final PreferencesService _preferences;
  final WorkoutRepository _workoutRepository;
  final WorkoutRecordMapper _mapper;
  final Duration _watchCompanionWritebackGracePeriod;
  final ValueNotifier<WorkoutWritebackState> state = ValueNotifier(
    const WorkoutWritebackState(
      capability: null,
      enabled: false,
      permissionsGranted: false,
      queueLength: 0,
    ),
  );

  StreamSubscription<WorkoutWriteEvent>? _queueEventsSub;
  bool _capabilityRefreshInFlight = false;
  Completer<void>? _initCompleter;
  final Map<String, Timer> _watchGraceTimers = {};

  Future<void> init() async {
    final existing = _initCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<void>();
    _initCompleter = completer;

    () async {
      try {
        await _initInternal();
        completer.complete();
      } catch (error, stackTrace) {
        _initCompleter = null;
        completer.completeError(error, stackTrace);
      }
    }();

    return completer.future;
  }

  Future<void> _initInternal() async {
    final capability = await _service.getCapabilities();
    await _queue.refreshCapability();
    await _queue.hydrate(process: false);

    final enabled = await _loadEnabled(capability.platform);
    final stateValue = state.value.copyWith(
      capability: capability,
      enabled: enabled,
      permissionsGranted: capability.hasWorkoutPermission,
      queueLength: _pendingCount(),
    );
    if (kDebugMode) {
      debugPrint(
        '[WorkoutWriteback] init capability=${capability.platform.name} '
        'supported=${capability.supported} hasPermission=${capability.hasWorkoutPermission} '
        'enabled=$enabled pending=${stateValue.queueLength}',
      );
    }
    state.value = stateValue;

    if (_shouldProcess(capability, enabled)) {
      _dispatchGuarded(() => _queue.process(), 'queue.process');
    }

    _queueEventsSub = _queue.events.listen((event) {
      if (event.type == WorkoutWriteEventType.permissionsUpdated) {
        _dispatchGuarded(() => _refreshCapability(), 'refreshCapability');
      }
      state.value = state.value.copyWith(queueLength: _pendingCount());
    });
  }

  Future<void> dispose() async {
    await _queueEventsSub?.cancel();
    for (final timer in _watchGraceTimers.values) {
      timer.cancel();
    }
    _watchGraceTimers.clear();
  }

  Future<void> _refreshCapability() async {
    if (_capabilityRefreshInFlight) {
      return;
    }
    _capabilityRefreshInFlight = true;
    try {
      await _queue.refreshCapability();
      await _queue.hydrate(process: false);
      await _queue.resetFailures();
      final capability = await _service.getCapabilities();
      final enabled = await _loadEnabled(capability.platform);
      state.value = state.value.copyWith(
        capability: capability,
        enabled: enabled,
        permissionsGranted: capability.hasWorkoutPermission,
        queueLength: _pendingCount(),
      );
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] refresh capability=${capability.platform.name} '
          'supported=${capability.supported} hasPermission=${capability.hasWorkoutPermission} '
          'enabled=$enabled pending=${state.value.queueLength}',
        );
      }
      if (_shouldProcess(capability, enabled)) {
        _dispatchGuarded(() => _queue.process(), 'queue.process');
      }
    } finally {
      _capabilityRefreshInFlight = false;
    }
  }

  Future<void> toggleEnabled(bool enable) async {
    var capability = await _service.getCapabilities();
    await _storeEnabled(capability.platform, enable);
    if (enable) {
      // Request the full set of scopes, but only treat workout permission as
      // required for enabling writeback. Optional scopes may be declined.
      await _service.requestPermissions({
        WorkoutPermissionScope.workouts,
        WorkoutPermissionScope.energy,
        WorkoutPermissionScope.distance,
        WorkoutPermissionScope.heartRate,
      });
      capability = await _service.getCapabilities();
      if (!capability.hasWorkoutPermission) {
        state.value = state.value.copyWith(
          capability: capability,
          enabled: false,
          permissionsGranted: false,
        );
        await _storeEnabled(capability.platform, false);
        return;
      }
    }

    state.value = state.value.copyWith(
      capability: capability,
      enabled: enable,
      permissionsGranted: enable ? capability.hasWorkoutPermission : false,
      queueLength: _pendingCount(),
    );
    if (kDebugMode) {
      debugPrint(
        '[WorkoutWriteback] toggle enable=$enable initialPermission=${capability.hasWorkoutPermission} '
        'storedPermission=${state.value.permissionsGranted}',
      );
    }
    if (!enable) {
      await _preferences.clearWorkoutWritebackMappings();
      await _queue.clear();
    }
    await _refreshCapability();
  }

  int _pendingCount() {
    return _queue.items
        .where((item) => item.status != WorkoutWriteStatus.written)
        .length;
  }

  bool _shouldProcess(WorkoutWriteCapability capability, bool enabled) {
    return enabled && capability.supported && capability.hasWorkoutPermission;
  }

  Future<bool> _isWatchCompanionEnabled() async {
    try {
      final base = _watchCompanionEnvEnabled
          ? true
          : await _preferences.getWatchCompanionEnabled();
      final override = await _preferences.getWatchCompanionDebugOverride();
      return override ?? base;
    } catch (_) {
      return _watchCompanionEnvEnabled;
    }
  }

  Future<bool> _shouldDeferWriteback(WorkoutSession session) async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (!await _isWatchCompanionEnabled()) return false;

    // Only defer near completion so edits long after the fact still sync quickly.
    final endedAt = session.endTime;
    if (endedAt == null) return true;
    final age = DateTime.now().difference(endedAt);
    if (age.isNegative) return false;
    return age <= _watchCompanionWritebackGracePeriod;
  }

  void _scheduleDeferredWriteback(String sessionId) {
    _watchGraceTimers.remove(sessionId)?.cancel();
    _watchGraceTimers[sessionId] = Timer(
      _watchCompanionWritebackGracePeriod,
      () {
        _watchGraceTimers.remove(sessionId);
        _dispatchGuarded(
          () => _attemptDeferredWriteback(sessionId),
          'attemptDeferredWriteback',
        );
      },
    );
  }

  Future<void> _attemptDeferredWriteback(String sessionId) async {
    if (!state.value.enabled) return;
    final session = await _workoutRepository.getWorkoutSession(sessionId);
    if (session == null) return;
    if (!session.isCompleted) return;

    if (session.capturedOnWatch) {
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] deferred write skipped watch-captured session $sessionId',
        );
      }
      return;
    }
    if (await _shouldAwaitWatchCapture(session) ||
        await _shouldDeferWriteback(session)) {
      _scheduleDeferredWriteback(session.id);
      return;
    }

    final record = _mapper.fromSession(session);
    await _queue.enqueue(record);
  }

  Future<void> handleWorkoutCompleted(WorkoutSession session) async {
    if (!state.value.enabled) return;
    if (session.capturedOnWatch) {
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] skip watch-captured session ${session.id}',
        );
      }
      return;
    }
    if (await _shouldAwaitWatchCapture(session) ||
        await _shouldDeferWriteback(session)) {
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] deferring writeback for ${session.id} to allow watch capture',
        );
      }
      _scheduleDeferredWriteback(session.id);
      return;
    }
    final record = _mapper.fromSession(session);
    await _queue.enqueue(record);
  }

  Future<void> handleWorkoutUpdated(WorkoutSession session) async {
    if (!state.value.enabled) return;
    if (session.capturedOnWatch) {
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] skip watch-captured session update ${session.id}',
        );
      }
      return;
    }
    if (await _shouldAwaitWatchCapture(session) ||
        await _shouldDeferWriteback(session)) {
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWriteback] deferring update writeback for ${session.id} to allow watch capture',
        );
      }
      _scheduleDeferredWriteback(session.id);
      return;
    }
    final record = _mapper.fromSession(session);
    await _queue.enqueue(record);
  }

  Future<void> handleWorkoutDeleted(String sessionId) async {
    final externalId = 'hustl:$sessionId';
    await _queue.remove(
      externalId,
      deleteRemote: state.value.enabled,
      keepUuid: null,
    );
  }

  Future<void> cancelQueuedWriteback(String sessionId) async {
    _watchGraceTimers.remove(sessionId)?.cancel();
    final externalId = 'hustl:$sessionId';
    // A stop event can arrive before the watch UUID is known. Defer any remote
    // delete until explicit watch UUID reconciliation to avoid deleting the
    // watch-authored workout by mistake.
    await _queue.remove(externalId, deleteRemote: false, keepUuid: null);
  }

  /// Called when a workout has been successfully written to Apple Health by the
  /// watch extension, so any pending or already-written phone writeback should
  /// be cancelled/removed to avoid duplicates.
  Future<void> handleWatchCapturedWorkout({
    required String sessionId,
    required String watchWorkoutUuid,
  }) async {
    _watchGraceTimers.remove(sessionId)?.cancel();
    final externalId = 'hustl:$sessionId';
    final item = _queueItemForExternalId(externalId);

    final mappings = await _preferences.getWorkoutWritebackMappings();
    final mappedUuid = mappings[externalId];
    if (mappedUuid == null || mappedUuid.isEmpty) {
      if (item != null && item.status == WorkoutWriteStatus.written) {
        final deleted = await _service.deleteWorkoutByRecord(
          item.record,
          keepUuid: watchWorkoutUuid,
        );
        if (deleted) {
          await _queue.remove(externalId, deleteRemote: false, keepUuid: null);
        } else {
          await _queue.remove(
            externalId,
            deleteRemote: true,
            keepUuid: watchWorkoutUuid,
          );
        }
        return;
      }
      await _queue.remove(externalId, deleteRemote: false, keepUuid: null);
      return;
    }

    // If the mapping accidentally points at the watch workout UUID, do not
    // delete it. Drop the mapping so later deletes can't nuke the watch entry.
    if (mappedUuid == watchWorkoutUuid) {
      await _preferences.removeWorkoutWritebackMapping(externalId);
      await _queue.remove(externalId, deleteRemote: false, keepUuid: null);
      return;
    }

    await _queue.remove(
      externalId,
      deleteRemote: true,
      keepUuid: watchWorkoutUuid,
    );
  }

  Future<bool> _shouldAwaitWatchCapture(WorkoutSession session) async {
    if (!session.watchCapturePending) return false;
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (!await _isWatchCompanionEnabled()) return false;
    return true;
  }

  WorkoutWriteQueueItem? _queueItemForExternalId(String externalId) {
    for (final item in _queue.items) {
      if (item.externalId == externalId) {
        return item;
      }
    }
    return null;
  }

  Future<bool> _loadEnabled(WorkoutWritePlatform platform) async {
    switch (platform) {
      case WorkoutWritePlatform.iosHealthKit:
        return await _preferences.getWorkoutWritebackEnabledIos();
      case WorkoutWritePlatform.androidHealthConnect:
        return await _preferences.getWorkoutWritebackEnabledAndroid();
      case WorkoutWritePlatform.unsupported:
        return false;
    }
  }

  Future<void> _storeEnabled(
    WorkoutWritePlatform platform,
    bool enabled,
  ) async {
    switch (platform) {
      case WorkoutWritePlatform.iosHealthKit:
        await _preferences.setWorkoutWritebackEnabledIos(enabled);
        break;
      case WorkoutWritePlatform.androidHealthConnect:
        await _preferences.setWorkoutWritebackEnabledAndroid(enabled);
        break;
      case WorkoutWritePlatform.unsupported:
        break;
    }
  }

  /// Runs a fire-and-forget coordinator task with its own guard so a stray
  /// async failure in this best-effort background work (queue processing,
  /// capability refresh, deferred writeback) is logged and swallowed here —
  /// instead of escaping to the root zone where a blanket
  /// PlatformDispatcher.onError would have to swallow ALL errors and mask real
  /// release crashes.
  void _dispatchGuarded(Future<void> Function() run, String label) {
    unawaited(
      run().catchError((Object error, StackTrace stack) {
        if (kDebugMode) {
          debugPrint('[WorkoutWriteback] $label failed (ignored): $error');
        }
      }),
    );
  }

  @visibleForTesting
  WorkoutRecord mapSession(WorkoutSession session) =>
      _mapper.fromSession(session);
}
