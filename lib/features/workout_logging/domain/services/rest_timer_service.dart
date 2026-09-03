import 'dart:async';

import '../../../../core/services/notification_service.dart';

typedef NowProvider = DateTime Function();

enum TimerStatus { idle, running, paused, completed }

/// Service for managing rest timer during workout
class RestTimerService {
  // Default rest time in seconds
  static const int defaultRestTime = 90;

  Timer? _timer;
  int _remainingSeconds = defaultRestTime;
  TimerStatus _status = TimerStatus.idle;
  DateTime? _targetTime; // When the timer should reach 0 (while running)
  int _originalDurationSeconds =
      defaultRestTime; // The originally requested duration when starting
  final NowProvider _now;
  final NotificationService _notificationService;
  String? _currentExerciseId;
  String? _currentExerciseName;
  String? _notificationNextExerciseName;
  bool _notificationIsNextSet = false;
  bool _restCompleteNotificationScheduled = false;
  int _scheduleGeneration = 0;

  // Stream controllers
  final _timerController = StreamController<int>.broadcast();
  final _statusController = StreamController<TimerStatus>.broadcast();

  // Streams
  Stream<int> get timerStream => _timerController.stream;
  Stream<TimerStatus> get statusStream => _statusController.stream;

  // Properties
  int get remainingSeconds => _remainingSeconds;
  TimerStatus get status => _status;
  int get originalDurationSeconds => _originalDurationSeconds;
  String? get currentExerciseId => _currentExerciseId;
  String? get currentExerciseName => _currentExerciseName;

  RestTimerService({
    NowProvider? now,
    required NotificationService notificationService,
  }) : _now = now ?? DateTime.now,
       _notificationService = notificationService;

  /// Start the timer.
  /// [exerciseName] is used for on-screen UI (current exercise).
  /// [notificationNextExerciseName] is used only for the completion notification body.
  /// [updateNotificationNextExercise] tells the service the caller computed a
  /// fresh next-exercise decision: when true, [notificationNextExerciseName] is
  /// applied verbatim, so an explicit `null` (e.g. all sets complete / no next
  /// exercise) clears any previously stored name instead of leaving a stale one.
  /// When false (e.g. adjusting duration or resuming) the stored name is
  /// preserved unless an exercise-less global timer is started.
  void startTimer({
    int? durationInSeconds,
    String? exerciseId,
    String? exerciseName,
    String? notificationNextExerciseName,
    bool? notificationIsNextSet,
    bool updateNotificationNextExercise = false,
  }) {
    // Cancel any existing timer
    _timer?.cancel();
    // If a timer was already active, cancel its scheduled completion before
    // creating a new schedule for the updated duration.
    if (_status == TimerStatus.running || _status == TimerStatus.paused) {
      _notificationService.cancelRestComplete();
      _restCompleteNotificationScheduled = false;
    }

    // Set duration and status
    _originalDurationSeconds = durationInSeconds ?? defaultRestTime;
    _remainingSeconds = _originalDurationSeconds;
    _currentExerciseId = exerciseId;
    _currentExerciseName = exerciseName;
    // Update notification name if provided; clear if starting a global timer
    if (updateNotificationNextExercise) {
      // Caller computed a fresh decision; apply verbatim. An explicit null
      // ("no next exercise") clears the stored name so the completion body
      // falls back to the generic copy instead of reusing a stale name.
      _notificationNextExerciseName = notificationNextExerciseName;
      _notificationIsNextSet = notificationIsNextSet ?? false;
    } else if (notificationNextExerciseName != null) {
      _notificationNextExerciseName = notificationNextExerciseName;
      _notificationIsNextSet = notificationIsNextSet ?? false;
    } else if (exerciseName == null) {
      _notificationNextExerciseName = null;
      _notificationIsNextSet = false;
    } else if (notificationIsNextSet != null) {
      _notificationIsNextSet = notificationIsNextSet;
    }
    _targetTime = _now().add(Duration(seconds: _remainingSeconds));
    _updateStatus(TimerStatus.running);

    // Emit initial value
    _timerController.add(_remainingSeconds);

    // Schedule notification for completion
    _scheduleRestCompletion(_remainingSeconds);

    // Show/update ongoing countdown in the notification tray (Android)
    _notificationService.showRestOngoing(
      _remainingSeconds,
      exerciseName: _currentExerciseName,
    );

    unawaited(
      _notificationService.updateRestLiveActivity(
        _remainingSeconds,
        exerciseName: _currentExerciseName,
      ),
    );

    // Schedule adaptive ticks
    _scheduleNextTick();
  }

