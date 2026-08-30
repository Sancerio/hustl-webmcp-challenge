import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active/workout_minimize_drag_handle.dart';

void main() {
  testWidgets('grabber has a distinct strip above the toolbar controls', (
    tester,
  ) async {
    var dragCanceled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 80,
            flexibleSpace: WorkoutMinimizeDragHandle(
              onDragStart: (_) {},
              onDragUpdate: (_) {},
              onDragEnd: (_) {},
              onDragCancel: () => dragCanceled = true,
            ),
            actions: const [
              SizedBox(key: Key('toolbarControl'), width: 40, height: 40),
            ],
          ),
        ),
      ),
    );

    final indicator = tester.getRect(
      find.byKey(const Key('workoutMinimizeDragIndicator')),
    );
    final rail = tester.getRect(
      find.byKey(const Key('workoutMinimizeDragHandle')),
    );
    final control = tester.getRect(find.byKey(const Key('toolbarControl')));
    expect(rail.width, 800);
    expect(rail.height, 32);
    expect(indicator.top, rail.top + 8);
    expect(indicator.bottom, lessThanOrEqualTo(control.top - 8));

    final detector = tester.widget<GestureDetector>(
      find.byKey(const Key('workoutMinimizeDragHandle')),
    );
    detector.onVerticalDragCancel!();
    await tester.pump();
    expect(dragCanceled, isTrue);
  });
}
