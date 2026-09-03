import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_radius.dart';
import '../../domain/services/rest_timer_service.dart';

class RestTimerChip extends StatefulWidget {
  final RestTimerService restTimerService;
  final VoidCallback onExpand;
  final VoidCallback? onTimerComplete;
  final int? totalSeconds;

  const RestTimerChip({
    super.key,
    required this.restTimerService,
    required this.onExpand,
    this.onTimerComplete,
    this.totalSeconds,
  });

  @override
  State<RestTimerChip> createState() => _RestTimerChipState();
}

class _RestTimerChipState extends State<RestTimerChip>
    with TickerProviderStateMixin {
  late int _remainingSeconds;
  late TimerStatus _status;
  late StreamSubscription<int> _timerSub;
  late StreamSubscription<TimerStatus> _statusSub;

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  late final AnimationController _popController;
  late final Animation<double> _popScale;

  // Whether reduced-motion is active; resolved from MediaQuery once dependencies
  // are available (initState has no usable context for this).
  bool _reduceMotion = false;
  bool _dependenciesResolved = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.restTimerService.remainingSeconds;
    _status = widget.restTimerService.status;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulseController);

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
    ]).animate(_popController);

    _timerSub = widget.restTimerService.timerStream.listen((seconds) {
      if (mounted) setState(() => _remainingSeconds = seconds);
    });
    _statusSub = widget.restTimerService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _status = status);
        if (status == TimerStatus.completed) {
          _pulseController.stop();
          if (_reduceMotion) {
            widget.onTimerComplete?.call();
          } else {
            _popController.forward(from: 0).whenComplete(() {
              widget.onTimerComplete?.call();
            });
          }
        } else if (status == TimerStatus.idle) {
          widget.onTimerComplete?.call();
        }
        _syncPulse();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_dependenciesResolved) {
      _dependenciesResolved = true;
      _syncPulse();
    }
  }

  // Run the pulse only while the timer is actively counting down and motion is
  // allowed; stop it otherwise so the per-second blur is never re-pulsed.
  void _syncPulse() {
    final shouldPulse = _status == TimerStatus.running && !_reduceMotion;
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _timerSub.cancel();
    _statusSub.cancel();
    _pulseController.dispose();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formatted = RestTimerService.formatTime(_remainingSeconds);
    final isCompleted = _status == TimerStatus.completed;
    final totalSeconds =
        widget.totalSeconds ?? widget.restTimerService.originalDurationSeconds;
    final progress = (1 - (_remainingSeconds / totalSeconds)).clamp(0.0, 1.0);

    // Filled blue pill while resting; on completion the fill flips to a quiet
    // emerald tint and the ring/accent turn emerald so the earned state still
    // reads cleanly on the chip.
    final onPill = colors.onPrimary;
    final pillColor = isCompleted
        ? Color.alphaBlend(
            colors.tertiary.withValues(alpha: 0.22),
            colors.primary,
          )
        : colors.primary;
    // Ring progress tints for legibility on the blue/emerald pill.
    final ringColor = isCompleted ? colors.tertiary : onPill;

    final gradient = SweepGradient(
      colors: [
        ringColor.withValues(alpha: 0.55),
        ringColor,
        ringColor.withValues(alpha: 0.55),
      ],
      stops: const [0.0, 0.55, 1.0],
      // No rotation to avoid motion-induced dizziness
    );

    // RepaintBoundary isolates the chip so the per-second time update does not
    // invalidate surrounding layers on every tick.
    return RepaintBoundary(
      child: Material(
        color: pillColor,
        borderRadius: AppRadius.pillRadius,
        child: ScaleTransition(
          scale: _popScale,
          child: InkWell(
            borderRadius: AppRadius.pillRadius,
            onTap: widget.onExpand,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: AppRadius.pillRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: AnimatedSize(
                duration: AppMotion.slow,
                curve: AppMotion.emphasizedCurve,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _pulse,
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CustomPaint(
                          painter: _RingPainter(
                            progress: progress,
                            color: ringColor,
                            gradient: gradient,
                            trackColor: onPill.withValues(alpha: 0.30),
                            strokeWidth: 3.2,
                            rotation: 0.0,
                            showThumb: !isCompleted,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.timer_rounded,
                              size: 14,
                              color: onPill,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REST',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: onPill.withValues(alpha: 0.75),
                              fontSize: 10,
                              height: 1.0,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_status == TimerStatus.running)
                                ScaleTransition(
                                  scale: Tween<double>(begin: 0.9, end: 1.25)
                                      .chain(
                                        CurveTween(curve: Curves.easeInOut),
                                      )
                                      .animate(_pulseController),
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: onPill,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              if (_status == TimerStatus.running)
                                const SizedBox(width: 6),
                              Text(
                                formatted,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: onPill,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  height: 1.1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Gradient? gradient;
  final Color trackColor;
  final double strokeWidth;
  final double rotation; // radians, for subtle sweep motion
  final bool showThumb;

  _RingPainter({
    required this.progress,
    required this.color,
    this.gradient,
    required this.trackColor,
    this.strokeWidth = 3.0,
    this.rotation = 0.0,
    this.showThumb = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    final progPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (gradient != null) {
      progPaint.shader = gradient!.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    }

    // Draw track (start at 12 o'clock / top)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // top
      2 * math.pi,
      false,
      trackPaint,
    );

    // Draw progress from top, clockwise
    final sweep = (progress.clamp(0.0, 1.0)) * 2 * math.pi;
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        progPaint,
      );
    }

    // Draw a quiet solid thumb at the progress end (no glow bloom).
    if (showThumb && sweep > 0) {
      final endAngle = (-math.pi / 2) + sweep;
      final thumbCenter = Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      );
      final thumbPaint = Paint()..color = color;
      canvas.drawCircle(thumbCenter, strokeWidth * 0.75, thumbPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
