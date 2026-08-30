import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/services/preferences_service.dart';
import '../../domain/writeback/workout_record.dart';
import '../../domain/writeback/workout_write_service.dart';

class WorkoutWriteQueueItem {
  const WorkoutWriteQueueItem({
    required this.externalId,
    required this.record,
    required this.payloadHash,
    required this.status,
    required this.platform,
    required this.updatedAt,
    this.pendingDelete = false,
    this.retryCount = 0,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.nextRetryAt,
    this.keepUuid,
  });

  final String externalId;
  final WorkoutRecord record;
  final String payloadHash;
  final WorkoutWriteStatus status;
  final WorkoutWritePlatform platform;
  final DateTime updatedAt;
  final bool pendingDelete;
  final int retryCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? nextRetryAt;
  final String? keepUuid;

  Map<String, dynamic> toMap() {
    return {
      'externalId': externalId,
      'payload': record.toCanonicalMap(),
      'payloadHash': payloadHash,
      'status': status.name,
      'platform': platform.name,
      'updatedAt': updatedAt.toIso8601String(),
      'pendingDelete': pendingDelete,
      'retryCount': retryCount,
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
      'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      'lastSuccessAt': lastSuccessAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
      'keepUuid': keepUuid,
    };
  }

  WorkoutWriteQueueItem copyWith({
    WorkoutRecord? record,
    String? payloadHash,
    WorkoutWriteStatus? status,
    int? retryCount,
    String? lastErrorCode,
    String? lastErrorMessage,
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
    DateTime? updatedAt,
    DateTime? nextRetryAt,
    WorkoutWritePlatform? platform,
    bool? pendingDelete,
    String? keepUuid,
    bool clearKeepUuid = false,
  }) {
    return WorkoutWriteQueueItem(
      externalId: externalId,
      record: record ?? this.record,
      payloadHash: payloadHash ?? this.payloadHash,
      status: status ?? this.status,
      platform: platform ?? this.platform,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingDelete: pendingDelete ?? this.pendingDelete,
      retryCount: retryCount ?? this.retryCount,
      lastErrorCode: lastErrorCode,
      lastErrorMessage: lastErrorMessage,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      keepUuid: clearKeepUuid ? null : (keepUuid ?? this.keepUuid),
    );
  }

  static WorkoutWriteQueueItem fromMap(Map<String, dynamic> map) {
    return WorkoutWriteQueueItem(
      externalId: map['externalId'] as String,
      record: _recordFromMap(Map<String, dynamic>.from(map['payload'] as Map)),
      payloadHash: map['payloadHash'] as String,
      status: WorkoutWriteStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => WorkoutWriteStatus.pending,
      ),
      platform: WorkoutWritePlatform.values.firstWhere(
        (p) => p.name == map['platform'],
        orElse: () => WorkoutWritePlatform.unsupported,
      ),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      pendingDelete: map['pendingDelete'] as bool? ?? false,
      retryCount: map['retryCount'] as int? ?? 0,
      lastErrorCode: map['lastErrorCode'] as String?,
      lastErrorMessage: map['lastErrorMessage'] as String?,
      lastAttemptAt: map['lastAttemptAt'] != null
          ? DateTime.parse(map['lastAttemptAt'] as String)
          : null,
      lastSuccessAt: map['lastSuccessAt'] != null
          ? DateTime.parse(map['lastSuccessAt'] as String)
          : null,
      nextRetryAt: map['nextRetryAt'] != null
          ? DateTime.parse(map['nextRetryAt'] as String)
          : null,
      keepUuid: map['keepUuid'] as String?,
    );
  }

  static WorkoutRecord _recordFromMap(Map<String, dynamic> map) {
    return WorkoutRecord(
      sessionId: map['sessionId'] as String,
      activityType: WorkoutActivityType.values.firstWhere(
        (t) => t.name == map['activityType'],
      ),
      startedAt: DateTime.parse(map['startedAt'] as String),
      endedAt: DateTime.parse(map['endedAt'] as String),
      duration: map['duration'] as int,
      energyKilocalories: map['energyKilocalories'] == null
          ? null
          : (map['energyKilocalories'] as num).toDouble(),
      distanceMeters: map['distanceMeters'] == null
          ? null
          : (map['distanceMeters'] as num).toDouble(),
      averageHeartRateBpm: map['averageHeartRateBpm'] == null
          ? null
          : (map['averageHeartRateBpm'] as num).toDouble(),
      maxHeartRateBpm: map['maxHeartRateBpm'] == null
          ? null
          : (map['maxHeartRateBpm'] as num).toDouble(),
      steps: map['steps'] as int?,
      metadata: map['metadata'] == null
          ? null
          : Map<String, String>.from(map['metadata'] as Map),
      // writes only; deletions keep record around for potential replays
    );
  }
}

