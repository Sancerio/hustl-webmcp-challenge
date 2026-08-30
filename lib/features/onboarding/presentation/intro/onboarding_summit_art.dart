import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Summit onboarding art: layered contour terrain with one blue route
/// climbing across the intro slides. The app icon itself is the climber —
/// a mini logo tile that advances camp to camp as the user swipes, and
/// plants a flag on the welcome screen.
///
/// All geometry is deterministic (no randomness) so goldens are stable and
/// reduce-motion renders a meaningful still frame.
class SummitTerrainPainter extends CustomPainter {
  const SummitTerrainPainter({
    required this.canvasColor,
    required this.contour,
    required this.contourStrong,
    required this.route,
    required this.ink,
    required this.flag,
    required this.sun,
    this.progress = 0.2,
    this.time = 0,
    this.moving = false,
    this.spark = 0,
    this.parallax = 0,
    this.ambientLife = false,
    this.summit = false,
    this.echoStrength = 1,
    this.sunFraction = const Offset(.62, .175),
  });

  /// Ridge fill — matches the screen background so nearer ridges occlude
  /// farther line work.
  final Color canvasColor;

  /// Faint echo-contour color and the crest-line color.
  final Color contour;
  final Color contourStrong;

  /// The climbing route.
  final Color route;

  /// Flag pole color.
  final Color ink;

  /// Flag cloth color.
  final Color flag;

  /// The high sun: warm accent arc + soft disc, top right.
  final Color sun;

  /// Sun center as width/height fractions. The welcome shifts it left so it
  /// doesn't crowd the planted summit flag.
  final Offset sunFraction;

  /// 0..1 strength of the faint echo contours above each crest. Light theme
  /// reads them as topo layers; dark theme reads them as blur, so pass 0.
  final double echoStrength;

  /// How far along the route the climber is (0..1).
  final double progress;

  /// Monotonic ambient clock in seconds; 0 = still frame (reduce-motion and
  /// goldens). Drives the pulse rings, dash march, sun breath, and — when
  /// [ambientLife] is on — ridge breathing, clouds, and the route energy
  /// pulse.
  final double time;

  /// True while the climber is travelling between camps (Expedition): adds
  /// the walking bob and a lean into the slope.
  final bool moving;

  /// 0..1 one-shot arrival choreography: camp pop + amber spark burst.
  final double spark;

  /// Horizontal parallax offset in px, applied depth-weighted to the ridges
  /// during a camp-to-camp move.
  final double parallax;

  /// Living Mountain layer (welcome screen): breathing ridges, drifting
  /// clouds, and a periodic energy pulse along the climbed route.
  final bool ambientLife;

  /// Whether the summit flag is planted (welcome screen).
  final bool summit;

  /// Route fractions where the three camps sit; slides land the climber on
  /// these stops (see [routeStopForPage]).
  static const camps = [0.42, 0.68, 0.92];

  /// Maps a live page position (0..3) to route progress, easing between the
  /// base-camp start and the camp stops.
  static double routeStopForPage(double page) {
    const stops = [0.16, 0.42, 0.68, 0.92];
    final lo = page.floor().clamp(0, stops.length - 1);
    final hi = page.ceil().clamp(0, stops.length - 1);
    final t = page - page.floorToDouble();
    return stops[lo] + (stops[hi] - stops[lo]) * t;
  }

  /// Route control points for a given canvas size (see [paint]).
  static List<Offset> _routePts(Size size) {
    final w = size.width, h = size.height;
    return [
      Offset(w * .04, h * .965),
      Offset(w * .30, h * .89),
      Offset(w * .16, h * .80),
      Offset(w * .46, h * .70), // ~camp 1
      Offset(w * .34, h * .585),
      Offset(w * .62, h * .47), // ~camp 2
      Offset(w * .55, h * .36),
      Offset(w * .76, h * .245), // ~camp 3 / summit
    ];
  }

