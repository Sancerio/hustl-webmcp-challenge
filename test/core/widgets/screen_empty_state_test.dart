import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows icon, title and message', (tester) async {
    await tester.pumpWidget(
      _host(
        const ScreenEmptyState(
          icon: Icons.fitness_center,
          title: 'No workouts yet',
          message: 'Log your first session to see it here.',
        ),
      ),
    );

    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.text('Log your first session to see it here.'), findsOneWidget);
  });

  testWidgets('renders the CTA only when both label and handler are given', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ScreenEmptyState(
          icon: Icons.info,
          title: 'Empty',
          actionLabel: 'Start',
        ),
      ),
    );

    // Missing onAction => no button.
    expect(find.widgetWithText(FilledButton, 'Start'), findsNothing);
  });

  testWidgets('invokes the CTA callback', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _host(
        ScreenEmptyState(
          icon: Icons.add,
          title: 'Empty',
          actionLabel: 'Start',
          onAction: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();

    expect(pressed, isTrue);
  });
}
