import 'package:flutter/material.dart';

import '../../../../../app/theme/app_spacing.dart';

/// Direct-manipulation affordance for the narrow active-workout sheet.
///
/// The full-width transparent rail is intentionally larger than the visual
/// handle. Workout-list scrolling remains untouched because only this dedicated
/// header zone owns the vertical drag recognizer.
class WorkoutMinimizeDragHandle extends StatelessWidget {
  const WorkoutMinimizeDragHandle({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragCancelCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Semantics(
        label: 'Drag down to minimize workout',
        child: GestureDetector(
          key: const Key('workoutMinimizeDragHandle'),
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: onDragStart,
          onVerticalDragUpdate: onDragUpdate,
          onVerticalDragEnd: onDragEnd,
          onVerticalDragCancel: onDragCancel,
          child: SizedBox(
            width: double.infinity,
            height: AppSpacing.x4,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.x1),
                child: Container(
                  key: const Key('workoutMinimizeDragIndicator'),
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
