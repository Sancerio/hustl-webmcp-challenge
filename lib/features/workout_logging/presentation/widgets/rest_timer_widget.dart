import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/services/rest_timer_service.dart';

const int _kTimeAdjustmentSeconds = 15;

class RestTimerWidget extends StatefulWidget {
  final RestTimerService restTimerService;
  final VoidCallback onClose;

  const RestTimerWidget({
    super.key,
    required this.restTimerService,
    required this.onClose,
  });

  @override
  State<RestTimerWidget> createState() => _RestTimerWidgetState();
}

class _RestTimerWidgetState extends State<RestTimerWidget> {
  late int _remainingSeconds;
  late TimerStatus _status;
  late final StreamSubscription<int> _timerSub;
  late final StreamSubscription<TimerStatus> _statusSub;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.restTimerService.remainingSeconds;
    _status = widget.restTimerService.status;

    // Listen to timer updates
    _timerSub = widget.restTimerService.timerStream.listen((seconds) {
      if (mounted) {
        setState(() {
          _remainingSeconds = seconds;
        });
      }
    });

    // Listen to status updates
    _statusSub = widget.restTimerService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });
  }

  /// Done resting early: stop the timer and dismiss. Mirrors the "Skip" action
  /// the rest Live Activity already exposes on the lock screen.
  void _skipRest() {
    widget.restTimerService.stopTimer();
    widget.onClose();
  }

  /// Trim or extend the current rest by [delta] seconds, clamped to a sane
  /// floor so a subtract can't drive it to zero. Reuses startTimer (the same
  /// path the old "+30s" used) since the service has no in-place adjust.
  void _adjust(int delta) {
    final newTime = (_remainingSeconds + delta).clamp(5, 3600);
    widget.restTimerService.startTimer(
      durationInSeconds: newTime,
      exerciseId: widget.restTimerService.currentExerciseId,
      exerciseName: widget.restTimerService.currentExerciseName,
    );
  }

  @override
  void dispose() {
    _timerSub.cancel();
    _statusSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedTime = RestTimerService.formatTime(_remainingSeconds);
    final isRunning = _status == TimerStatus.running;
    final isPaused = _status == TimerStatus.paused;
    final isCompleted = _status == TimerStatus.completed;

    // Calculate elapsed progress for the indicator (0.0 to 1.0)
    final totalSeconds = widget.restTimerService.originalDurationSeconds
        .toDouble();
    final progress = (1 - (_remainingSeconds / totalSeconds)).clamp(0.0, 1.0);

    // Define softened colors for low-light comfort
    // Use subdued colors by default; reserve strong error for the critical
    // overdue path. Completion is a positive, earned state — emerald.
    Color timerColor;
    Color timeTextColor = theme.colorScheme.onSurface.withValues(alpha: 0.95);
    if (isCompleted) {
      timerColor = theme.colorScheme.tertiary;
      timeTextColor = theme.colorScheme.tertiary;
    } else if (_remainingSeconds < 10) {
      timerColor = theme.colorScheme.error;
      timeTextColor = theme.colorScheme.error;
    } else if (_remainingSeconds < 30) {
      timerColor = theme.colorScheme.tertiary.withValues(alpha: 0.85);
    } else {
      timerColor = theme.colorScheme.primary.withValues(alpha: 0.65);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timer display
          Row(
            children: [
              // Timer icon with circular progress
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Circular progress indicator
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.surfaceContainerHighest,
                      ),
                      backgroundColor: timerColor,
                    ),
                    // Timer icon
                    Icon(Icons.timer, color: timerColor, size: 24),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Timer display
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rest timer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.85,
                        ),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formattedTime,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: timeTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Close button
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Adjust + pause
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: () => _adjust(-_kTimeAdjustmentSeconds),
                child: const Text('-${_kTimeAdjustmentSeconds}s'),
              ),

              FilledButton.tonalIcon(
                onPressed: isRunning
                    ? widget.restTimerService.pauseTimer
                    : isPaused
                    ? widget.restTimerService.resumeTimer
                    : () => widget.restTimerService.startTimer(
                        exerciseId: widget.restTimerService.currentExerciseId,
                        exerciseName:
                            widget.restTimerService.currentExerciseName,
                      ),
                icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                label: Text(
                  isRunning
                      ? 'Pause'
                      : isPaused
                      ? 'Resume'
                      : 'Start',
                ),
              ),

              OutlinedButton(
                onPressed: () => _adjust(_kTimeAdjustmentSeconds),
                child: const Text('+${_kTimeAdjustmentSeconds}s'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Primary action: done resting early — stops the timer and dismisses.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _skipRest,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Skip rest'),
            ),
          ),
        ],
      ),
    );
  }
}

// RestTimerDialogContent has been moved to widgets/rest_timer_dialog_content.dart