  /// Pause the timer
  void pauseTimer() {
    if (_status == TimerStatus.running) {
      _recalculateRemaining();
      _timer?.cancel();
      // Clear target while paused so remaining stays fixed until resume
      _targetTime = null;
      _notificationService.cancelRestComplete();
      _notificationService.cancelRestOngoing();
      unawaited(
        _notificationService.updateRestLiveActivity(
          _remainingSeconds,
          exerciseName: _currentExerciseName,
          isPaused: true,
        ),
      );
      _restCompleteNotificationScheduled = false;
      _scheduleGeneration++;
      _updateStatus(TimerStatus.paused);
    }
  }

  /// Resume the timer
  void resumeTimer() {
    if (_status == TimerStatus.paused) {
      // Resume from remaining, preserve originalDurationSeconds for progress context
      _targetTime = _now().add(Duration(seconds: _remainingSeconds));
      _scheduleRestCompletion(_remainingSeconds);
      _notificationService.showRestOngoing(
        _remainingSeconds,
        exerciseName: _currentExerciseName,
      );
      unawaited(
        _notificationService.updateRestLiveActivity(
          _remainingSeconds,
          exerciseName: _currentExerciseName,
        ),
      );
      _updateStatus(TimerStatus.running);
      _scheduleNextTick();
    }
  }

  /// Reset the timer
  void resetTimer({int? durationInSeconds, String? exerciseName}) {
    _timer?.cancel();
    _originalDurationSeconds = durationInSeconds ?? defaultRestTime;
    _remainingSeconds = _originalDurationSeconds;
    _currentExerciseId = null;
    _currentExerciseName = exerciseName;
    if (exerciseName == null) {
      _notificationNextExerciseName = null;
      _notificationIsNextSet = false;
    }
    _targetTime = null;
    _notificationService.cancelRestComplete();
    _notificationService.cancelRestOngoing();
    unawaited(_notificationService.endRestLiveActivity());
    _restCompleteNotificationScheduled = false;
    _scheduleGeneration++;
    _updateStatus(TimerStatus.idle);
    _timerController.add(_remainingSeconds);
  }

  /// Stop and clear the timer
  void stopTimer() {
    _timer?.cancel();
    _originalDurationSeconds = defaultRestTime;
    _remainingSeconds = defaultRestTime;
    _currentExerciseId = null;
    _currentExerciseName = null;
    _notificationNextExerciseName = null;
    _notificationIsNextSet = false;
    _targetTime = null;
    _notificationService.cancelRestComplete();
    _notificationService.cancelRestOngoing();
    unawaited(_notificationService.endRestLiveActivity());
    _restCompleteNotificationScheduled = false;
    _scheduleGeneration++;
    _updateStatus(TimerStatus.idle);
    _timerController.add(_remainingSeconds);
  }

