import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

class InsightsWeightChangeCard extends StatelessWidget {
  const InsightsWeightChangeCard({super.key, required this.data});

  final Map data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final observed = (data['observedDeltaKg'] as num?)?.toDouble();
    final expected = (data['expectedDeltaKg'] as num?)?.toDouble();
    if (observed == null) return const SizedBox.shrink();

    String fmt(double? v) => v == null
        ? '—'
        : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} kg';

    final range = [
      observed.abs(),
      if (expected != null) expected.abs(),
      0.5,
    ].reduce((a, b) => a > b ? a : b);

    double pos(double v) => ((v / (range * 2)) + 0.5).clamp(0.0, 1.0);

    final accent = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Weight change'),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.cardRadius,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label:
                    'Weight change bar. Observed ${fmt(observed)}, expected ${fmt(expected)}.',
                excludeSemantics: true,
                child: SizedBox(
                  height: 18,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: w * 0.5 - 1,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 2,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          Positioned(
                            left: (w * pos(observed)) - 6,
                            top: 0,
                            child: _Marker(color: accent),
                          ),
                          if (expected != null)
                            Positioned(
                              left: (w * pos(expected)) - 6,
                              top: 0,
                              child: _Marker(
                                color: theme.colorScheme.onSurfaceVariant,
                                dashed: true,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _StatLineRow(
                label: 'Observed',
                value: fmt(observed),
                valueColor: accent,
              ),
              const Divider(),
              _StatLineRow(label: 'Expected', value: fmt(expected)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatLineRow extends StatelessWidget {
  const _StatLineRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 18,
      child: CustomPaint(
        painter: _MarkerPainter(color: color, dashed: dashed),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 2, size.width, size.height - 2),
      const Radius.circular(4),
    );
    if (!dashed) {
      canvas.drawRRect(r, paint);
      return;
    }

    final dashPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    const top = 3.0;
    final bottom = size.height - 1;
    const dash = 3.0;
    const gap = 2.0;
    var y = top;
    while (y < bottom) {
      final y2 = (y + dash).clamp(top, bottom);
      canvas.drawLine(Offset(x, y), Offset(x, y2), dashPaint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}