/// Manages persistence, retries, and orchestration of workout writeback items.
class WorkoutWriteQueue {
  WorkoutWriteQueue(
    this._preferences,
    this._service, {
    DateTime Function()? clock,
    Random? random,
  }) : _now = clock ?? DateTime.now,
       _rand = random ?? Random();

  static const _storageKey = 'workout_write_queue_v1';

  final PreferencesService _preferences;
  final WorkoutWriteService _service;
  final DateTime Function() _now;
  final Random _rand;
  final Map<String, WorkoutWriteQueueItem> _items = {};
  final StreamController<WorkoutWriteEvent> _events =
      StreamController<WorkoutWriteEvent>.broadcast();

  bool _loaded = false;
  bool _processing = false;
  WorkoutWriteCapability? _capability;

  Stream<WorkoutWriteEvent> get events => _events.stream;

  List<WorkoutWriteQueueItem> get items =>
      _items.values.toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

  Future<void> hydrate({bool process = true}) async {
    await _ensureLoaded();
    if (process) {
      unawaited(_processQueue());
    }
  }

  Future<void> process() async {
    await _processQueue();
  }

  Future<void> resetFailures() async {
    await _ensureLoaded();
    var changed = false;
    final now = _now();
    _items.updateAll((key, value) {
      if (value.status == WorkoutWriteStatus.failed &&
          value.nextRetryAt == null) {
        changed = true;
        return value.copyWith(
          status: WorkoutWriteStatus.pending,
          lastErrorCode: null,
          lastErrorMessage: null,
          nextRetryAt: null,
          updatedAt: now,
        );
      }
      return value;
    });
    if (changed) {
      await _persist();
    }
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _items.clear();
    await _persist();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _loadFromStorage();
    _loaded = true;
  }

  Future<void> refreshCapability() async {
    _capability = await _service.getCapabilities();
    _events.add(
      const WorkoutWriteEvent(WorkoutWriteEventType.permissionsUpdated, ''),
    );
  }

  Future<void> enqueue(WorkoutRecord record) async {
    await _ensureLoaded();
    _capability ??= await _service.getCapabilities();

    final key = record.externalId;
    final payloadHash = record.payloadHash();
    final existing = _items[key];

    if (existing != null &&
        existing.payloadHash == payloadHash &&
        existing.status == WorkoutWriteStatus.written) {
      return;
    }

    final item =
        (existing ??
                WorkoutWriteQueueItem(
                  externalId: key,
                  record: record,
                  payloadHash: payloadHash,
                  status: WorkoutWriteStatus.pending,
                  platform:
                      _capability?.platform ?? WorkoutWritePlatform.unsupported,
                  updatedAt: _now(),
                ))
            .copyWith(
              record: record,
              payloadHash: payloadHash,
              status: WorkoutWriteStatus.pending,
              pendingDelete: false,
              retryCount: existing?.retryCount,
              lastErrorCode: null,
              lastErrorMessage: null,
              lastAttemptAt: null,
              nextRetryAt: null,
              platform: _capability?.platform,
              clearKeepUuid: true,
              updatedAt: _now(),
            );

    _items[key] = item;
    await _persist();
    _events.add(WorkoutWriteEvent(WorkoutWriteEventType.queued, key));
    unawaited(_processQueue());
  }

  Future<void> remove(
    String externalId, {
    bool deleteRemote = true,
    String? keepUuid,
  }) async {
    await _ensureLoaded();
    final existing = _items[externalId];
    if (existing == null) {
      if (deleteRemote) {
        if (keepUuid != null && keepUuid.isNotEmpty) {
          final mappings = await _preferences.getWorkoutWritebackMappings();
          final mappedUuid = mappings[externalId];
          if (mappedUuid == keepUuid) {
            await _preferences.removeWorkoutWritebackMapping(externalId);
            return;
          }
        }
        try {
          await _service.deleteWorkout(externalId);
        } catch (error) {
          debugPrint('WorkoutWriteQueue.deleteWorkout failed: $error');
        }
      }
      return;
    }

    if (!deleteRemote) {
      _items.remove(externalId);
      await _persist();
      _events.add(
        WorkoutWriteEvent(WorkoutWriteEventType.succeeded, externalId),
      );
      return;
    }

    final pending = existing.copyWith(
      pendingDelete: true,
      keepUuid: keepUuid,
      clearKeepUuid: keepUuid == null,
      status: WorkoutWriteStatus.pending,
      retryCount: existing.retryCount,
      lastErrorCode: null,
      lastErrorMessage: null,
      nextRetryAt: null,
      updatedAt: _now(),
    );
    _items[externalId] = pending;
    await _persist();
    unawaited(_processQueue());
  }