  /// Update status and notify listeners
  void _updateStatus(TimerStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  /// Recalculate remaining time based on targetTime and emit updates.
  void _recalculateRemaining() {
    if (_status != TimerStatus.running) return;
    final target = _targetTime;
    if (target == null) return;

    final diff = target.difference(_now()).inSeconds;
    final newRemaining = diff > 0 ? diff : 0;

    if (newRemaining != _remainingSeconds) {
      _remainingSeconds = newRemaining;
      _timerController.add(_remainingSeconds);
      // Update ongoing countdown notification on Android whenever remaining changes
      _notificationService.showRestOngoing(
        _remainingSeconds,
        exerciseName: _currentExerciseName,
      );
    }

    if (newRemaining == 0) {
      _timer?.cancel();
      _updateStatus(TimerStatus.completed);
      final target = _targetTime;
      final overshoot = target == null
          ? Duration.zero
          : _now().difference(target);
      unawaited(_handleTimerCompletion(overshoot));
    } else {
      // Reschedule next tick adaptively
      _scheduleNextTick();
    }
  }

  Future<void> _handleTimerCompletion(Duration overshoot) async {
    bool skipForegroundBell = false;
    final bool hadScheduledNotification = _restCompleteNotificationScheduled;
    _restCompleteNotificationScheduled = false;
    _scheduleGeneration++;

    if (hadScheduledNotification) {
      try {
        final bool pending = await _notificationService
            .isRestCompleteNotificationPending();
        final bool catchUpFromBackground =
            overshoot > const Duration(seconds: 1);
        skipForegroundBell = catchUpFromBackground && !pending;
      } catch (_) {
        // If anything goes wrong while checking pending notifications, fall
        // back to playing the bell to ensure the alert is audible.
        skipForegroundBell = false;
      }
    }

    try {
      await _notificationService.cancelRestComplete();
    } catch (_) {
      // Ignore cancellation errors; proceed with showing completion alert.
    }

    await _notificationService.showRestComplete(
      exerciseName: _notificationNextExerciseName,
      isNextSet: _notificationIsNextSet,
      skipForegroundBell: skipForegroundBell,
    );
    // Immediately switch the ongoing notification to workout mode to avoid
    // negative chronometer countdown in the tray.
    await _notificationService.showRestOngoing(
      0,
      exerciseName: _currentExerciseName,
    );
    await _notificationService.endRestLiveActivity();
  }

  /// Public method to resync time after app resumes/backgrounding.
  /// Safe to call anytime; if running, it will immediately apply catch-up.
  void refreshNow() {
    _recalculateRemaining();
    // Ensure UI updates in tests or after resume by emitting current value.
    _timerController.add(_remainingSeconds);
    if (_status == TimerStatus.running &&
        (_timer == null || !_timer!.isActive)) {
      _scheduleNextTick();
    }
  }

  void _scheduleRestCompletion(int seconds) {
    final int token = ++_scheduleGeneration;
    _restCompleteNotificationScheduled = false;
    _notificationService
        .scheduleRestComplete(
          seconds,
          exerciseName: _notificationNextExerciseName,
          isNextSet: _notificationIsNextSet,
        )
        .then((_) async {
          bool pending = false;
          try {
            pending = await _notificationService
                .isRestCompleteNotificationPending();
          } catch (_) {
            pending = false;
          }
          if (_scheduleGeneration == token) {
            _restCompleteNotificationScheduled = pending;
          }
        })
        .catchError((_) {
          if (_scheduleGeneration == token) {
            _restCompleteNotificationScheduled = false;
          }
        });
  }

  /// Schedule the next tick adaptively to reduce wakeups for long timers.
  void _scheduleNextTick() {
    _timer?.cancel();
    final interval = _nextTickInterval();
    _timer = Timer(interval, _recalculateRemaining);
  }

  Duration _nextTickInterval() {
    if (_targetTime == null) return const Duration(seconds: 1);
    final remaining = _targetTime!.difference(_now()).inSeconds;
    if (remaining <= 60) return const Duration(seconds: 1);
    if (remaining <= 5 * 60) return const Duration(seconds: 2);
    return const Duration(seconds: 5);
  }

  /// Format seconds to mm:ss
  static String formatTime(int seconds) {
    final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  /// Dispose the service
  void dispose() {
    _timer?.cancel();
    _timerController.close();
    _statusController.close();
  }
}
