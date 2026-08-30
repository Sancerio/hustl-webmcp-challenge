import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// A circular progress ring with rounded caps.
///
/// Wave F (MacroFactor pivot): the default fill is a quiet solid colour (the
/// single interactive accent). Pass [gradient] to opt into the signature sweep —
/// reserved for the startup splash ring. Either way the arc draws on
/// (0 -> target) over 600ms easeOutCubic the first time it appears and whenever
/// [progress] changes, honours `MediaQuery.disableAnimations` (snaps instantly),
/// and isolates its painter in a [RepaintBoundary].
class AppProgressRing extends StatelessWidget {
  const AppProgressRing({
    super.key,
    required this.progress,
    this.size = 120,
    this.strokeWidth = 12,
    this.gradient,
    this.color,
    this.trackColor,
    this.child,
    this.semanticsLabel,
  });

  /// Target completion in the 0..1 range (clamped).
  final double progress;
  final double size;
  final double strokeWidth;

  /// Optional sweep gradient for the filled arc. When set it takes precedence
  /// over [color] — reserved for the signature splash ring. When null the ring
  /// paints a quiet solid [color].
  final Gradient? gradient;

  /// Solid fill colour for the filled arc when no [gradient] is given. Defaults
  /// to the single interactive accent.
  final Color? color;

  /// Colour of the unfilled track. Defaults to a faint outline.
  final Color? trackColor;

  /// Optional centre content (e.g. an [AnimatedMetricText]).
  final Widget? child;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final track =
        trackColor ??
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4);
    final solidColor = color ?? Theme.of(context).colorScheme.primary;

    final ring = RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: clamped),
        duration: disableAnimations ? Duration.zero : AppMotion.emphasized,
        curve: AppMotion.emphasizedCurve,
        builder: (context, value, _) {
          return CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              progress: value,
              strokeWidth: strokeWidth,
              gradient: gradient,
              color: solidColor,
              trackColor: track,
            ),
            child: child == null ? null : Center(child: child),
          );
        },
      ),
    );

    // When no label is provided the ring is decorative (e.g. a background
    // accent) and should be invisible to assistive technology.  When a label
    // IS provided, announce it as the element label and expose the numeric
    // percent as the value so TalkBack/VoiceOver reads e.g. "Calories, 72%".
    if (semanticsLabel == null) {
      return ExcludeSemantics(
        child: SizedBox.square(dimension: size, child: ring),
      );
    }

    return Semantics(
      label: semanticsLabel,
      value: '${(clamped * 100).round()}%',
      child: SizedBox.square(dimension: size, child: ring),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.gradient,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;

  /// When set, the arc is painted with this sweep gradient; otherwise a solid
  /// [color] stroke is used.
  final Gradient? gradient;
  final Color color;
  final Color trackColor;

  static const double _start = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, _start, 2 * math.pi, false, trackPaint);

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (gradient != null) {
      fillPaint.shader = gradient!.createShader(arcRect);
    } else {
      fillPaint.color = color;
    }
    canvas.drawArc(arcRect, _start, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.gradient != gradient ||
      old.color != color ||
      old.trackColor != trackColor;
}
