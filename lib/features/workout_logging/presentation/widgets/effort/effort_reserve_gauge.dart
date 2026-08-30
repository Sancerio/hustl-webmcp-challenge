import 'package:flutter/material.dart';

import 'package:hustl_app/features/workout_logging/domain/utils/effort_scale.dart';
import 'package:hustl_app/features/workout_logging/presentation/utils/effort_intensity.dart';

/// A 6-pip "reserve gauge" showing a logged set's effort as reps in reserve.
///
/// Pips fill from the left = reps left in the tank when the set ended
/// ("gas left in the tank"); an empty tank (0 pips lit) means it was taken
/// to failure. Lit pips, the faintly-tinted empty pips, and the label all
/// follow the RIR intensity zone shared with the rest of the effort UI
/// ([rirColor]) — so the tank reads its intensity even with the label hidden.
///
/// Effort is optional on a set, so a `null` [rpe] renders nothing.
class EffortReserveGauge extends StatelessWidget {
  const EffortReserveGauge({
    super.key,
    required this.rpe,
    this.showLabel = true,
    this.pipSize = 6,
    this.pipGap = 2.5,
  });

  /// The set's stored RPE (1–10). Converted to RIR (0–6) for display.
  final int? rpe;

  /// Whether to trail the pips with the colour-coded RIR number.
  final bool showLabel;

  /// Width/height of each pip.
  final double pipSize;

  /// Horizontal gap between pips.
  final double pipGap;

  @override
  Widget build(BuildContext context) {
    if (rpe == null) return const SizedBox.shrink();

    final rir = EffortScale.rirFromRpe(rpe)!;
    final color = rirColor(rir);
    // Empty pips carry a tint of the zone colour so the tank reads its intensity
    // even at RIR 0 (empty red tank = taken to failure). Amber is perceptually
    // lighter, so it needs a stronger tint to hold the same weight as the rest.
    final emptyAlpha = (rir == 2 || rir == 3) ? 0.38 : 0.28;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 6; i++) ...[
          if (i != 0) SizedBox(width: pipGap),
          Container(
            width: pipSize,
            height: pipSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1.5),
              color: i < rir ? color : color.withValues(alpha: emptyAlpha),
            ),
          ),
        ],
        if (showLabel) ...[
          const SizedBox(width: 8),
          // Min-width, right-aligned slot so single digits and "6+" occupy at
          // least the same space — keeps the pips aligned in a column when
          // gauges stack (e.g. the exercise-history list) while still letting
          // the label grow instead of clipping at large text scale. Kept quiet
          // (small, semibold) so the pips carry the intensity and the
          // weight×reps stays the primary read.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(
              EffortScale.rirLabel(rir),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                // Neutral, not the zone colour: the pips carry the intensity, so
                // the number stays quiet precision instead of a colour badge.
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      label:
          'Effort: ${EffortScale.rirLabel(rir)} reps in reserve'
          '${rir <= 1 ? ', at or near failure' : ''}',
      child: ExcludeSemantics(child: row),
    );
  }
}
