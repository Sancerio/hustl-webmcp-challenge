import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import 'kg_format.dart';

/// The INSIGHTS volume mini-chart: weekly volume as a single 2px blue line,
/// edge-to-edge and borderless, with a flat ≤10% fill under the line and a
/// dot only on the latest point. No card frame, no gridlines.
class HomeVolumeTrendChart extends StatelessWidget {
  const HomeVolumeTrendChart({super.key, required this.weeklyVolumes});

  /// Weekly volume totals (kg), oldest first, ending with the current week.
  final List<double> weeklyVolumes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (weeklyVolumes.length < 2) {
      // First-run / not-enough-history: instead of a stranded line of cut-off
      // grey copy, show an inviting framed card with a calm ghost baseline and
      // a single supportive line so the section reads as a promise, not a dead
      // end.
      return Container(
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart_rounded, size: 20, color: colors.primary),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: Text(
                    'Your volume trend will appear here',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Log a few sessions and watch your weekly volume climb.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            RepaintBoundary(
              child: SizedBox(
                height: 40,
                child: CustomPaint(
                  size: const Size(double.infinity, 40),
                  painter: _GhostBaselinePainter(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final latest = weeklyVolumes.last;
    final weeks = weeklyVolumes.length;

    return Semantics(
      container: true,
      label:
          'Weekly volume trend over the last $weeks weeks. '
          'This week: ${latest.round()} kilograms.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly volume',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${formatCompactKg(latest)} kg',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            RepaintBoundary(
              child: SizedBox(
                height: 64,
                child: CustomPaint(
                  size: const Size(double.infinity, 64),
                  painter: _TrendPainter(
                    values: weeklyVolumes,
                    line: AppColors.accentElectricBlue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${weeks - 1}w ago',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  'This week',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.line});

  final List<double> values;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0) return;

    const dotRadius = 3.0;
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final scale = maxValue <= 0 ? 0.0 : 1.0 / maxValue;

    // Inset so the 2px stroke and the latest-point dot never clip.
    const inset = dotRadius + 1;
    final drawHeight = size.height - inset * 2;
    final stepX = (size.width - inset * 2) / (values.length - 1);

    Offset pointAt(int i) =>
        Offset(inset + stepX * i, inset + drawHeight * (1 - values[i] * scale));

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }

    // Flat fill under the line (≤10% alpha), down to the baseline.
    final fillPath = Path.from(path)
      ..lineTo(pointAt(values.length - 1).dx, size.height)
      ..lineTo(pointAt(0).dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = line.withValues(alpha: 0.08));

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // A dot on the latest point only.
    canvas.drawCircle(
      pointAt(values.length - 1),
      dotRadius,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.line != line;
}

/// A calm dashed baseline drawn for the first-run trend card — a quiet promise
/// of the line to come, never a stark empty box.
class _GhostBaselinePainter extends CustomPainter {
  const _GhostBaselinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final y = size.height - 3;
    const dash = 6.0;
    const gap = 6.0;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_GhostBaselinePainter oldDelegate) =>
      oldDelegate.color != color;
}
