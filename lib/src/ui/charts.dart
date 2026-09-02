import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

class RingMetric extends StatelessWidget {
  const RingMetric({
    super.key,
    required this.value,
    required this.center,
    required this.caption,
    this.color = hustleEmerald,
    this.size = 104,
  });

  final double value;
  final String center;
  final String caption;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: hustleSurfaceHigh,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              center,
              style: const TextStyle(
                color: hustleText,
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: const TextStyle(color: hustleText, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );
}

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = hustleBlue,
    this.height = 72,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(maxValue - minValue, 1).toDouble();
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y =
          size.height -
          ((values[index] - minValue) / range * size.height * .72) -
          8;
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class WeekBars extends StatelessWidget {
  const WeekBars({super.key});

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var index = 0; index < labels.length; index++)
          Column(
            children: [
              Container(
                width: 10,
                height: 42,
                decoration: BoxDecoration(
                  color: index < 4 ? hustleBlue : hustleSurfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(labels[index], style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