  Future<void> markDirty(String externalId) async {
    await _ensureLoaded();
    final existing = _items[externalId];
    if (existing == null) return;
    final updated = existing.copyWith(
      status: WorkoutWriteStatus.pending,
      updatedAt: _now(),
      nextRetryAt: null,
      lastErrorCode: null,
      lastErrorMessage: null,
      pendingDelete: false,
      clearKeepUuid: true,
    );
    _items[externalId] = updated;
    await _persist();
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    await _ensureLoaded();
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final next = _nextRunnableItem();
        if (next == null) break;
        await _runItem(next);
      }
    } finally {
      _processing = false;
    }
  }

  WorkoutWriteQueueItem? _nextRunnableItem() {
    if (_capability == null || !_capability!.supported) {
      return null;
    }
    final now = _now();
    final ready = _items.values.where((item) {
      if (item.status == WorkoutWriteStatus.written) return false;
      if (item.status == WorkoutWriteStatus.writing) return false;
      if (item.status == WorkoutWriteStatus.failed) {
        if (item.nextRetryAt == null) {
          return false;
        }
        if (item.nextRetryAt!.isAfter(now)) {
          return false;
        }
      }
      return true;
    }).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return ready.isEmpty ? null : ready.first;
  }

  Future<void> _runItem(WorkoutWriteQueueItem item) async {
    final key = item.externalId;
    final attempt = item.copyWith(
      status: WorkoutWriteStatus.writing,
      retryCount: item.retryCount + 1,
      lastAttemptAt: _now(),
      updatedAt: _now(),
    );
    _items[key] = attempt;
    await _persist();
    _events.add(WorkoutWriteEvent(WorkoutWriteEventType.started, key));

    if (attempt.pendingDelete) {
      bool success = false;
      try {
        success = await _service.deleteWorkoutByRecord(
          attempt.record,
          keepUuid: attempt.keepUuid,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'WorkoutWriteQueue remote delete failed: $error\n$stackTrace',
        );
      }

      final current = _items[key];
      if (!identical(current, attempt)) {
        return;
      }

      if (success) {
        _items.remove(key);
        await _persist();
        _events.add(WorkoutWriteEvent(WorkoutWriteEventType.succeeded, key));
        return;
      }

      final delay = _computeBackoff(attempt.retryCount, true);
      final failedDelete = attempt.copyWith(
        status: WorkoutWriteStatus.failed,
        lastErrorCode: 'delete_failed',
        lastErrorMessage: 'Failed to delete workout',
        nextRetryAt: delay == null ? null : _now().add(delay),
        updatedAt: _now(),
      );
      _items[key] = failedDelete;
      await _persist();
      _events.add(
        WorkoutWriteEvent(
          WorkoutWriteEventType.failed,
          key,
          errorCode: 'delete_failed',
          message: 'Failed to delete workout',
        ),
      );
      return;
    }

    WorkoutWriteResult result;
    try {
      result = await _service.upsertWorkout(item.record);
    } catch (error, stackTrace) {
      debugPrint('WorkoutWriteQueue upsert failed: $error\n$stackTrace');
      result = const WorkoutWriteResult.failure(
        errorCode: 'exception',
        retryable: true,
      );
    }

    final current = _items[key];
    if (!identical(current, attempt)) {
      return;
    }
    if (result.success) {
      final success = attempt.copyWith(
        status: WorkoutWriteStatus.written,
        lastSuccessAt: _now(),
        lastErrorCode: null,
        lastErrorMessage: null,
        clearKeepUuid: true,
        updatedAt: _now(),
      );
      _items[key] = success;
      await _persist();
      _events.add(WorkoutWriteEvent(WorkoutWriteEventType.succeeded, key));
      return;
    }

    final delay = _computeBackoff(attempt.retryCount, result.retryable);
    final failed = attempt.copyWith(
      status: WorkoutWriteStatus.failed,
      lastErrorCode: result.errorCode,
      lastErrorMessage: result.message,
      nextRetryAt: delay == null ? null : _now().add(delay),
      updatedAt: _now(),
    );
    _items[key] = failed;
    await _persist();
    _events.add(
      WorkoutWriteEvent(
        WorkoutWriteEventType.failed,
        key,
        errorCode: result.errorCode,
        message: result.message,
      ),
    );
  }

  Duration? _computeBackoff(int attempts, bool retryable) {
    if (!retryable) return null;
    final cappedAttempts = attempts.clamp(1, 8);
    final baseSeconds = pow(2, cappedAttempts + 1).toInt();
    final jitter = _rand.nextInt(15);
    final seconds = (baseSeconds + jitter).clamp(10, 1800);
    return Duration(seconds: seconds);
  }

  Future<void> _loadFromStorage() async {
    final raw = await _preferences.getRawString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = json.decode(raw) as List;
      for (final entry in decoded) {
        final map = Map<String, dynamic>.from(entry as Map);
        final item = WorkoutWriteQueueItem.fromMap(map);
        _items[item.externalId] = item;
      }
    } catch (error, stackTrace) {
      debugPrint('WorkoutWriteQueue load failed: $error\n$stackTrace');
      await _preferences.setRawString(_storageKey, null);
      _items.clear();
    }
  }

  Future<void> _persist() async {
    final data = [for (final item in _items.values) item.toMap()];
    await _preferences.setRawString(_storageKey, json.encode(data));
  }
}
