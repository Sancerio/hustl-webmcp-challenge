import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';

/// The "your first climb" trail-plan card on the redesigned welcome screen:
/// a flat surface (matching the Settings-screen hairline-card idiom — no
/// gradients or shadows) holding three waypoint rows threaded by a dashed
/// connector, echoing the mountain route above. Step 1 reads as "you are
/// here"; the rest are ahead on the same climb.
///
/// On web (no Health Connect / HealthKit), [showRecovery] is false: the
/// recovery waypoint is hidden and the remaining two steps renumber to 1-2,
/// matching the CTA hierarchy's web fallback on the parent screen.
class OnboardingTrailPlanCard extends StatelessWidget {
  const OnboardingTrailPlanCard({
    super.key,
    required this.showRecovery,
    required this.onConnectRecovery,
    required this.onStartWorkout,
    required this.onImportStrong,
  });

  final bool showRecovery;
  final VoidCallback onConnectRecovery;
  final VoidCallback onStartWorkout;
  final VoidCallback onImportStrong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final steps = <_WaypointSpec>[
      if (showRecovery)
        _WaypointSpec(
          title: 'Connect recovery',
          body: 'Sleep, HRV and heart rate tune every plan you get.',
          chip: 'One tap',
          chipTint: colors.primary,
          semanticsHint: 'Connect recovery data',
          onTap: onConnectRecovery,
        ),
      _WaypointSpec(
        title: 'Start a workout',
        body: 'Log your first set in 30 seconds. No account needed.',
        chip: '30 sec',
        chipTint: colors.onSurfaceVariant,
        semanticsHint: 'Start your first workout',
        onTap: onStartWorkout,
      ),
      _WaypointSpec(
        title: 'Bring Strong history',
        body: 'Your PRs and progress come with you.',
        chip: 'Optional',
        chipTint: colors.onSurfaceVariant,
        semanticsHint: 'Bring your Strong workout history',
        onTap: onImportStrong,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your first climb',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 + 4),
          for (var i = 0; i < steps.length; i++)
            _WaypointRow(
              index: i + 1,
              here: i == 0,
              last: i == steps.length - 1,
              spec: steps[i],
            ),
        ],
      ),
    );
  }
}

class _WaypointSpec {
  const _WaypointSpec({
    required this.title,
    required this.body,
    required this.chip,
    required this.chipTint,
    required this.semanticsHint,
    required this.onTap,
  });

  final String title;
  final String body;
  final String chip;
  final Color chipTint;
  final String semanticsHint;
  final VoidCallback onTap;
}

class _WaypointRow extends StatelessWidget {
  const _WaypointRow({
    required this.index,
    required this.here,
    required this.last,
    required this.spec,
  });

  final int index;
  final bool here;
  final bool last;
  final _WaypointSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      button: true,
      label:
          '${here ? 'You are here. ' : ''}Step $index: ${spec.title}. '
          '${spec.body}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: spec.onTap,
          borderRadius: AppRadius.controlRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 - 2),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: here ? colors.primary : Colors.transparent,
                            border: Border.all(
                              color: here
                                  ? colors.primary
                                  : colors.outlineVariant,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            '$index',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: here
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (!last)
                          SizedBox(
                            width: 22,
                            height: 32,
                            child: CustomPaint(
                              painter: _DashedConnectorPainter(
                                color: colors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1 + 4),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: last ? 0 : AppSpacing.x1 + 2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  spec.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.x1),
                              AppChip(
                                label: spec.chip,
                                variant: AppChipVariant.status,
                                color: spec.chipTint,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            spec.body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed vertical connector between waypoint dots — the trail-plan's own
/// small echo of the mountain route's dashed "ahead" styling.
class _DashedConnectorPainter extends CustomPainter {
  const _DashedConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.35);
    const dash = 5.0, gap = 5.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedConnectorPainter old) => old.color != color;
}
