import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// The visual language of a legend swatch, matched to its on-chart series.
enum ChartSwatch {
  /// A connecting line with no marker (e.g. raw scale weigh-ins as a line).
  line,

  /// A line with a ringed/hollow centre dot (the hero trend/expenditure line).
  lineDot,

  /// A line with a hollow square marker (a secondary "holding" state).
  lineSquare,

  /// A filled triangle wedge — an area/range band.
  band,

  /// A row of small filled dots — discrete daily points.
  dots,
}

/// One legend entry. When [onTap] is set the entry doubles as a show/hide toggle
/// (dimmed when inactive), exactly like MacroFactor's tappable legend.
class ChartLegendEntry {
  const ChartLegendEntry({
    required this.swatch,
    required this.color,
    required this.label,
    this.active = true,
    this.onTap,
  });

  final ChartSwatch swatch;
  final Color color;
  final String label;
  final bool active;
  final VoidCallback? onTap;
}

/// A standalone legend card sitting beneath the range selector, mirroring the
/// reference: a quiet surface holding the series swatches, centered and evenly
/// spaced.
class ChartLegendCard extends StatelessWidget {
  const ChartLegendCard({super.key, required this.entries});

  final List<ChartLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.x3),
            Flexible(
              child: _LegendChip(entry: entries[i], ringColor: colors.surface),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.entry, required this.ringColor});

  final ChartLegendEntry entry;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Opacity(
      opacity: entry.active ? 1 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 14,
            child: CustomPaint(
              painter: _SwatchPainter(
                swatch: entry.swatch,
                color: entry.color,
                ringColor: ringColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    if (entry.onTap == null) return chip;
    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.x1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: chip,
      ),
    );
  }
}

/// Paints each swatch so it reads as the exact series it labels.
class _SwatchPainter extends CustomPainter {
  _SwatchPainter({
    required this.swatch,
    required this.color,
    required this.ringColor,
  });

  final ChartSwatch swatch;
  final Color color;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final center = Offset(size.width / 2, midY);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;

    switch (swatch) {
      case ChartSwatch.dots:
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        for (final fx in const [0.18, 0.5, 0.82]) {
          canvas.drawCircle(Offset(size.width * fx, midY), 2, fill);
        }
      case ChartSwatch.line:
        canvas.drawLine(Offset(0, midY), Offset(size.width, midY), line);
      case ChartSwatch.lineDot:
        canvas.drawLine(Offset(0, midY), Offset(size.width, midY), line);
        _hollowMarker(canvas, center, isSquare: false);
      case ChartSwatch.lineSquare:
        canvas.drawLine(Offset(0, midY), Offset(size.width, midY), line);
        _hollowMarker(canvas, center, isSquare: true);
      case ChartSwatch.band:
        final path = Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width, 2)
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..style = PaintingStyle.fill,
        );
    }
  }

  /// A hollow marker (ring or square) punched out of the card with [ringColor].
  void _hollowMarker(Canvas canvas, Offset center, {required bool isSquare}) {
    final fill = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    if (isSquare) {
      final rect = Rect.fromCenter(center: center, width: 7, height: 7);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    } else {
      canvas.drawCircle(center, 3.4, fill);
      canvas.drawCircle(center, 3.4, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.swatch != swatch ||
      old.color != color ||
      old.ringColor != ringColor;
}
