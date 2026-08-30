import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// Direction of a short-window change, shown as an icon + word in the reference.
enum ChangeDirection { increase, decrease, steady }

extension on ChangeDirection {
  IconData get icon => switch (this) {
    ChangeDirection.increase => Icons.trending_up,
    ChangeDirection.decrease => Icons.trending_down,
    ChangeDirection.steady => Icons.trending_flat,
  };

  String get word => switch (this) {
    ChangeDirection.increase => 'Increase',
    ChangeDirection.decrease => 'Decrease',
    ChangeDirection.steady => 'Steady',
  };
}

/// Classifies a signed delta into a direction with a small dead-band so tiny
/// noise reads as "Steady" rather than flickering up/down.
ChangeDirection directionOf(double delta, {double deadband = 0}) {
  if (delta > deadband) return ChangeDirection.increase;
  if (delta < -deadband) return ChangeDirection.decrease;
  return ChangeDirection.steady;
}

/// One row of the changes card: a window label, a mini sparkline, the delta
/// value, and the trend direction.
class ChartChangeRow {
  const ChartChangeRow({
    required this.label,
    required this.sparkline,
    required this.valueText,
    required this.direction,
  });

  final String label;
  final List<double> sparkline;
  final String valueText;
  final ChangeDirection direction;
}

/// The "Insights & Data" change card from the reference: a titled card with
/// per-window rows (3-day / 7-day), each pairing a sparkline + delta + direction.
class ChartChangesCard extends StatelessWidget {
  const ChartChangesCard({
    super.key,
    required this.title,
    required this.accentColor,
    required this.rows,
  });

  final String title;
  final Color accentColor;
  final List<ChartChangeRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: AppSpacing.x2,
                color: theme.colorScheme.outlineVariant,
              ),
            _ChangeRow(row: rows[i], accentColor: accentColor),
          ],
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.row, required this.accentColor});

  final ChartChangeRow row;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            row.label,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        SizedBox(
          width: 44,
          height: 24,
          child: CustomPaint(
            painter: _SparklinePainter(values: row.sparkline, color: accentColor),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: Text(
            row.valueText,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Icon(row.direction.icon, size: 18, color: muted),
        const SizedBox(width: 6),
        Text(
          row.direction.word,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// A tiny filled sparkline (area + line) for a single change row.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final dx = size.width / (values.length - 1);
    double yOf(double v) => size.height - ((v - lo) / span) * size.height;

    final path = Path()..moveTo(0, yOf(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(i * dx, yOf(values[i]));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
