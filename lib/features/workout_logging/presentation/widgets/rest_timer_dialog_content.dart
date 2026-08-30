import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/haptics.dart';
import '../../domain/services/rest_timer_service.dart';

const int _kTimeAdjustmentSeconds = 30;

class RestTimerDialogContent extends StatefulWidget {
  final RestTimerService restTimerService;
  final VoidCallback onClose;
  const RestTimerDialogContent({
    super.key,
    required this.restTimerService,
    required this.onClose,
  });

  @override
  State<RestTimerDialogContent> createState() => _RestTimerDialogContentState();
}

class _RestTimerDialogContentState extends State<RestTimerDialogContent> {
  late int _remainingSeconds;
  late TimerStatus _status;
  late final StreamSubscription<int> _timerSub;
  late final StreamSubscription<TimerStatus> _statusSub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.restTimerService.remainingSeconds;
    _status = widget.restTimerService.status;
    _timerSub = widget.restTimerService.timerStream.listen((seconds) {
      if (mounted) setState(() => _remainingSeconds = seconds);
    });
    _statusSub = widget.restTimerService.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
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
    final isCompleted = _status == TimerStatus.completed;
    final totalSeconds = widget.restTimerService.originalDurationSeconds
        .toDouble();
    final progress = (1 - (_remainingSeconds / totalSeconds)).clamp(0.0, 1.0);
    final exerciseName = widget.restTimerService.currentExerciseName;
    // Softer color scheme for low light. Reserve error red for the critical
    // overdue path; completion is a positive, earned state — emerald.
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

    // If timer is completed, provide haptic feedback and close dialog after build
    if (isCompleted && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Haptics.maybeMediumImpact();
        if (mounted) {
          widget.onClose();
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Title row with close
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  'Rest timer',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (exerciseName != null && exerciseName.isNotEmpty) ...[
            Text(
              exerciseName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Hero countdown: the big tabular numeral lives INSIDE the progress
          // ring so the resting state reads like a premium dedicated timer
          // rather than an icon with a number underneath. The ring colour is
          // the blue brand primary by default (see [timerColor] above); the
          // 56px display tier (§12.1) is the ONE surface allowed it.
          Center(
            child: SizedBox(
              width: 196,
              height: 196,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer progress ring (static value — no implicit animation,
                  // so reduced-motion is honoured for free).
                  SizedBox(
                    width: 196,
                    height: 196,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  // Big tabular numeral centred in the ring.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted ? Icons.check_rounded : Icons.timer_rounded,
                        color: timerColor,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedTime,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: timeTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Adjust time or skip',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _remainingSeconds > _kTimeAdjustmentSeconds
                    ? () {
                        final newTime =
                            _remainingSeconds - _kTimeAdjustmentSeconds;
                        widget.restTimerService.startTimer(
                          durationInSeconds: newTime,
                          exerciseId: widget.restTimerService.currentExerciseId,
                          exerciseName:
                              widget.restTimerService.currentExerciseName,
                        );
                      }
                    : null,
                icon: const Icon(Icons.remove),
                label: const Text('-${_kTimeAdjustmentSeconds}s'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final newTime = _remainingSeconds + _kTimeAdjustmentSeconds;
                  widget.restTimerService.startTimer(
                    durationInSeconds: newTime,
                    exerciseId: widget.restTimerService.currentExerciseId,
                    exerciseName: widget.restTimerService.currentExerciseName,
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('+${_kTimeAdjustmentSeconds}s'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  widget.restTimerService.stopTimer();
                  widget.onClose();
                },
                child: const Text('Skip'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
