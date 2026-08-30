import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';

/// Mirrors the "Best sets" mini-table row inside `HistorySessionCard`
/// (`_ExerciseBestSetTable`, `history_session_card.dart`): exercise name on
/// the left, a compact labelled [EffortReserveGauge] plus the best-set label
/// right-aligned on the right — both Expanded halves of a 2-column table.
/// The gauge shows its label here (unlike the default-size gauge elsewhere)
/// so a RIR-0 failure best set is unambiguous even though the pips alone
/// would render as an empty tank. Kept as a small harness (rather than
/// mounting the full session card, which needs a complete
/// `WorkoutSession`/`HistorySessionMetrics` fixture) so the golden stays
/// focused on the compact-gauge layout that changed. Includes a narrow
/// (320px) width with a long exercise name to confirm the mini-table never
/// overflows.
class _BestSetRowHarness extends StatelessWidget {
  const _BestSetRowHarness();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row({required String name, required String label, int? rpe}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (rpe != null) ...[
                    EffortReserveGauge(
                      rpe: rpe,
                      showLabel: true,
                      pipSize: 5,
                      pipGap: 2,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            row(name: 'Bench Press (Barbell)', label: '100 kg × 5', rpe: 8),
            const Divider(),
            row(name: 'Back Squat', label: '140 kg × 3'),
            const Divider(),
            row(
              name: 'Incline Dumbbell Press With A Very Long Custom Name',
              label: '22.5 kg × 12',
              rpe: 10,
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> pumpHarness(
    WidgetTester tester,
    ThemeData theme, {
    double width = 420,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(width * 2, 300 * 2);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(body: _BestSetRowHarness()),
      ),
    );
    await tester.pump();
  }

  testWidgets('history best-set rows with compact effort gauge — light', (
    tester,
  ) async {
    await pumpHarness(tester, AppTheme.lightTheme);

    await expectLater(
      find.byType(_BestSetRowHarness),
      matchesGoldenFile('goldens/history_best_set_row_light.png'),
    );
  });

  testWidgets('history best-set rows with compact effort gauge — dark', (
    tester,
  ) async {
    await pumpHarness(tester, AppTheme.darkTheme);

    await expectLater(
      find.byType(_BestSetRowHarness),
      matchesGoldenFile('goldens/history_best_set_row_dark.png'),
    );
  });

  testWidgets(
    'history best-set rows on a narrow phone width with a long exercise '
    'name do not overflow',
    (tester) async {
      await pumpHarness(tester, AppTheme.lightTheme, width: 320);

      expect(tester.takeException(), isNull);
    },
  );
}
