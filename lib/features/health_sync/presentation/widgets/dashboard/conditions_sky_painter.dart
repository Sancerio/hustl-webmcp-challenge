import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/daily_recovery_snapshot.dart';

/// How clear/cloudy the conditions hero's sky reads for a readiness band.
/// Ordered from clearest to cloudiest; [neutral] is the calibrating / no-band
/// state, which paints no sun emphasis at all.
enum SkyMood { clear, mostlyClear, partlyCloudy, mostlyCloudy, neutral }

SkyMood skyMoodForBand(RecoveryFlowBand? band) {
  switch (band) {
    case RecoveryFlowBand.charged:
      return SkyMood.clear;
    case RecoveryFlowBand.ready:
      return SkyMood.mostlyClear;
    case RecoveryFlowBand.steady:
      return SkyMood.partlyCloudy;
    case RecoveryFlowBand.recharge:
      return SkyMood.mostlyCloudy;
    case null:
      return SkyMood.neutral;
  }
}

/// Paints the conditions hero's sky: two soft contour ridgelines (echo-line
/// style) under a sun whose cloud coverage encodes the readiness band —
/// clear (charged) through mostly-cloudy (recharge). All colors are handed in
/// from `colorScheme`/`AppColors` tokens by the caller so the painting reads
/// correctly in both light and dark themes.
class ConditionsSkyPainter extends CustomPainter {
  const ConditionsSkyPainter({
    required this.mood,
    required this.sun,
    required this.cloudFill,
    required this.cloudOutline,
    required this.ridgeFillNear,
    required this.ridgeFillFar,
    required this.ridgeOutline,
    required this.ridgeEcho,
  });

  final SkyMood mood;
  final Color sun;
  final Color cloudFill;
  final Color cloudOutline;
  final Color ridgeFillNear;
  final Color ridgeFillFar;
  final Color ridgeOutline;
  final Color ridgeEcho;

  /// Fraction of the sun a cloud obscures, by mood: 0 = fully clear, 1 =
  /// mostly covered. [SkyMood.neutral] paints no sun at all.
  double get _cloudCoverage {
    switch (mood) {
      case SkyMood.clear:
        return 0.0;
      case SkyMood.mostlyClear:
        return 0.28;
      case SkyMood.partlyCloudy:
        return 0.55;
      case SkyMood.mostlyCloudy:
        return 0.82;
      case SkyMood.neutral:
        return 0.0;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mood != SkyMood.neutral) {
      _paintSun(canvas, size);
    }
    _paintRidges(canvas, size);
  }

  void _paintSun(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sunCenter = Offset(w * .78, h * .32);
    const sunRadius = 26.0;

    canvas.drawCircle(sunCenter, sunRadius, Paint()..color = sun);
    canvas.drawCircle(
      sunCenter,
      sunRadius + 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = sun.withValues(alpha: .3),
    );

    final coverage = _cloudCoverage;
    if (coverage <= 0) return;

    // As coverage rises the cloud both grows and drifts toward the sun's
    // centre, from a small offset wisp (mostlyClear) to a mass that hides
    // most of the sun (mostlyCloudy). The cloud sits BELOW-left of the sun
    // so the sun peeks over its top edge — reading as "sun behind cloud",
    // not a crescent moon (an edge-on side occlusion leaves a moon-like
    // sliver).
    final horizontalDrift = (1 - coverage) * 22 + 2;
    final cloudCenter =
        sunCenter + Offset(-horizontalDrift, sunRadius * (.75 - coverage * .5));
    final cloudWidth = 38 + coverage * 40;
    final cloudHeight = 16 + coverage * 18;

    var cloud = Path()
      ..addOval(
        Rect.fromCenter(
          center: cloudCenter,
          width: cloudWidth,
          height: cloudHeight,
        ),
      );
    cloud = Path.combine(
      PathOperation.union,
      cloud,
      Path()..addOval(
        Rect.fromCircle(
          center: cloudCenter + Offset(-cloudWidth * .28, -cloudHeight * .15),
          radius: cloudHeight * .58,
        ),
      ),
    );
    cloud = Path.combine(
      PathOperation.union,
      cloud,
      Path()..addOval(
        Rect.fromCircle(
          center: cloudCenter + Offset(cloudWidth * .22, -cloudHeight * .25),
          radius: cloudHeight * .62,
        ),
      ),
    );

    canvas.drawPath(cloud, Paint()..color = cloudFill);
    canvas.drawPath(
      cloud,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = cloudOutline,
    );
  }

  void _paintRidges(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ridges = <({double base, double amp, double phase, Color fill})>[
      (base: .64, amp: .10, phase: 1.1, fill: ridgeFillNear),
      (base: .84, amp: .13, phase: 3.4, fill: ridgeFillFar),
    ];

    Path ridgePath(double base, double amp, double phase) {
      final p = Path()
        ..moveTo(-8, h)
        ..lineTo(-8, h * base);
      for (double x = 0; x <= w + 8; x += 6) {
        final t = x / w * math.pi * 2;
        final y =
            h * base +
            math.sin(t * 1.2 + phase) * h * amp * .5 +
            math.sin(t * 3.0 + phase * 1.7) * h * amp * .18;
        p.lineTo(x, y);
      }
      p
        ..lineTo(w + 8, h)
        ..close();
      return p;
    }

    for (final r in ridges) {
      final path = ridgePath(r.base, r.amp, r.phase);
      canvas.drawPath(path, Paint()..color = r.fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ridgeOutline,
      );
      for (var i = 1; i <= 2; i++) {
        canvas.save();
        canvas.translate(0, -6.0 * i);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = ridgeEcho.withValues(alpha: (.22 - i * .07).clamp(0, 1)),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConditionsSkyPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.sun != sun ||
      oldDelegate.cloudFill != cloudFill ||
      oldDelegate.ridgeFillNear != ridgeFillNear ||
      oldDelegate.ridgeFillFar != ridgeFillFar;
}
