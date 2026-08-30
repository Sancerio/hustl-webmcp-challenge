import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/workout_logging/presentation/widgets/home/quick_start_sheet.dart';

/// Pumps a tiny router whose only route opens the [QuickStartSheet], then taps
/// the opener so the sheet is on screen and ready to assert against.
Future<void> _openSheet(
  WidgetTester tester, {
  required bool hasLastSession,
  String? lastSessionName,
  bool hasPreviousSessions = false,
  VoidCallback? onRepeatLast,
  VoidCallback? onRepeatPrevious,
  VoidCallback? onFromTemplate,
  VoidCallback? onEmpty,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () => QuickStartSheet.show(
              context,
              hasLastSession: hasLastSession,
              lastSessionName: lastSessionName,
              hasPreviousSessions: hasPreviousSessions,
              onRepeatLast: onRepeatLast ?? () {},
              onRepeatPrevious: onRepeatPrevious ?? () {},
              onFromTemplate: onFromTemplate ?? () {},
              onEmpty: onEmpty ?? () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows all three rows when there is a last session', (
    tester,
  ) async {
    await _openSheet(tester, hasLastSession: true, lastSessionName: 'Push Day');

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('Repeat Push Day'), findsOneWidget);
    expect(find.text('From a template'), findsOneWidget);
    expect(find.text('Empty workout'), findsOneWidget);
  });

  testWidgets('hides the repeat row when there is no last session', (
    tester,
  ) async {
    await _openSheet(tester, hasLastSession: false, lastSessionName: null);

    expect(find.textContaining('Repeat'), findsNothing);
    expect(find.text('From a template'), findsOneWidget);
    expect(find.text('Empty workout'), findsOneWidget);
  });

  testWidgets('tapping repeat pops the sheet and fires onRepeatLast', (
    tester,
  ) async {
    var repeated = 0;
    await _openSheet(
      tester,
      hasLastSession: true,
      lastSessionName: 'Push Day',
      onRepeatLast: () => repeated++,
    );

    await tester.tap(find.text('Repeat Push Day'));
    await tester.pumpAndSettle();

    expect(repeated, 1);
    // Sheet dismissed.
    expect(find.text('Start a workout'), findsNothing);
  });

  testWidgets('tapping from a template fires onFromTemplate', (tester) async {
    var fromTemplate = 0;
    await _openSheet(
      tester,
      hasLastSession: true,
      lastSessionName: 'Push Day',
      onFromTemplate: () => fromTemplate++,
    );

    await tester.tap(find.text('From a template'));
    await tester.pumpAndSettle();

    expect(fromTemplate, 1);
    expect(find.text('Start a workout'), findsNothing);
  });

  testWidgets('tapping empty workout fires onEmpty', (tester) async {
    var empty = 0;
    await _openSheet(
      tester,
      hasLastSession: false,
      lastSessionName: null,
      onEmpty: () => empty++,
    );

    await tester.tap(find.text('Empty workout'));
    await tester.pumpAndSettle();

    expect(empty, 1);
    expect(find.text('Start a workout'), findsNothing);
  });

  testWidgets(
    'shows the previous-workout row and fires onRepeatPrevious when there is '
    'more than one session',
    (tester) async {
      var picked = 0;
      await _openSheet(
        tester,
        hasLastSession: true,
        lastSessionName: 'Push Day',
        hasPreviousSessions: true,
        onRepeatPrevious: () => picked++,
      );

      expect(find.text('Repeat a previous workout'), findsOneWidget);

      await tester.tap(find.text('Repeat a previous workout'));
      await tester.pumpAndSettle();

      expect(picked, 1);
      expect(find.text('Start a workout'), findsNothing);
    },
  );

  testWidgets('hides the previous-workout row without prior sessions', (
    tester,
  ) async {
    await _openSheet(
      tester,
      hasLastSession: true,
      lastSessionName: 'Push Day',
    );

    expect(find.text('Repeat a previous workout'), findsNothing);
  });
}
