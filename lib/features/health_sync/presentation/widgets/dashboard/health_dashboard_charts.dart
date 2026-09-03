import 'dart:math' as math;

import 'package:flutter/material.dart';

class SparklineShell extends StatelessWidget {
  const SparklineShell({
    super.key,
    required this.accent,
    required this.values,
    this.wide = false,
  });

  final Color accent;
  final List<double> values;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: wide ? 132 : 88,
      width: double.infinity,
      child: CustomPaint(
        painter: SparklinePainter(
          accent: accent,
          values: values,
          grid: colorScheme.outlineVariant.withValues(alpha: 0.18),
          surface: colorScheme.surface,
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.accent,
    required this.values,
    required this.grid,
    required this.surface,
  });

  final Color accent;
  final List<double> values;
  final Color grid;

  /// The theme's surface colour — used for the sparkline endpoint dot centre
  /// so the point is visible against the chart background in both light and
  /// dark themes.
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final baseline = size.height - 8;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      gridPaint,
    );

    if (values.length < 2) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1e-6, maxValue - minValue);
    final path = Path();

    Offset pointAt(int index, double value) {
      final dx = (index / (values.length - 1)) * size.width;
      final normalized = (value - minValue) / range;
      final dy = size.height - 14 - normalized * (size.height - 28);
      return Offset(dx, dy);
    }

    final firstPoint = pointAt(0, values.first);
    path.moveTo(firstPoint.dx, firstPoint.dy);
    for (var i = 1; i < values.length; i++) {
      final current = pointAt(i, values[i]);
      final previous = pointAt(i - 1, values[i - 1]);
      final control = Offset((previous.dx + current.dx) / 2, previous.dy);
      final control2 = Offset((previous.dx + current.dx) / 2, current.dy);
      path.cubicTo(
        control.dx,
        control.dy,
        control2.dx,
        control2.dy,
        current.dx,
        current.dy,
      );
    }

    // §12.4: flat fill at ≤10% alpha — no gradient, no glow.
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = accent.withValues(alpha: 0.08));

    // §12.4: thin 1.5px crisp line.
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Small endpoint dot.
    final lastPoint = pointAt(values.length - 1, values.last);
    canvas.drawCircle(lastPoint, 4, Paint()..color = surface);
    canvas.drawCircle(lastPoint, 2.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.values != values ||
        oldDelegate.surface != surface;
  }
}
