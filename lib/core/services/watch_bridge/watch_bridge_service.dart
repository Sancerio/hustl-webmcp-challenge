import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../../../features/workout_logging/domain/services/rest_timer_service.dart';
import '../preferences_service.dart';
import 'watch_bridge_command.dart';
import 'watch_bridge_handler.dart';
import 'watch_bridge_health.dart';

/// Why a `workout_cancelled` teardown was published to paired watches. The same
/// wire message covers an explicit discard and a normal completion, so the watch
/// needs the reason: a discard DELETES the on-watch record (it must never
/// resurrect), a completion FINISHES it but keeps its pending sync data.
/// `wireValue` must stay in sync with the Swift `ConnectivityManager.CancelReason`
/// parser ("discarded" / "completed").
enum WatchCancelReason {
  discarded,
  completed;

  String get wireValue => switch (this) {
    WatchCancelReason.discarded => 'discarded',
    WatchCancelReason.completed => 'completed',
  };
}

class WatchBridgeService {
  WatchBridgeService({
    WatchBridgeHandler? handler,
    PreferencesService? preferences,
  }) : _preferences = preferences ?? GetIt.instance<PreferencesService>() {
    _handler =
        handler ??
        WatchBridgeHandler(
          onPublishCancelled: _sendWorkoutCancelledMessage,
          onSendCatalogResponse: _sendCatalogResponseMessage,
        );
  }

  static const MethodChannel _methodChannel = MethodChannel(
    'com.hustl.app/watch_bridge',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.hustl.app/watch_bridge/events',
  );

  late final WatchBridgeHandler _handler;
  final PreferencesService _preferences;

  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<TimerStatus>? _restStatusSub;
  Timer? _publishTimer;
  DateTime? _lastPublishAt;
  String? _lastNoSessionPayloadFingerprint;
  static final Object _fingerprintOmit = Object();
  bool _publishInFlight = false;
  bool _publishPending = false;
  bool _initialized = false;
  bool _enabled = false;
  int _lastCommandTimestampMs = 0;
  static const bool _envEnabled = bool.fromEnvironment(
    'WATCH_COMPANION_ENABLED',
    defaultValue: false,
  );
  static bool get envEnabled => _envEnabled;

  bool get isEnabled => _enabled;

