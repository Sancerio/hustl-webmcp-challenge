import 'package:flutter/material.dart';

/// Visual heart of the Sonar watch card: a watch glyph inside a soft tinted
/// disc, with searching "sonar" rings rippling outward behind it.
///
/// The medallion owns no animation of its own — the parent card drives a single
/// repeating controller and passes its progress in via [phase] (0..1). When the
/// state resolves to connected, the parent swaps the glyph for a check and stops
/// the controller; this widget simply renders whatever it is handed.
class WatchRecordingMedallion extends StatelessWidget {
  const WatchRecordingMedallion({
    super.key,
    required this.phase,
    required this.showRings,
    required this.glyph,
    required this.discColor,
  }) : assert(phase >= 0);

  /// Repeating controller progress (0..1). Frozen by the parent in
  /// reduced-motion mode so a single faint ring stays put.
  final double phase;

  /// Whether the sonar rings should be painted. False in resolved states
  /// (connected/recording) where the rings would be noise.
  final bool showRings;

  /// Centered glyph (watch icon while searching, check when connected).
  final Widget glyph;

  /// Fill of the inner disc behind the glyph.
  final Color discColor;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRings)
            Positioned.fill(
              child: CustomPaint(
                painter: SonarPainter(phase: phase, color: primary),
              ),
            ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: discColor),
            alignment: Alignment.center,
            child: glyph,
          ),
        ],
      ),
    );
  }
}

/// Paints two phase-offset expanding rings that fade as they grow — a calm
/// radar sweep, no rotation and no glow bloom.
class SonarPainter extends CustomPainter {
  const SonarPainter({required this.phase, required this.color});

  /// Controller progress in 0..1.
  final double phase;

  /// Ring stroke colour (the brand primary); per-ring alpha is derived here.
  final Color color;

  static const double _baseRadius = 24;
  static const double _spanRadius = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      final radius = _baseRadius + p * _spanRadius;
      final alpha = (1 - p) * 0.28;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(SonarPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
