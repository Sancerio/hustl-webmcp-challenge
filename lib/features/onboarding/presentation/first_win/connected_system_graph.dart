import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';

/// The signature "Building your plan" reveal + coaching readiness.
///
/// The HEADLINE is a single depth-weighted **Coach readiness** progress ring
/// (the app's signature data-viz), with the four pillar nodes (Workouts →
/// Nutrition → Health → Coaching) underneath as the INPUTS that fill it. A pulse
/// flows along the connectors so "your data compounds into one coach" reads as a
/// felt mechanic.
class ConnectedSystemGraph extends StatefulWidget {
  const ConnectedSystemGraph({
    super.key,
    required this.readiness,
    required this.filledCount,
    this.readinessNote,
    this.animateReveal = true,
  });

  /// Headline coach-readiness score, 0..1 (depth-weighted, not pillar count).
  final double readiness;

  /// How many of the four pillars currently have ANY data (drives node visuals).
  final int filledCount;

  /// Optional caption under the inputs, e.g. "Add meals + weight to sharpen".
  final String? readinessNote;

  /// Whether to play the one-shot reveal on mount (off for screenshots/tests).
  final bool animateReveal;

  static const List<_Pillar> _pillars = [
    _Pillar('Workouts', Icons.fitness_center_rounded),
    _Pillar('Nutrition', Icons.local_fire_department_rounded),
    _Pillar('Health', Icons.favorite_rounded),
    _Pillar('Coaching', Icons.auto_awesome_rounded),
  ];

  @override
  State<ConnectedSystemGraph> createState() => _ConnectedSystemGraphState();
}

class _ConnectedSystemGraphState extends State<ConnectedSystemGraph>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.animateReveal && !reduceMotion) {
      _reveal.forward();
      _pulse.repeat();
    } else {
      _reveal.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filled = widget.filledCount.clamp(
      0,
      ConnectedSystemGraph._pillars.length,
    );
    final activeConnector =
        filled.clamp(0, ConnectedSystemGraph._pillars.length - 1) - 1;
    final pct = (widget.readiness.clamp(0.0, 1.0) * 100).round();
    final reveal = CurvedAnimation(
      parent: _reveal,
      curve: AppMotion.enterCurve,
    );

    return RepaintBoundary(
      child: FadeTransition(
        opacity: reveal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Headline: the readiness ring (signature data-viz).
            Center(
              child: AppProgressRing(
                progress: widget.readiness,
                size: 128,
                strokeWidth: 12,
                color: AppColors.accentEmeraldGreen,
                semanticsLabel: 'Coach readiness $pct percent',
                child: AnimatedMetricText(
                  value: pct.toDouble(),
                  suffix: '%',
                  style: AppTextStyles.metricEmphasis(context),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Coach readiness',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            // Inputs: the four pillars feeding the ring. Decorative — the ring
            // above already carries the readiness semantics.
            ExcludeSemantics(
              child: Row(
                children: [
                  for (
                    var i = 0;
                    i < ConnectedSystemGraph._pillars.length;
                    i++
                  ) ...[
                    Expanded(
                      child: _PillarNode(
                        pillar: ConnectedSystemGraph._pillars[i],
                        filled: i < filled,
                        isNext: i == filled,
                      ),
                    ),
                    if (i < ConnectedSystemGraph._pillars.length - 1)
                      _FlowConnector(
                        pulse: _pulse,
                        lit: i < filled - 1,
                        active: i == activeConnector,
                      ),
                  ],
                ],
              ),
            ),
            if (widget.readinessNote != null) ...[
              const SizedBox(height: AppSpacing.x1 + 4),
              Text(
                widget.readinessNote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pillar {
  const _Pillar(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _PillarNode extends StatelessWidget {
  const _PillarNode({
    required this.pillar,
    required this.filled,
    required this.isNext,
  });

  final _Pillar pillar;
  final bool filled;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = AppColors.accentEmeraldGreen;
    final ring = filled
        ? accent
        : (isNext
              ? colors.primary.withValues(alpha: 0.5)
              : colors.outlineVariant);

    return Column(
      children: [
        AnimatedContainer(
          duration: AppMotion.medium,
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? accent.withValues(alpha: 0.14)
                : colors.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(color: ring, width: filled ? 1.5 : 1),
          ),
          child: Icon(
            filled ? Icons.check_rounded : pillar.icon,
            size: 18,
            color: filled
                ? accent
                : (isNext ? colors.primary : colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          pillar.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: filled || isNext
                ? colors.onSurface
                : colors.onSurfaceVariant.withValues(alpha: 0.7),
            fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The line between two pillars. Lit (solid emerald) when both ends have data;
/// for the active edge a pulse travels along it toward the dormant pillar.
class _FlowConnector extends StatelessWidget {
  const _FlowConnector({
    required this.pulse,
    required this.lit,
    required this.active,
  });

  final Animation<double> pulse;
  final bool lit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = lit
        ? AppColors.accentEmeraldGreen.withValues(alpha: 0.55)
        : colors.outlineVariant.withValues(alpha: 0.6);

    return SizedBox(
      width: 16,
      height: 44,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 2, color: base),
            if (active)
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(pulse.value);
                  return Align(
                    alignment: Alignment(-1 + 2 * t, 0),
                    child: Opacity(
                      opacity: (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0),
                      child: Container(
                        width: 7,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: AppRadius.pillRadius,
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
