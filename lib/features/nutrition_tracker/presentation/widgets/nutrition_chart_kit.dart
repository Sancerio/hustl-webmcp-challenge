import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared chart furniture for the nutrition screens (Insights energy chart,
/// Weight trend chart) so their axes + legends read as one system.

/// A sparse bottom date axis for an index-based (x = 0..n-1) fl_chart series:
/// shows ~4-5 non-overlapping 'MMM d' labels (always including the last point),
/// reservedSize 22. Pass the per-point [dates] aligned to the x indices.
SideTitles sparseDateSideTitles({
  required List<DateTime> dates,
  required ThemeData theme,
  DateFormat? format,
}) {
  final fmt = format ?? DateFormat('MMM d');
  final interval = math.max(1, (dates.length / 4).ceil());
  return SideTitles(
    showTitles: true,
    reservedSize: 22,
    interval: 1,
    getTitlesWidget: (value, meta) {
      final i = value.round();
      if (i < 0 || i >= dates.length) return const SizedBox.shrink();
      // Keep an evenly-spaced subset, but always label the most-recent point.
      final isLast = i == dates.length - 1;
      if (i % interval != 0 && !isLast) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          fmt.format(dates[i]),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

/// A legend swatch + label — a filled dot (default) or a short line segment for
/// reference/trend lines.
class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({
    super.key,
    required this.color,
    required this.label,
    this.line = false,
  });

  final Color color;
  final String label;

  /// Render the swatch as a short line (for a reference/trend line) instead of
  /// a dot (for a bar/area series).
  final bool line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        line
            ? Container(width: 14, height: 2.5, color: color)
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A slim (~6px) rounded, horizontal STACKED proportion bar. Each segment's
/// width is its fraction of the whole. Used for Strategy's macro split, the
/// data-quality meters, and Insights proportion rows.
class ProportionBar extends StatelessWidget {
  const ProportionBar({
    super.key,
    required this.segments,
    this.height = 6,
    this.gap = 2,
  });

  /// Ordered (fraction, colour) segments. Fractions should sum to ~1; any
  /// remainder renders as a faint track.
  final List<({double fraction, Color color})> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    final total = segments.fold<double>(
      0,
      (s, e) => s + math.max(0, e.fraction),
    );
    final remainder = math.max(0.0, 1 - total);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final seg in segments)
              if (seg.fraction > 0) ...[
                Expanded(
                  flex: (seg.fraction * 1000).round(),
                  child: Container(color: seg.color),
                ),
                if (gap > 0) SizedBox(width: gap),
              ],
            if (remainder > 0.001)
              Expanded(
                flex: (remainder * 1000).round(),
                child: Container(color: track),
              ),
          ],
        ),
      ),
    );
  }
}