  /// Commands travel over independent WatchConnectivity transports, so wall-clock
  /// milliseconds alone are not enough to order two rapid Stop/Send-again taps.
  /// Keep timestamps strictly increasing for this phone process; the Watch persists
  /// the resulting per-session watermark across its own relaunches.
  int _nextCommandTimestampMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = now > _lastCommandTimestampMs
        ? now
        : _lastCommandTimestampMs + 1;
    _lastCommandTimestampMs = next;
    return next;
  }

  StreamSubscription<dynamic> _listenToCommands() {
    return _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! String) return;
        unawaited(_handleWatchEvent(event));
      },
      onError: (e, st) {
        dev.log(
          'Watch command stream error',
          name: 'WatchBridgeService',
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  Future<void> _handleWatchEvent(String event) async {
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map) return;
      payload = Map<String, dynamic>.from(decoded);
      if (payload['type'] == 'bridge_refresh_requested') {
        // Native activation/reachability callbacks replace the old five-second
        // polling heartbeat. Refresh once when connectivity actually changes;
        // idle time between set edits now does zero bridge work on Flutter's UI
        // isolate.
        _schedulePublish(force: true);
        await _ackWatchEvent(payload);
        return;
      }
      dev.log(
        'Received watch payload keys=${payload.keys.toList()..sort()}',
        name: 'WatchBridgeService',
      );
      final healthSummary = WatchHealthSummary.tryParse(payload);
      if (healthSummary != null) {
        await _handler.handleHealthSummary(
          healthSummary,
          propagateErrors: true,
        );
        _schedulePublish(force: true);
      } else {
        final recordingState = WatchHealthRecordingState.tryParse(payload);
        final watchSession = WatchSession.tryParse(payload);
        final command = WatchCommand.tryParse(payload);
        if (recordingState != null) {
          await _handler.handleHealthRecordingState(
            recordingState,
            propagateErrors: true,
          );
          _schedulePublish(force: true);
        } else if (watchSession != null) {
          dev.log(
            'Watch session reconcile id=${watchSession.id} '
            'exercises=${watchSession.exercises.length}',
            name: 'WatchBridgeService',
          );
          await _handler.handleWatchSession(
            watchSession,
            propagateErrors: true,
          );
          _schedulePublish(force: true);
        } else if (command != null) {
          dev.log(
            'Watch command type=${command.type} sessionId=${command.sessionId ?? "nil"}',
            name: 'WatchBridgeService',
          );
          await _handler.handleCommand(command, propagateErrors: true);
          _schedulePublish(force: true);
        }
      }
    } catch (e, st) {
      dev.log(
        'Failed to handle watch payload',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
      return;
    }
    await _ackWatchEvent(payload);
  }

  Future<void> _ackWatchEvent(Map<String, dynamic>? payload) async {
    final ackId = payload?['_bridgeAckId'];
    if (ackId is! String || ackId.isEmpty) return;
    try {
      await _methodChannel.invokeMethod<void>('ackWatchEvent', {
        'ackId': ackId,
      });
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to ack watch payload',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!_isSupported) return;
    _enabled = await _isFeatureEnabled();
    if (!_enabled) {
      dev.log(
        'Watch companion disabled; skipping init',
        name: 'WatchBridgeService',
      );
      return;
    }

    await _start();
  }

  Future<void> refreshEnabled() async {
    if (!_isSupported) {
      await _stop();
      _enabled = false;
      return;
    }
    final next = await _isFeatureEnabled();
    if (next == _enabled) return;
    if (_enabled) {
      _enabled = false;
      await _stop();
    }
    _enabled = next;
    if (_enabled) {
      dev.log('Watch companion enabled', name: 'WatchBridgeService');
      await _start();
    } else {
      dev.log('Watch companion disabled', name: 'WatchBridgeService');
      await _stop();
    }
  }

  Future<void> dispose() async {
    await _stop();
    _handler.dispose();
    _enabled = false;
    _initialized = false;
  }

  Future<void> _stop() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _restStatusSub?.cancel();
    _restStatusSub = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    _publishPending = false;
    _lastNoSessionPayloadFingerprint = null;
  }

  Future<void> publishNow() async {
    if (!_isSupported || !_enabled) return;
    if (_publishInFlight) {
      _publishPending = true;
      return;
    }
    _publishInFlight = true;
    try {
      final payload = await _handler.buildStatePayload();
      if (payload == null) return;
      if (_isRedundantNoSessionPayload(payload)) return;
      await _methodChannel.invokeMethod<void>('updateState', payload);
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to publish watch state',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    } finally {
      _publishInFlight = false;
      if (_publishPending && _enabled) {
        _publishPending = false;
        _schedulePublish(force: true);
      }
    }
  }

  bool _isRedundantNoSessionPayload(Map<String, dynamic> payload) {
    final sessionId = payload['sessionId'];
    final noSession =
        sessionId == null || (sessionId is String && sessionId.isEmpty);
    if (!noSession) {
      _lastNoSessionPayloadFingerprint = null;
      return false;
    }

    final fingerprintPayload = _normalizedNoSessionFingerprintValue(payload);
    final fingerprint = jsonEncode(fingerprintPayload);
    if (fingerprint == _lastNoSessionPayloadFingerprint) {
      return true;
    }
    _lastNoSessionPayloadFingerprint = fingerprint;
    return false;
  }

  Object? _normalizedNoSessionFingerprintValue(Object? value, {String? key}) {
    if (key == 'ts' || key == 'elapsedSec' || key == 'remainingSec') {
      return _fingerprintOmit;
    }

    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      final normalized = <String, Object?>{};
      for (final entry in entries) {
        final child = _normalizedNoSessionFingerprintValue(
          entry.value,
          key: entry.key,
        );
        if (!identical(child, _fingerprintOmit)) {
          normalized[entry.key] = child;
        }
      }
      return normalized;
    }

    if (value is Iterable) {
      return value
          .map((child) => _normalizedNoSessionFingerprintValue(child))
          .where((child) => !identical(child, _fingerprintOmit))
          .toList();
    }

    return value;
  }

  Future<void> requestStopRecording({required String sessionId}) async {
    if (!_isSupported || !_enabled) return;
    final payload = <String, dynamic>{
      'v': 1,
      'ts': _nextCommandTimestampMs(),
      'id': const Uuid().v4(),
      'type': 'health_recording_stop_request',
      'sessionId': sessionId,
    };
    try {
      await _methodChannel.invokeMethod<void>('sendCommand', payload);
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to send stop recording command',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Sends a distinct start/retry intent instead of relying on another copy of
  /// the (potentially unchanged) application-context snapshot. Every call gets
  /// a new command id so an explicit "Send again" tap always reaches the live
  /// Watch command channel and is never swallowed by state deduplication.
  Future<void> requestStartRecording({required String sessionId}) async {
    if (!_isSupported || !_enabled) return;
    final payload = <String, dynamic>{
      'v': 1,
      'ts': _nextCommandTimestampMs(),
      'id': const Uuid().v4(),
      'type': 'health_recording_start_request',
      'sessionId': sessionId,
    };
    try {
      await _methodChannel.invokeMethod<void>('sendCommand', payload);
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to send start recording command',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Phone-side terminal cancel: tombstone the session locally (so a queued watch
  /// snapshot can't resurrect it) and tell paired watches to tear down their local
  /// record. Safe to call regardless of reachability — the native bridge mirrors
  /// the dual path (sendMessage when reachable, else transferUserInfo).
  void cancelWorkout({
    required String sessionId,
    String? hkWorkoutUuid,
    WatchCancelReason reason = WatchCancelReason.discarded,
  }) {
    _handler.markSessionCancelled(sessionId, hkWorkoutUuid: hkWorkoutUuid);
    if (!_isSupported || !_enabled) return;
    _sendWorkoutCancelledMessage(
      sessionId: sessionId,
      hkWorkoutUuid: hkWorkoutUuid,
      reason: reason,
    );
  }

  void _sendWorkoutCancelledMessage({
    required String sessionId,
    String? hkWorkoutUuid,
    WatchCancelReason reason = WatchCancelReason.discarded,
  }) {
    if (!_isSupported || !_enabled) return;
    final payload = <String, dynamic>{
      'v': 1,
      'ts': _nextCommandTimestampMs(),
      'id': const Uuid().v4(),
      'type': 'workout_cancelled',
      'sessionId': sessionId,
      // Lets the watch distinguish an explicit discard (DELETE the local record)
      // from a normal completion teardown (FINISH but keep pending sync data).
      // Protocol string must stay in sync with Swift CancelReason.
      'reason': reason.wireValue,
      if (hkWorkoutUuid != null && hkWorkoutUuid.isNotEmpty)
        'hkWorkoutUuid': hkWorkoutUuid,
    };
    try {
      // ignore: discarded_futures
      _methodChannel.invokeMethod<void>('sendCommand', payload);
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to send workout_cancelled command',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Ship an `exercise_catalog` response (built by the handler) to paired watches.
  /// Mirrors the dual send path used for commands (sendMessage when reachable,
  /// else transferUserInfo via the native bridge).
  void _sendCatalogResponseMessage(Map<String, dynamic> payload) {
    if (!_isSupported || !_enabled) return;
    try {
      // ignore: discarded_futures
      _methodChannel.invokeMethod<void>('sendCommand', payload);
    } on MissingPluginException {
      // No-op when the native bridge isn't available (e.g., tests).
    } catch (e, st) {
      dev.log(
        'Failed to send exercise_catalog response',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  void schedulePublish() => _schedulePublish();

  void _schedulePublish({bool force = false}) {
    if (!_isSupported || !_enabled) return;
    if (_publishInFlight) {
      _publishPending = true;
      return;
    }

    final now = DateTime.now();
    final last = _lastPublishAt;
    final shouldDelay =
        !force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 700);

    _publishTimer?.cancel();
    if (shouldDelay) {
      _publishTimer = Timer(const Duration(milliseconds: 750), () {
        _publishTimer = null;
        _lastPublishAt = DateTime.now();
        // ignore: discarded_futures
        publishNow();
      });
      return;
    }

    _lastPublishAt = now;
    // ignore: discarded_futures
    publishNow();
  }

  bool get _isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> _isFeatureEnabled() async {
    try {
      final baseEnabled = _envEnabled
          ? true
          : await _preferences.getWatchCompanionEnabled();
      final override = await _preferences.getWatchCompanionDebugOverride();
      return override ?? baseEnabled;
    } catch (_) {
      return _envEnabled;
    }
  }

  Future<void> _start() async {
    if (_eventsSub != null || _restStatusSub != null) {
      return;
    }
    try {
      _eventsSub = _listenToCommands();
      _restStatusSub = GetIt.instance<RestTimerService>().statusStream.listen(
        (_) => _schedulePublish(),
      );
      _schedulePublish(force: true);
    } catch (e, st) {
      await _stop();
      _enabled = false;
      dev.log(
        'Failed to start watch bridge',
        name: 'WatchBridgeService',
        error: e,
        stackTrace: st,
      );
    }
  }
}