  static Path _routePathFor(Size size) {
    final pts = _routePts(size);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      path.quadraticBezierTo(
        (a.dx + b.dx) / 2,
        (a.dy + b.dy) / 2 - 8,
        b.dx,
        b.dy,
      );
    }
    return path;
  }

  /// Where the climber (the real [LogoMark] widget, overlaid by the screen)
  /// sits for a given canvas size and route progress.
  static Offset markerPositionFor(Size size, double progress) {
    final metric = _routePathFor(size).computeMetrics().first;
    return metric
        .getTangentForOffset(metric.length * progress.clamp(0.0, 1.0))!
        .position;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // ---- Terrain: four ridgelines, back to front, each with echo contours.
    const ridges = [
      (base: .30, amp: .10, phase: 0.4, tint: .30),
      (base: .46, amp: .13, phase: 2.1, tint: .48),
      (base: .62, amp: .16, phase: 4.6, tint: .70),
      (base: .80, amp: .18, phase: 1.2, tint: 1.0),
    ];

    // Crest is stroked as an OPEN polyline; only the fill uses the closed
    // shape. Stroking the closed path would paint its bottom-edge closure as
    // a hard horizontal rule across the canvas boundary.
    Path crestPath(double base, double amp, double phase) {
      final p = Path();
      for (double x = -8; x <= w + 8; x += 6) {
        final t = x / w * math.pi * 2;
        final y =
            h * base +
            math.sin(t * 1.15 + phase) * h * amp * .45 +
            math.sin(t * 2.9 + phase * 1.7) * h * amp * .22 +
            math.sin(t * 6.3 + phase * .6) * h * amp * .07;
        x == -8 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    var ridgeIndex = 0;
    for (final r in ridges) {
      ridgeIndex++;
      final depth = ridgeIndex / ridges.length;
      final breathe = ambientLife && time > 0
          ? math.sin(time * .35 + r.phase * 2) * 3
          : 0.0;
      canvas.save();
      canvas.translate(parallax * depth, breathe);
      final crest = crestPath(r.base, r.amp, r.phase);
      final fill = Path.from(crest)
        ..lineTo(w + 8, h + 8)
        ..lineTo(-8, h + 8)
        ..close();
      canvas.drawPath(fill, Paint()..color = canvasColor);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Color.lerp(contour, contourStrong, r.tint)!,
      );
      for (var i = 1; echoStrength > 0 && i <= 2; i++) {
        canvas.save();
        canvas.translate(0, -7.0 * i);
        canvas.drawPath(
          crest,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = contour.withValues(alpha: (.8 - i * .3) * echoStrength),
        );
        canvas.restore();
      }
      canvas.restore();
    }

    // ---- Clouds (Living Mountain only): soft two-lobe shapes drifting
    // across the upper sky. Positions derive from time, so the still frame
    // (time == 0) has no clouds and goldens stay byte-identical.
    if (ambientLife && time > 0) {
      const cloudSpecs = [
        (.20, .16, 46.0, 56.0),
        (.72, .30, 34.0, 80.0),
        (.45, .08, 26.0, 104.0),
      ];
      final cloud = Paint()..color = contour.withValues(alpha: .55);
      for (final (cx, cy, sizeR, period) in cloudSpecs) {
        final x = ((cx * w + time * (w / period)) % (w + 120)) - 60;
        final y = cy * h + math.sin(time * .3 + cx * 9) * 3;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, y),
            width: sizeR * 2,
            height: sizeR * .68,
          ),
          cloud,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x + sizeR * .5, y - sizeR * .12),
            width: sizeR * 1.2,
            height: sizeR * .44,
          ),
          cloud,
        );
      }
    }

    // ---- The route: switchbacks up the front ridges. Camp joints sit close
    // to the `camps` fractions of arc length.
    final pts = _routePts(size);
    final metric = _routePathFor(size).computeMetrics().first;
    final len = metric.length;

    canvas.drawPath(
      metric.extractPath(0, len * progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.4
        ..color = route,
    );
    const dash = 9.0, gap = 7.0;
    final march = time > 0 ? (time * 14) % (dash + gap) : 0.0;
    var d = len * progress + gap - march;
    if (d < len * progress) d += dash + gap;
    final ahead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = route.withValues(alpha: .38);
    while (d < len) {
      canvas.drawPath(metric.extractPath(d, math.min(d + dash, len)), ahead);
      d += dash + gap;
    }

    // ---- Energy pulse (Living Mountain): every five seconds a bright dot
    // travels the climbed route — the mountain acknowledging the work.
    if (ambientLife && time > 0) {
      final ph = (time % 5) / 5 * 1.4;
      if (ph <= 1) {
        final at = metric.getTangentForOffset(len * progress * ph)!.position;
        canvas.drawCircle(at, 8, Paint()..color = route.withValues(alpha: .25));
        canvas.drawCircle(
          at,
          3.4,
          Paint()..color = route.withValues(alpha: .9),
        );
      }
    }

    // ---- Camps: filled once passed, hollow ahead.
    for (final campT in camps) {
      final at = metric.getTangentForOffset(len * campT)!.position;
      final passed = campT <= progress + .015;
      final pop = spark > 0 && (campT - progress).abs() < .02
          ? 1 + math.sin(spark * math.pi) * .5
          : 1.0;
      canvas.drawCircle(
        at,
        (passed ? 6 : 5) * pop,
        Paint()..color = passed ? route : canvasColor,
      );
      canvas.drawCircle(
        at,
        (passed ? 6 : 5) * pop,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = passed ? route : contourStrong,
      );
    }

    // ---- The high sun: a thin ring and a soft disc, in open sky — below
    // the iOS Dynamic Island zone, clear of Skip, the summit flag, and the
    // welcome logo row.
    final sunAt = Offset(w * sunFraction.dx, h * sunFraction.dy);
    final darkSky = canvasColor.computeLuminance() < .2;
    final sunBreath = time > 0 ? 1 + 0.04 * math.sin(time * 1.4) : 1.0;
    if (darkSky) {
      // Alpine sun against a night sky: bright solid core, quiet halo.
      canvas.drawCircle(
        sunAt,
        30 * sunBreath,
        Paint()..color = sun.withValues(alpha: .08),
      );
      canvas.drawCircle(
        sunAt,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = sun.withValues(alpha: .50),
      );
      canvas.drawCircle(
        sunAt,
        11 * sunBreath,
        Paint()..color = sun.withValues(alpha: .95),
      );
    } else {
      canvas.drawCircle(
        sunAt,
        24 * sunBreath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = sun.withValues(alpha: .60),
      );
      canvas.drawCircle(sunAt, 14, Paint()..color = sun.withValues(alpha: .18));
    }

    // ---- Summit flag.
    if (summit) {
      final top = pts.last;
      canvas.drawLine(
        top,
        top.translate(0, -30),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = ink,
      );
      final cloth = Path()
        ..moveTo(top.dx, top.dy - 30)
        ..lineTo(top.dx + 24, top.dy - 23.5)
        ..lineTo(top.dx, top.dy - 17)
        ..close();
      canvas.drawPath(cloth, Paint()..color = flag);
    }

    // ---- The climber's ground: halo + pulse rings. The icon itself is the
    // real LogoMark widget, overlaid by the screen at markerPositionFor().
    final at = metric.getTangentForOffset(len * progress.clamp(0, 1))!.position;
    canvas.drawCircle(
      at,
      20,
      Paint()..color = canvasColor.withValues(alpha: .85),
    );
    // Pulse rings breathe outward on the ambient clock.
    if (time > 0) {
      for (var i = 0; i < 2; i++) {
        final t = ((time / 3.8) + i * .5) % 1.0;
        canvas.drawCircle(
          at,
          14 + t * 16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = route.withValues(alpha: (1 - t) * .30),
        );
      }
    } else {
      canvas.drawCircle(
        at,
        18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = route.withValues(alpha: .22),
      );
    }

    // ---- Arrival spark (Kinetic): six amber points burst from the camp the
    // climber just reached, fading as they fly.
    if (spark > 0 && spark < 1) {
      final burst = Curves.easeOutCubic.transform(spark);
      for (var i = 0; i < 6; i++) {
        final a = i / 6 * math.pi * 2;
        final r = 10 + burst * 22;
        canvas.drawCircle(
          at + Offset(math.cos(a) * r, math.sin(a) * r),
          2.2 * (1 - spark) + .6,
          Paint()..color = flag.withValues(alpha: 1 - spark),
        );
      }
    }
  }

  /// Walking bob for the overlaid icon while moving; the screen applies it
  /// to the LogoMark so painter and widget agree.
  static Offset markerLift(double time, {required bool moving}) =>
      moving && time > 0 ? Offset(0, math.sin(time * 26) * 2.5) : Offset.zero;

  /// Lean angle (radians) for the overlaid icon while moving, from the local
  /// route slope at [progress].
  static double markerLean(Size size, double progress, {required bool moving}) {
    if (!moving) return 0;
    final metric = _routePathFor(size).computeMetrics().first;
    final ang = metric
        .getTangentForOffset(metric.length * progress.clamp(0.0, 1.0))!
        .angle;
    return math.sin(ang) * .10;
  }

  @override
  bool shouldRepaint(SummitTerrainPainter old) =>
      old.progress != progress ||
      old.time != time ||
      old.moving != moving ||
      old.spark != spark ||
      old.parallax != parallax ||
      old.summit != summit ||
      old.route != route ||
      old.canvasColor != canvasColor;
}
